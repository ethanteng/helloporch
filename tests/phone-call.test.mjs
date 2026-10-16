import assert from "node:assert/strict";
import { beforeEach, afterEach, test } from "node:test";
import { TokenVerifier } from "livekit-server-sdk";
import { handlePhoneCall } from "../lib/calls/phone.ts";

const configuration = {
  LIVEKIT_URL: "wss://porch-test.livekit.cloud",
  LIVEKIT_API_KEY: "test-key",
  LIVEKIT_API_SECRET: "test-secret-only-not-a-real-api-credential",
  PORCH_CALL_ACCESS_CODE: "test-prototype-access-code",
  LIVEKIT_SIP_OUTBOUND_TRUNK_ID: "ST_test",
  PORCH_PHONE_NUMBERS: "+14155550123,+442079460123",
};
let previous;
const now = Math.floor(Date.now() / 1000);
beforeEach(() => {
  previous = Object.fromEntries(Object.keys(configuration).map((key) => [key, process.env[key]]));
  Object.assign(process.env, configuration);
});
afterEach(() => {
  for (const [key, value] of Object.entries(previous)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
});

function request(body, headers = {}) {
  return new Request("https://porch.example.com/api/calls/phone/prepare", {
    method: "POST", headers: { Authorization: `Bearer ${configuration.PORCH_CALL_ACCESS_CODE}`, ...headers },
    body: JSON.stringify(body),
  });
}
function fixture() {
  const calls = { dial: [], deleted: [], services: 0 };
  const state = { joined: true, attributes: {}, dialError: undefined, deletionError: undefined, onDial: undefined };
  const missing = () => Object.assign(new Error("not found"), { code: "not_found" });
  const client = {
    rooms: {
      async getParticipant() {
        if (!state.joined) throw missing();
        return { attributes: state.attributes };
      },
      async updateParticipant(_room, _identity, options) { Object.assign(state.attributes, options.attributes); },
      async deleteRoom(room) {
        if (state.deletionError) throw state.deletionError;
        calls.deleted.push(room);
        if (!state.joined) throw missing();
        state.joined = false;
      },
    },
    sip: {
      async createSipParticipant(...args) {
        calls.dial.push(args);
        if (state.onDial) await state.onDial();
        if (state.dialError) throw state.dialError;
        return {};
      },
    },
  };
  const dependencies = { now: () => now, services: () => { calls.services += 1; return client; } };
  const send = (action, body, overrides = {}) => handlePhoneCall(request(body), action, { ...dependencies, ...overrides });
  const prepare = async () => {
    const response = await send("prepare", { phoneNumber: "+14155550123", name: " David " });
    assert.equal(response.status, 200);
    return response.json();
  };
  return { calls, state, dependencies, send, prepare };
}

test("phone calls require authentication and same-origin requests", async () => {
  const f = fixture();
  for (const action of ["prepare", "start", "end"]) {
    assert.equal((await handlePhoneCall(request({}, { Authorization: "Bearer wrong" }), action, f.dependencies)).status, 401);
    assert.equal((await handlePhoneCall(request({}, { Origin: "https://foreign.example.com" }), action, f.dependencies)).status, 403);
  }
  assert.equal(f.calls.services, 0);
});

test("missing configuration, invalid numbers, and unapproved numbers cannot dial", async () => {
  const f = fixture();
  for (const key of ["LIVEKIT_SIP_OUTBOUND_TRUNK_ID", "PORCH_PHONE_NUMBERS"]) {
    delete process.env[key];
    assert.equal((await f.send("prepare", { phoneNumber: "+14155550123", name: "David" })).status, 503);
    process.env[key] = configuration[key];
  }
  for (const phoneNumber of ["4155550123", "+01415550123", "+14155550123#2", "sip:person@example.com", "+1911", ""]) {
    assert.equal((await f.send("prepare", { phoneNumber, name: "David" })).status, 400);
  }
  assert.equal((await f.send("prepare", { phoneNumber: "+14155559999", name: "David" })).status, 403);
  assert.equal(f.calls.dial.length, 0);
});

test("preparing creates isolated microphone-only credentials without placing a call", async () => {
  const f = fixture();
  const first = await f.prepare();
  const second = await f.prepare();
  assert.notEqual(first.room, second.room);
  assert.ok(first.room.startsWith("porch-phone-"));
  const token = await new TokenVerifier(configuration.LIVEKIT_API_KEY, configuration.LIVEKIT_API_SECRET).verify(first.token);
  assert.equal(token.video.room, first.room);
  assert.deepEqual(token.video.canPublishSources, ["microphone"]);
  assert.equal(token.video.canUpdateOwnMetadata, false);
  assert.equal(token.sip, undefined);
  assert.equal(token.roomConfig.maxParticipants, 2);
  assert.equal(f.calls.services, 0);
  assert.ok(!JSON.stringify(first).includes(configuration.LIVEKIT_API_SECRET));
});

test("a tampered, invented, or expired control token cannot dial or delete a room", async () => {
  const f = fixture();
  const session = await f.prepare();
  const [encoded, signature] = session.controlToken.split(".");
  const ticket = JSON.parse(Buffer.from(encoded, "base64url").toString());
  ticket.phoneNumber = "+14155559999";
  const forged = `${Buffer.from(JSON.stringify(ticket)).toString("base64url")}.${signature}`;
  for (const controlToken of [forged, "fake.token", "", "a".repeat(1801)]) {
    for (const action of ["start", "end"]) assert.equal((await f.send(action, { controlToken })).status, 401);
  }
  assert.equal((await f.send("end", { controlToken: session.controlToken }, { now: () => now + 1201 })).status, 401);
  assert.equal(f.calls.services, 0);
});

test("the iPad must be present and a destination must still be approved before dialing", async () => {
  const f = fixture();
  const session = await f.prepare();
  process.env.PORCH_PHONE_NUMBERS = "+442079460123";
  assert.equal((await f.send("start", { controlToken: session.controlToken })).status, 403);
  process.env.PORCH_PHONE_NUMBERS = configuration.PORCH_PHONE_NUMBERS;
  f.state.joined = false;
  assert.equal((await f.send("start", { controlToken: session.controlToken })).status, 409);
  assert.equal(f.calls.dial.length, 0);
});

test("dialing uses the configured trunk, a fixed destination, and bounded duration; sequential replays do not redial", async () => {
  const f = fixture();
  const session = await f.prepare();
  const body = { controlToken: session.controlToken, phoneNumber: "+14155559999", room: "someone-elses-room" };
  assert.equal((await f.send("start", body)).status, 200);
  const [trunk, number, room, options] = f.calls.dial[0];
  assert.equal(trunk, "ST_test");
  assert.equal(number, "+14155550123");
  assert.equal(room, session.room);
  assert.equal(options.participantIdentity, "phone");
  assert.equal(options.ringingTimeout, 45);
  assert.equal(options.maxCallDuration, 900);
  assert.equal(options.waitUntilAnswered, false);
  assert.equal(options.playDialtone, true);
  assert.equal((await f.send("start", body)).status, 409);
  assert.equal(f.calls.dial.length, 1);
});

test("concurrent dial submissions in one process cannot create a second telephone leg", async () => {
  const f = fixture();
  const session = await f.prepare();
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  let entered;
  const dialing = new Promise((resolve) => { entered = resolve; });
  f.state.onDial = async () => { entered(); await gate; };
  const first = f.send("start", { controlToken: session.controlToken });
  await dialing;
  assert.equal((await f.send("start", { controlToken: session.controlToken })).status, 409);
  release();
  assert.equal((await first).status, 200);
  assert.equal(f.calls.dial.length, 1);
});

test("cancellation during dialing removes a late telephone leg", async () => {
  const f = fixture();
  const session = await f.prepare();
  f.state.onDial = async () => { f.state.joined = false; };
  assert.equal((await f.send("start", { controlToken: session.controlToken })).status, 409);
  assert.ok(f.calls.deleted.includes(session.room));
});

test("provider failure triggers cleanup and a safe explanation", async () => {
  const f = fixture();
  const session = await f.prepare();
  f.state.dialError = Object.assign(new Error("private provider error +14155550123"), { sipStatusCode: 486 });
  const response = await f.send("start", { controlToken: session.controlToken });
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "Their phone is busy. Try again later." });
  assert.ok(f.calls.deleted.includes(session.room));
});

test("end remains idempotent and available after dialing expires or telephony is disabled", async () => {
  const f = fixture();
  const session = await f.prepare();
  assert.equal((await f.send("start", { controlToken: session.controlToken }, { now: () => now + 121 })).status, 410);
  delete process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;
  delete process.env.PORCH_PHONE_NUMBERS;
  assert.equal((await f.send("end", { controlToken: session.controlToken })).status, 200);
  assert.equal((await f.send("end", { controlToken: session.controlToken })).status, 200);
});

test("a failed hangup is reported for retry, not incorrectly confirmed", async () => {
  const f = fixture();
  const session = await f.prepare();
  f.state.deletionError = new Error("offline");
  assert.equal((await f.send("end", { controlToken: session.controlToken })).status, 502);
});
