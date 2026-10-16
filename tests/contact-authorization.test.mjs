import assert from "node:assert/strict";
import { beforeEach, afterEach, test } from "node:test";
import { POST } from "../app/api/calls/contacts/authorize/route.ts";
import { authorizeContact } from "../lib/calls/contacts.ts";
import { handlePhoneCall } from "../lib/calls/phone.ts";

const config = {
  LIVEKIT_URL: "wss://porch-test.livekit.cloud", LIVEKIT_API_KEY: "test-key",
  LIVEKIT_API_SECRET: "test-secret-only-not-real", PORCH_CALL_ACCESS_CODE: "test-calling-access-code",
  PORCH_CONTACT_SETUP_CODE: "test-separate-caregiver-code", LIVEKIT_SIP_OUTBOUND_TRUNK_ID: "ST_test",
  PORCH_PHONE_NUMBERS: "",
};
const now = Math.floor(Date.now() / 1000);
const number = "+14155550123";
let previous;
beforeEach(() => {
  previous = Object.fromEntries(Object.keys(config).map(key => [key, process.env[key]]));
  Object.assign(process.env, config);
});
afterEach(() => {
  for (const [key, value] of Object.entries(previous)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
});
function request(body, headers = {}, origin = "https://porch.example.com") {
  return new Request(`${origin}/api/calls/contacts/authorize`, { method: "POST", body: JSON.stringify(body),
    headers: { Authorization: `Bearer ${config.PORCH_CALL_ACCESS_CODE}`, "X-Porch-Setup-Code": config.PORCH_CONTACT_SETUP_CODE, ...headers } });
}
async function approval() {
  const response = await authorizeContact(request({ phoneNumber: number }), now);
  assert.equal(response.status, 200);
  return response.json();
}
function services() {
  const calls = { dialed: [], deleted: [], attributes: {} };
  return { calls, dependencies: { now: () => now, services: () => ({
    rooms: {
      async getParticipant() { return { attributes: calls.attributes }; },
      async updateParticipant(_room, _identity, options) { Object.assign(calls.attributes, options.attributes); },
      async deleteRoom(room) { calls.deleted.push(room); },
    },
    sip: { async createSipParticipant(...args) { calls.dialed.push(args); } },
  }) } };
}

test("calling access alone cannot authorize new phone destinations", async () => {
  assert.equal((await POST(request({ phoneNumber: number }, { "X-Porch-Setup-Code": "" }))).status, 403);
  assert.equal((await POST(request({ phoneNumber: number }, { "X-Porch-Setup-Code": config.PORCH_CALL_ACCESS_CODE }))).status, 403);
  assert.equal((await POST(request({ phoneNumber: number }, { Authorization: "Bearer wrong" }))).status, 401);
  assert.equal((await POST(request({ phoneNumber: number }, { Origin: "https://foreign.example.com" }))).status, 403);
});

test("contact approval fails closed without a distinct caregiver code and phone trunk", async () => {
  for (const value of [undefined, "short", config.PORCH_CALL_ACCESS_CODE]) {
    if (value === undefined) delete process.env.PORCH_CONTACT_SETUP_CODE;
    else process.env.PORCH_CONTACT_SETUP_CODE = value;
    assert.equal((await POST(request({ phoneNumber: number }))).status, 503);
  }
  process.env.PORCH_CONTACT_SETUP_CODE = config.PORCH_CONTACT_SETUP_CODE;
  delete process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;
  assert.equal((await POST(request({ phoneNumber: number }))).status, 503);
});

test("saving a contact returns only a bounded destination approval, without a call", async () => {
  const response = await authorizeContact(request({ phoneNumber: number }), now);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const body = await response.json();
  assert.deepEqual(Object.keys(body).sort(), ["authorization", "expiresAt"]);
  assert.equal(body.expiresAt, now + 30 * 24 * 60 * 60);
  assert.ok(!JSON.stringify(body).includes(config.LIVEKIT_API_SECRET));
  assert.ok(!JSON.stringify(body).includes(config.PORCH_CONTACT_SETUP_CODE));
  for (const phoneNumber of ["4155550123", "+01415550123", "+14155550123#2", "+1911", null]) {
    assert.equal((await POST(request({ phoneNumber }))).status, 400);
  }
  assert.equal((await POST(request({ phoneNumber: "x".repeat(3000) }))).status, 413);
});

test("a saved contact can dial without any Vercel destination list", async () => {
  delete process.env.PORCH_PHONE_NUMBERS;
  const approved = await approval();
  const f = services();
  const prepared = await handlePhoneCall(request({ phoneNumber: number, name: "Mom", contactAuthorization: approved.authorization }), "prepare", f.dependencies);
  assert.equal(prepared.status, 200);
  assert.equal(f.calls.dialed.length, 0);
  const session = await prepared.json();
  assert.equal((await handlePhoneCall(request({ controlToken: session.controlToken }), "start", f.dependencies)).status, 200);
  assert.equal(f.calls.dialed.length, 1);
  assert.equal(f.calls.dialed[0][1], number);
});

test("approvals cannot be altered, reused for another destination, or used on another server", async () => {
  const { authorization } = await approval();
  const f = services();
  for (const input of [
    { phoneNumber: "+14155550124", contactAuthorization: authorization },
    { phoneNumber: number, contactAuthorization: authorization + "x" },
    { phoneNumber: number, contactAuthorization: "invented" },
    { phoneNumber: number, contactAuthorization: null },
  ]) {
    assert.equal((await handlePhoneCall(request({ name: "Mom", ...input }), "prepare", f.dependencies)).status, 403);
  }
  assert.equal((await handlePhoneCall(request({ name: "Mom", phoneNumber: number, contactAuthorization: authorization }, {}, "https://another.example.com"), "prepare", f.dependencies)).status, 403);
  assert.equal(f.calls.dialed.length, 0);
});

test("expired approval is rejected and saving again renews it", async () => {
  const { authorization, expiresAt } = await approval();
  const input = { phoneNumber: number, name: "Mom", contactAuthorization: authorization };
  assert.equal((await handlePhoneCall(request(input), "prepare", { now: () => expiresAt })).status, 403);
  const renewed = await authorizeContact(request({ phoneNumber: number }), expiresAt);
  const newApproval = await renewed.json();
  assert.notEqual(newApproval.authorization, authorization);
  assert.equal((await handlePhoneCall(request({ ...input, contactAuthorization: newApproval.authorization }), "prepare", { now: () => expiresAt })).status, 200);
});

test("rotating the caregiver code revokes approvals before dialing but leaves hangup available", async () => {
  const { authorization } = await approval();
  const f = services();
  const session = await (await handlePhoneCall(request({ phoneNumber: number, name: "Mom", contactAuthorization: authorization }), "prepare", f.dependencies)).json();
  process.env.PORCH_CONTACT_SETUP_CODE = "rotated-caregiver-code-for-test";
  assert.equal((await handlePhoneCall(request({ controlToken: session.controlToken }), "start", f.dependencies)).status, 403);
  assert.equal(f.calls.dialed.length, 0);
  assert.equal((await handlePhoneCall(request({ controlToken: session.controlToken }), "end", f.dependencies)).status, 200);
  assert.equal(f.calls.deleted.length, 1);
});

test("approval expiry is checked again between preparing and actually dialing", async () => {
  const { authorization, expiresAt } = await approval();
  const f = services();
  const prepared = await handlePhoneCall(request({ phoneNumber: number, name: "Mom", contactAuthorization: authorization }), "prepare", { ...f.dependencies, now: () => expiresAt - 10 });
  assert.equal(prepared.status, 200);
  const session = await prepared.json();
  assert.equal((await handlePhoneCall(request({ controlToken: session.controlToken }), "start", { ...f.dependencies, now: () => expiresAt })).status, 403);
  assert.equal(f.calls.dialed.length, 0);
});

test("old iPad builds retain the explicit legacy destination list during migration", async () => {
  const f = services();
  process.env.PORCH_PHONE_NUMBERS = number;
  assert.equal((await handlePhoneCall(request({ phoneNumber: number, name: "Mom" }), "prepare", f.dependencies)).status, 200);
  assert.equal((await handlePhoneCall(request({ phoneNumber: number, name: "Mom", contactAuthorization: "bad" }), "prepare", f.dependencies)).status, 403);
  delete process.env.PORCH_PHONE_NUMBERS;
  assert.equal((await handlePhoneCall(request({ phoneNumber: number, name: "Mom" }), "prepare", f.dependencies)).status, 503);
});
