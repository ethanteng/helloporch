// Records the 3-way calling film (app/(site)/features/three-way/Film.tsx) to a 1080 × 1920 MP4. Headless Chrome steps
// through the film one frame at a time over the DevTools protocol, and scripts/encode-frames.swift encodes the
// frames with AVFoundation, so it needs macOS with Google Chrome but nothing else.
//
// Start `npm run dev` first, then: node scripts/render-three-way-film.mjs [out.mp4] [http://localhost:3000]
import { execFileSync, spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FPS = 30;
const out = resolve(process.argv[2] ?? "three-way-calling.mp4");
const site = process.argv[3] ?? "http://localhost:3000";

const profile = await mkdtemp(join(tmpdir(), "porch-film-chrome-"));
const frames = await mkdtemp(join(tmpdir(), "porch-film-frames-"));
const chrome = spawn(
  CHROME,
  ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "--hide-scrollbars", "--force-color-profile=srgb", "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] },
);

try {
  const endpoint = await new Promise((found, fail) => {
    let log = "";
    chrome.stderr.on("data", (chunk) => {
      log += chunk;
      const match = log.match(/DevTools listening on (ws:\/\/\S+)/);
      if (match) found(match[1]);
    });
    chrome.on("exit", (code) => fail(new Error(`Chrome exited (${code}):\n${log}`)));
  });

  const devtools = await connect(endpoint);
  const { targetId } = await devtools.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await devtools.send("Target.attachToTarget", { targetId, flatten: true });
  const page = (method, params) => devtools.send(method, params, sessionId);
  const evaluate = async (expression) => {
    const { result, exceptionDetails } = await page("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text);
    return result.value;
  };

  // The film is laid out at 540 × 960 and captured at twice that.
  await page("Emulation.setDeviceMetricsOverride", { width: 540, height: 960, deviceScaleFactor: 2, mobile: false });
  await page("Page.enable");
  const loaded = devtools.next((message) => message.method === "Page.loadEventFired" && message.sessionId === sessionId);
  await page("Page.navigate", { url: `${site}/features/three-way/film?render` });
  await loaded;

  // Wait for the film, its fonts and any photos, and hide the dev server's badge.
  const duration = await evaluate(`(async () => {
    for (let i = 0; !window.__film; i++) {
      if (i > 200) throw new Error("The film didn't load. Is this the Porch dev server?");
      await new Promise((r) => setTimeout(r, 50));
    }
    await document.fonts.ready;
    await Promise.all([...document.images].map((image) => image.decode().catch(() => {})));
    const hide = document.createElement("style");
    hide.textContent = "nextjs-portal { display: none !important; }";
    document.head.append(hide);
    return window.__film.duration;
  })()`);

  const total = Math.round(duration * FPS);
  for (let i = 0; i < total; i++) {
    await evaluate(`window.__film.seek(${i / FPS})`);
    const { data } = await page("Page.captureScreenshot", { format: "png" });
    await writeFile(join(frames, `${String(i).padStart(5, "0")}.png`), Buffer.from(data, "base64"));
    if (i % FPS === 0) process.stdout.write(`\rCaptured ${i} of ${total} frames`);
  }
  process.stdout.write(`\rCaptured ${total} of ${total} frames\n`);
  devtools.close();
  chrome.kill();

  execFileSync("swift", [join(import.meta.dirname, "encode-frames.swift"), frames, String(FPS), out], { stdio: "inherit" });
} finally {
  chrome.kill();
  await rm(frames, { recursive: true, force: true });
  await rm(profile, { recursive: true, force: true });
}

/** A minimal DevTools protocol client over Node's WebSocket. */
async function connect(url) {
  const socket = new WebSocket(url);
  await new Promise((open, fail) => {
    socket.onopen = open;
    socket.onerror = () => fail(new Error(`Couldn't connect to ${url}`));
  });
  let lastID = 0;
  const pending = new Map();
  const waiters = new Set();
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    const call = pending.get(message.id);
    if (call) {
      pending.delete(message.id);
      if (message.error) call.fail(new Error(`${call.method}: ${message.error.message}`));
      else call.done(message.result);
      return;
    }
    for (const waiter of waiters) {
      if (waiter.matches(message)) {
        waiters.delete(waiter);
        waiter.done(message);
      }
    }
  };
  return {
    send: (method, params = {}, sessionId) =>
      new Promise((done, fail) => {
        const id = ++lastID;
        pending.set(id, { method, done, fail });
        socket.send(JSON.stringify({ id, method, params, sessionId }));
      }),
    next: (matches) => new Promise((done) => waiters.add({ matches, done })),
    close: () => socket.close(),
  };
}
