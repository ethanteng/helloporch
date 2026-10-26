import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { AccessToken, ParticipantInfo } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';
import { handleInboundWebhook, inboundRoomPrefix } from '../lib/family/inbound.ts';
import { handlePhoneCall } from '../lib/calls/phone.ts';
import { callLogLimits } from '../lib/family/call-log.ts';

class MemoryStore {
  values = new Map(); lifetimes = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value, seconds) { if (this.values.has(key)) return false; this.values.set(key, value); this.lifetimes.set(key, seconds); return true; }
  async compareAndSet(key, before, after, seconds) { if (this.values.get(key) !== before) return false; this.values.set(key, after); this.lifetimes.set(key, seconds); return true; }
}
const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-not-real', PORCH_CONTACT_SETUP_CODE: 'private-test-caregiver-secret',
  LIVEKIT_SIP_OUTBOUND_TRUNK_ID: 'ST_test', PORCH_PHONE_NUMBERS: '+14155550123' };
const pin = env.PORCH_CONTACT_SETUP_CODE;
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k, process.env[k]])); Object.assign(process.env, env); });
afterEach(() => { for (const [k, v] of Object.entries(previous)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });

function fixture(overrides = {}) {
  const store = new MemoryStore(), participants = new Map();
  let now = 1_800_000_000;
  const dependencies = { store, now: () => now, endRoom: async room => { participants.delete(room); },
    getPhoneParticipant: async (room, identity) => {
      const p = participants.get(room);
      if (!p || p.identity !== identity) throw Object.assign(Error('gone'), { code: 'not_found' });
      return p;
    }, ...overrides };
  const send = (action, values = {}, credential, code) => handleFamily(new Request('https://porch.example/api/family', {
    method: 'POST', headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(code ? { 'X-Porch-Setup-Code': code } : {}) },
    body: JSON.stringify({ action, ...(['claimInvite', 'createHousehold'].includes(action) ? { deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') } : {}), ...values }),
  }), dependencies);
  const json = async (...args) => { const r = await send(...args); assert.equal(r.status, 200, await r.clone().text()); return r.json(); };
  const setup = async () => {
    const bedside = await json('createHousehold', { name: 'Mom' }, undefined, pin);
    const invitation = await json('createInvite', { name: 'Ethan', permissions: { audio: true, video: true } }, bedside.credential, pin);
    const family = await json('claimInvite', { code: invitation.code });
    await json('poll', { available: true }, bedside.credential); await json('poll', { available: true }, family.credential);
    return { bedside, family };
  };
  const history = async (credential, code = pin) => (await json('callHistory', {}, credential, code)).calls;
  // Both devices keep checking in, as they do on a call.
  const talk = async (seconds, ...devices) => {
    let left = seconds;
    do {
      const step = Math.min(10, left); now += step; left -= step;
      for (const device of devices) await json('poll', { available: true }, device.credential);
    } while (left > 0);
  };
  return { store, participants, dependencies, send, json, setup, history, talk, advance: seconds => now += seconds, now: () => now };
}

test('caregivers see who called whom and how it went, newest first', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const mom = bedside.state.me.id, ethan = family.state.me.id;
  // Mom calls Ethan, who declines.
  const declined = (await f.json('startCall', { targetID: ethan, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  f.advance(3); await f.json('endCall', { callID: declined.id }, family.credential);
  // Mom calls again with video and nobody answers, so the bedside gives up.
  f.advance(60); await f.talk(0, bedside, family);
  const missed = (await f.json('startCall', { targetID: ethan, mode: 'video', kind: 'call' }, bedside.credential)).state.call;
  f.advance(20); await f.json('endCall', { callID: missed.id }, bedside.credential);
  // Ethan calls Mom, and they talk for two minutes.
  f.advance(60); await f.talk(0, bedside, family);
  const answered = (await f.json('startCall', { targetID: mom, mode: 'video', kind: 'call' }, family.credential)).state.call;
  f.advance(4); await f.json('acceptCall', { callID: answered.id, available: true }, bedside.credential);
  await f.talk(120, bedside, family);
  await f.json('endCall', { callID: answered.id }, family.credential);
  // Mom is calling Ethan right now.
  f.advance(30); await f.talk(0, bedside, family);
  const ringing = (await f.json('startCall', { targetID: ethan, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;

  const calls = await f.history(bedside.credential);
  assert.deepEqual(calls.map(c => [c.id, c.direction, c.outcome, c.mode]), [
    [ringing.id, 'outgoing', 'ringing', 'voice'],
    [answered.id, 'incoming', 'answered', 'video'],
    [missed.id, 'outgoing', 'missed', 'video'],
    [declined.id, 'outgoing', 'declined', 'voice'],
  ]);
  for (const call of calls) { assert.equal(call.name, 'Ethan'); assert.equal(call.memberID, ethan); assert.equal(call.via, 'porch'); }
  const talked = calls[1];
  assert.equal(talked.answeredAt - talked.startedAt, 4); assert.equal(talked.endedAt - talked.answeredAt, 120);
  assert.equal(calls[0].endedAt, undefined, 'a ringing call has no end yet');
  assert.equal(calls[2].reached, false, "Ethan's phone never reported showing the call");
  assert.equal(calls[1].reached, undefined); assert.equal(calls[3].reached, undefined);
  assert.ok(!JSON.stringify(calls).includes(family.credential.split('.')[1]));
});

test("a missed call from the bedside says whether it reached the family phone", async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const call = (await f.json('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  // The phone's app reports the call once iOS shows it, then nobody answers.
  await f.json('poll', { available: false, receivedCallID: call.id }, family.credential);
  f.advance(45); await f.json('endCall', { callID: call.id }, bedside.credential);
  const [entry] = await f.history(bedside.credential);
  assert.equal(entry.outcome, 'missed'); assert.equal(entry.reached, true);
});

test('a call whose devices both vanished ends when they were last heard from, not when someone looks', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const call = (await f.json('startCall', { targetID: bedside.state.me.id, mode: 'video', kind: 'call' }, family.credential)).state.call;
  await f.json('acceptCall', { callID: call.id, available: true }, bedside.credential);
  await f.talk(60, bedside, family);
  f.advance(86400);
  const [entry] = await f.history(bedside.credential);
  assert.equal(entry.outcome, 'answered'); assert.equal(entry.endedAt - entry.answeredAt, 60);
});

test("saving history waits until the call's request is answered", async () => {
  const later = [], f = fixture({ afterResponse: task => later.push(task) }), { bedside, family } = await f.setup();
  const first = (await f.json('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  await f.json('endCall', { callID: first.id }, bedside.credential);
  const second = (await f.json('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  assert.deepEqual((await f.history(bedside.credential)).map(c => c.id), [second.id]);
  await Promise.all(later.map(task => task()));
  assert.deepEqual((await f.history(bedside.credential)).map(c => c.id), [second.id, first.id]);
});

test('call history needs caregiver access and the PIN', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const call = (await f.json('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  assert.equal((await f.send('callHistory', {}, bedside.credential)).status, 403, 'the bedside needs its PIN');
  assert.equal((await f.send('callHistory', {}, family.credential, pin)).status, 403, 'family devices need caregiver approval');
  await f.json('setCaregiver', { memberID: family.state.me.id, enabled: true }, bedside.credential, pin);
  assert.equal((await f.send('callHistory', {}, family.credential)).status, 403, 'a caregiver phone needs the PIN');
  assert.deepEqual((await f.history(family.credential)).map(c => c.id), [call.id]);
});

test('a call that has run out reads as missed before anyone checks in', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const first = (await f.json('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call', waitSeconds: 20 }, bedside.credential)).state.call;
  f.advance(51);
  assert.deepEqual((await f.history(bedside.credential)).map(c => [c.id, c.outcome]), [[first.id, 'missed']]);
});

test('calls keep the name they started with, though the person is renamed or removed before the next call', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const ethan = family.state.me.id;
  const david = await f.json('claimInvite', { code: (await f.json('createInvite', { name: 'David', permissions: { audio: true, video: true } }, bedside.credential, pin)).code });
  await f.json('setMemberOverride', { memberID: ethan, name: 'Son' }, bedside.credential, pin);
  // Mom calls Ethan, and the caregiver renames him while it rings.
  const first = (await f.json('startCall', { targetID: ethan, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  assert.equal(first.peerName, undefined, 'devices are sent names their own way');
  await f.json('setMemberOverride', { memberID: ethan, name: 'Ethan T' }, bedside.credential, pin);
  assert.deepEqual((await f.history(bedside.credential)).map(c => c.name), ['Son']);
  await f.json('endCall', { callID: first.id }, bedside.credential);
  // Removing Ethan clears the names he went by. Mom's next call is what saves his to history.
  await f.json('revoke', { memberID: ethan }, bedside.credential, pin);
  f.advance(5); await f.talk(0, bedside, david);
  const second = (await f.json('startCall', { targetID: david.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
  assert.deepEqual((await f.history(bedside.credential)).map(c => [c.id, c.name]), [[second.id, 'David'], [first.id, 'Son']]);
});

test('a Porch call that could not reach the family phone shows as unavailable', async () => {
  const f = fixture({ sendPush: async () => ({ delivered: false }) }), { bedside, family } = await f.setup();
  await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, family.credential);
  await f.json('poll', { available: false }, family.credential);
  assert.equal((await f.send('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).status, 409);
  const calls = await f.history(bedside.credential), [call] = calls;
  assert.equal(call.outcome, 'unavailable'); assert.equal(call.direction, 'outgoing');
  assert.ok(!JSON.stringify(calls).includes('abababab'), 'push tokens never reach history');
});

test('phone calls in, and the bedside dialing a phone, are in the history', async () => {
  const f = fixture(), { bedside } = await f.setup();
  const householdID = bedside.state.householdID;
  await f.store.create('phone-number:+14155550100', JSON.stringify({ householdID, bedsideID: bedside.state.me.id, trunkID: 'ST_inbound' }));
  await f.json('setPhoneDropIn', { number: '+14155550200', name: 'Aunt May', enabled: true }, bedside.credential, pin);
  const webhook = async event => {
    const body = JSON.stringify(event), token = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, { ttl: '1m' });
    token.sha256 = createHash('sha256').update(body).digest('base64');
    const response = await handleInboundWebhook(new Request('https://porch.example/api/calls/inbound/webhook', { method: 'POST', headers: { Authorization: await token.toJwt() }, body }), f.dependencies);
    assert.equal(response.status, 200);
  };
  const ring = async caller => {
    const room = { sid: `RM_${randomUUID()}`, name: `${inboundRoomPrefix}${randomUUID()}` };
    const participant = new ParticipantInfo({ sid: `PA_${randomUUID()}`, identity: `sip_${randomUUID()}`, kind: 3,
      attributes: { 'sip.trunkID': 'ST_inbound', 'sip.trunkPhoneNumber': '+14155550100', 'sip.phoneNumber': caller, 'sip.callStatus': 'ringing' } });
    f.participants.set(room.name, participant);
    await webhook({ id: randomUUID(), createdAt: f.now(), event: 'participant_joined', room, participant: participant.toJson() });
    return room;
  };
  // Aunt May calls and hangs up before Mom answers; then an unknown number calls.
  const first = await ring('+14155550200');
  f.participants.delete(first.name); f.advance(10);
  await f.json('poll', { available: true }, bedside.credential);
  // Renaming her approved number afterwards doesn't rename her call.
  await f.json('setPhoneDropIn', { number: '+14155550200', name: 'May Lee', enabled: true }, bedside.credential, pin);
  await ring('+14155550999');

  // Mom's Porch calls a contact's regular phone.
  const phone = { joined: true, attributes: {} };
  const services = () => ({
    rooms: { async getParticipant() { if (!phone.joined) throw Object.assign(Error('gone'), { code: 'not_found' }); return { attributes: phone.attributes }; },
      async updateParticipant(_room, _identity, options) { Object.assign(phone.attributes, options.attributes); }, async deleteRoom() { phone.joined = false; } },
    sip: { async createSipParticipant() { return {}; } },
  });
  const phoneDependencies = { now: f.now, store: f.store, services,
    authorize: async () => ({ apiKey: env.LIVEKIT_API_KEY, apiSecret: env.LIVEKIT_API_SECRET, serverUrl: env.LIVEKIT_URL, householdID }) };
  const phoneRequest = body => new Request('https://porch.example/api/calls/phone', { method: 'POST', body: JSON.stringify(body) });
  f.advance(30);
  const prepared = await (await handlePhoneCall(phoneRequest({ phoneNumber: '+14155550123', name: 'David' }), 'prepare', phoneDependencies)).json();
  assert.equal((await handlePhoneCall(phoneRequest({ controlToken: prepared.controlToken }), 'start', phoneDependencies)).status, 200);

  const calls = await f.history(bedside.credential);
  assert.deepEqual(calls.map(c => [c.direction, c.via, c.name, c.number, c.outcome]), [
    ['outgoing', 'phone', 'David', '+14155550123', 'dialed'],
    ['incoming', 'phone', '+14155550999', '+14155550999', 'ringing'],
    ['incoming', 'phone', 'Aunt May', '+14155550200', 'missed'],
  ]);
  // Without a household, such as a legacy shared-code iPad, nothing is recorded and the call still starts.
  const legacy = { ...phoneDependencies, authorize: async () => ({ apiKey: env.LIVEKIT_API_KEY, apiSecret: env.LIVEKIT_API_SECRET, serverUrl: env.LIVEKIT_URL }) };
  phone.joined = true; phone.attributes = {};
  const again = await (await handlePhoneCall(phoneRequest({ phoneNumber: '+14155550123', name: 'David' }), 'prepare', legacy)).json();
  assert.equal((await handlePhoneCall(phoneRequest({ controlToken: again.controlToken }), 'start', legacy)).status, 200);
  assert.equal((await f.history(bedside.credential)).length, 3);
});

test('history keeps the newest calls for 90 days', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const ids = [];
  for (let n = 0; n < callLogLimits.entries + 5; n++) {
    f.advance(60); await f.talk(0, bedside, family);
    const call = (await f.json('startCall', { targetID: family.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential)).state.call;
    await f.json('endCall', { callID: call.id }, bedside.credential);
    ids.push(call.id);
  }
  assert.equal(f.store.lifetimes.get(`call-log:${bedside.state.householdID}`), callLogLimits.keepSeconds, 'storage deletes it 90 days after the newest call');
  const calls = await f.history(bedside.credential);
  assert.equal(calls.length, callLogLimits.entries);
  assert.deepEqual(calls.map(c => c.id), ids.slice(-callLogLimits.entries).reverse());
  f.advance(callLogLimits.keepSeconds);
  assert.deepEqual(await f.history(bedside.credential), []);
});
