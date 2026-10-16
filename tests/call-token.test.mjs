import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import { TokenVerifier } from "livekit-server-sdk";
import { POST } from "../app/api/calls/token/route.ts";

const configuration = {
  LIVEKIT_URL: "wss://porch-test.livekit.cloud",
  LIVEKIT_API_KEY: "test-key",
  LIVEKIT_API_SECRET: "test-secret-only-not-a-real-api-credential",
  PORCH_CALL_ACCESS_CODE: "test-prototype-access-code",
};
let previous;
beforeEach(() => {
  previous = Object.fromEntries(Object.keys(configuration).map((key) => [key, process.env[key]]));
  Object.assign(process.env, configuration);
});
afterEach(() => {
  for (const [key, value] of Object.entries(previous)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

function request(body = { room: "family-david", mode: "voice", name: " David " }, headers = {}) {
  return new Request("https://porch.example.com/api/calls/token", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${configuration.PORCH_CALL_ACCESS_CODE}`, ...headers },
    body: JSON.stringify(body),
  });
}

test("calling fails closed when configuration is absent or invalid", async () => {
  for (const key of Object.keys(configuration)) {
    delete process.env[key];
    assert.equal((await POST(request())).status, 503);
    process.env[key] = configuration[key];
  }
  for (const url of ["https://example.com", "wss://user:secret@example.com", "not-a-url"]) {
    process.env.LIVEKIT_URL = url;
    assert.equal((await POST(request())).status, 503);
  }
});

test("token generation requires the access code and rejects foreign browser origins", async () => {
  for (const authorization of ["", "Bearer wrong", configuration.PORCH_CALL_ACCESS_CODE]) {
    assert.equal((await POST(request(undefined, { Authorization: authorization }))).status, 401);
  }
  assert.equal((await POST(request(undefined, { Origin: "https://other.example.com" }))).status, 403);
  assert.equal((await POST(request(undefined, { Origin: "https://porch.example.com" }))).status, 200);
});

test("malformed call details cannot mint a token", async () => {
  for (const body of [null, [], "room", {},
    { room: "../other", mode: "voice", name: "David" },
    { room: "family", mode: "unknown", name: "David" },
    { room: "family", mode: "voice", name: " " },
    { room: "family", mode: "voice", name: "a".repeat(81) },
    { room: "a".repeat(65), mode: "video", name: "David" },
  ]) assert.equal((await POST(request(body))).status, 400);
  assert.equal((await POST(request({ padding: "a".repeat(2049) }))).status, 413);
  const invalid = new Request("https://porch.example.com/api/calls/token", {
    method: "POST", body: "{", headers: { Authorization: `Bearer ${configuration.PORCH_CALL_ACCESS_CODE}` },
  });
  assert.equal((await POST(invalid)).status, 400);
});

test("verified voice token permits only microphone in its room and expires soon", async () => {
  const response = await POST(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const payload = await response.json();
  const claims = await new TokenVerifier(configuration.LIVEKIT_API_KEY, configuration.LIVEKIT_API_SECRET).verify(payload.token);
  assert.equal(payload.serverUrl, configuration.LIVEKIT_URL);
  assert.equal(payload.room, "porch-voice-family-david");
  assert.equal(claims.name, "David");
  assert.equal(claims.video.room, payload.room);
  assert.equal(claims.video.roomJoin, true);
  assert.equal(claims.video.canPublishData, false);
  assert.deepEqual(claims.video.canPublishSources, ["microphone"]);
  assert.equal(claims.video.roomAdmin, undefined);
  assert.equal(claims.roomConfig.maxParticipants, 2);
  assert.ok(claims.exp - Math.floor(Date.now() / 1000) <= 600);
  assert.ok(claims.exp > Math.floor(Date.now() / 1000));
  assert.ok(!JSON.stringify(payload).includes(configuration.LIVEKIT_API_SECRET));
  assert.ok(!JSON.stringify(payload).includes(configuration.PORCH_CALL_ACCESS_CODE));
});

test("video tokens allow camera and microphone, use a separate room, and unique identities", async () => {
  const verifier = new TokenVerifier(configuration.LIVEKIT_API_KEY, configuration.LIVEKIT_API_SECRET);
  const first = await (await POST(request({ room: "family-david", mode: "video", name: "David" }))).json();
  const second = await (await POST(request({ room: "family-david", mode: "video", name: "David" }))).json();
  const claims = await verifier.verify(first.token);
  assert.equal(claims.video.room, "porch-video-family-david");
  assert.deepEqual(claims.video.canPublishSources, ["microphone", "camera"]);
  assert.notEqual(claims.sub, (await verifier.verify(second.token)).sub);
});
