// A translated call without phones: "mom" (the bedside) and "ethan" join a test room, the translator is dispatched
// into it, and each plays recorded sentences in turn. Reports what the translator heard and said, how long after each
// sentence ended its words and voice arrived, and saves what each side heard as a WAV file to listen to.
//
//   node scripts/call-test.ts <folder with clips.json and 16 kHz s16le .pcm clips> [clip ids in order...]
//
// Uses LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET for the room, and a translator worker already running
// (`npm run dev`) against the same server. Clips whose id starts with "m" are Mom's; the rest are Ethan's.
import { readFileSync, writeFileSync } from "node:fs";
import { join as path } from "node:path";
import { AudioFrame, AudioSource, AudioStream, LocalAudioTrack, Room, RoomEvent, TrackKind, TrackPublishOptions, TrackSource,
  type RemoteTrack } from "@livekit/rtc-node";
import { AccessToken, AgentDispatchClient } from "livekit-server-sdk";
import { agentName, topics, trackNames } from "../src/agent.ts";
import type { Message } from "../src/interpreter.ts";

const [folder, ...order] = process.argv.slice(2);
const url = process.env.LIVEKIT_URL!, key = process.env.LIVEKIT_API_KEY!, secret = process.env.LIVEKIT_API_SECRET!;
if (!folder || !url || !key || !secret) throw new Error("Give the clips folder, and set LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET.");
const clips: { id: string; text: string }[] = JSON.parse(readFileSync(path(folder, "clips.json"), "utf8"));
const script = order.length ? order.map(id => clips.find(c => c.id === id)!) : clips;
const roomName = `translation-test-${Date.now()}`;
const started = Date.now();
const at = () => `${((Date.now() - started) / 1000).toFixed(1)}s`.padStart(6);

type Caller = { room: Room; source: AudioSource; heard: Int16Array[]; firstVoiceAfter?: number };
async function join(identity: string, name: string): Promise<Caller> {
  const token = new AccessToken(key, secret, { identity, name, ttl: "10m" });
  token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true, canPublishData: false });
  const room = new Room();
  await room.connect(url, await token.toJwt(), { autoSubscribe: true, dynacast: false });
  const source = new AudioSource(16_000, 1);
  await room.localParticipant!.publishTrack(LocalAudioTrack.createAudioTrack("microphone", source), new TrackPublishOptions({ source: TrackSource.SOURCE_MICROPHONE }));
  const caller: Caller = { room, source, heard: [] };
  const mine = trackNames[identity === "mom" ? "bedside" : "family"];
  room.on(RoomEvent.TrackSubscribed, (track: RemoteTrack, publication) => {
    if (track.kind !== TrackKind.KIND_AUDIO || !publication.name?.startsWith("porch-translation")) return;
    // As the apps do (ios/Porch/CallTranslation.swift): leave the other side's translation.
    if (publication.name !== mine) { publication.setSubscribed(false); return; }
    void (async () => {
      const reader = new AudioStream(track, 24_000, 1).getReader();
      for (;;) {
        const { value: frame, done } = await reader.read();
        if (done) break;
        caller.heard.push(new Int16Array(frame.data));
        if (caller.firstVoiceAfter === 0 && frame.data.some((s: number) => Math.abs(s) > 500)) caller.firstVoiceAfter = Date.now();
      }
    })();
  });
  room.on(RoomEvent.TrackUnsubscribed, (_track, publication) => {
    if (publication.name?.startsWith("porch-translation")) console.log(`${at()} ${publication.name === mine ? "✗" : "✓"} ${identity} no longer receives ${publication.name}`);
  });
  room.on(RoomEvent.DataReceived, (payload, participant, _kind, topic) => {
    if (topic !== topics.lines) return;
    const message = JSON.parse(new TextDecoder().decode(payload)) as Message;
    if (message.type === "line") {
      const tag = identity === "mom" ? "mom sees" : "ethan sees";
      console.log(`${at()} ${tag}: [${message.name}] heard «${message.heard}»${message.said ? ` → said «${message.said}»` : " (already in their language)"}`);
      lineAt ??= Date.now();
    } else if (message.type === "speaking") {
      console.log(`${at()}   ${identity}: translator ${message.on ? "started" : "stopped"} speaking (voices ${message.on ? "lowered" : "back"})`);
    } else if (message.type === "state") console.log(`${at()} ${identity}: translation ${message.on ? "on" : "off"} (${message.language}) from ${participant?.identity}`);
  });
  return caller;
}

let lineAt: number | undefined;
async function play(caller: Caller, clip: string) {
  const pcm = readFileSync(path(folder, `${clip}.pcm`));
  const samples = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.length / 2);
  for (let i = 0; i < samples.length; i += 160) {
    const frame = samples.slice(i, i + 160);
    await caller.source.captureFrame(new AudioFrame(frame, 16_000, 1, frame.length));
  }
  // Wait until the sentence has actually been sent, not just queued: the end of speech is now.
  await caller.source.waitForPlayout();
  const ended = Date.now();
  // Silence afterwards, so recognition hears the sentence end.
  for (let i = 0; i < 100; i++) await caller.source.captureFrame(new AudioFrame(new Int16Array(160), 16_000, 1, 160));
  return ended;
}

function wav(samples: Int16Array[], path: string) {
  const data = Buffer.concat(samples.map(s => Buffer.from(s.buffer, s.byteOffset, s.byteLength)));
  const header = Buffer.alloc(44);
  header.write("RIFF", 0); header.writeUInt32LE(36 + data.length, 4); header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22); header.writeUInt32LE(24_000, 24);
  header.writeUInt32LE(48_000, 28); header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34); header.write("data", 36); header.writeUInt32LE(data.length, 40);
  writeFileSync(path, Buffer.concat([header, data]));
}

const mom = await join("mom", "Mom"), ethan = await join("ethan", "Ethan");
const dispatch = new AgentDispatchClient(url.replace(/^ws/, "http"), key, secret);
await dispatch.createDispatch(roomName, agentName, { metadata: JSON.stringify({ bedside: "mom", bedsideLanguage: "zh-Hant",
  bedsideVoice: "Z8Aisvg1z70p27kGvkZZ", familyLanguage: "en", familyVoice: "OYTbf65OHHFELVut7v2H" }) });
console.log(`${at()} dispatched the translator into ${roomName}`);
for (let waited = 0; ![...mom.room.remoteParticipants.values()].some(p => p.attributes["porch.translator"] === "1"); waited++) {
  if (waited > 300) throw new Error("The translator didn't join. Is `npm run dev` running against this server?");
  await new Promise(r => setTimeout(r, 100));
}
await new Promise(r => setTimeout(r, 3_000));

for (const clip of script) {
  const speaker = clip.id.startsWith("m") ? mom : ethan, listener = speaker === mom ? ethan : mom;
  console.log(`\n${at()} ${speaker === mom ? "mom" : "ethan"} says: ${clip.text}`);
  lineAt = undefined; listener.firstVoiceAfter = 0;
  const ended = await play(speaker, clip.id);
  await new Promise(r => setTimeout(r, 9_000));
  const words = lineAt ? `${((lineAt - ended) / 1000).toFixed(1)}s` : "none";
  const voice = listener.firstVoiceAfter ? `${((listener.firstVoiceAfter - ended) / 1000).toFixed(1)}s` : "none";
  console.log(`${at()} after the sentence ended: words ${words}, voice ${voice}`);
}

wav(mom.heard, path(folder, "mom-heard.wav")); wav(ethan.heard, path(folder, "ethan-heard.wav"));
console.log(`\nSaved what each side heard: ${path(folder, "mom-heard.wav")}, ${path(folder, "ethan-heard.wav")}`);
await mom.room.disconnect(); await ethan.room.disconnect();
process.exit(0);
