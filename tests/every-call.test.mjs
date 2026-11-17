import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { AccessToken, ParticipantInfo } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';
import { handleInboundWebhook, inboundRoomPrefix } from '../lib/family/inbound.ts';

// Every call drops in: a caregiver turns it on with the PIN typed again, any caregiver turns it off, and the other
// caregivers' phones are told either way.
const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-not-real', PORCH_CONTACT_SETUP_CODE: 'private-test-caregiver-secret' };
const legacy = env.PORCH_CONTACT_SETUP_CODE;
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k, process.env[k]])); Object.assign(process.env, env); });
afterEach(() => { for (const [k, v] of Object.entries(previous)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key, value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key, after); return true; }
}
const device = () => ({ deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') });
function fixture() {
  const store = new MemoryStore(), notices = [], ended = [], participants = new Map();
  let now = 1_800_000_000;
  const dependencies = { store, now: () => now, endRoom: async room => { ended.push(room); },
    sendNotice: async (registration, notice) => { notices.push({ token: registration.token, ...notice }); return { delivered: true }; },
    getPhoneParticipant: async (room, identity) => {
      const p = participants.get(room);
      if (!p || p.identity !== identity) throw Object.assign(Error('gone'), { code: 'not_found' });
      return p;
    } };
  const send = (action, values = {}, credential, pin) => handleFamily(new Request('https://porch.example/api/family', { method: 'POST',
    headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(pin ? { 'X-Porch-Setup-Code': pin } : {}) },
    body: JSON.stringify({ action, ...values }) }), dependencies);
  const json = async (...args) => { const r = await send(...args); assert.equal(r.status, 200, await r.clone().text()); return r.json(); };
  const join = async (bedside, name, { permissions = { audio: false, video: false }, caregiver = false } = {}) => {
    const invite = await json('createInvite', { name, permissions, caregiver }, bedside.credential, legacy);
    const member = await json('claimInvite', { code: invite.code, ...device() });
    await json('poll', { available: true }, member.credential);
    return member;
  };
  const setup = async () => {
    const bedside = await json('createHousehold', { name: 'Mom', ...device() }, undefined, legacy);
    await json('initializeCaregiverPIN', { pin: '123456' }, bedside.credential);
    await json('poll', { available: true }, bedside.credential);
    await store.create('phone-number:+14155550100', JSON.stringify({ householdID: bedside.state.householdID, bedsideID: bedside.state.me.id, trunkID: 'ST_inbound' }));
    return bedside;
  };
  const alerts = (member, n) => json('registerAlerts', { token: String(n).repeat(64), environment: 'sandbox' }, member.credential);
  const phoneCall = (caller = '+14155550200', attributes = {}) => {
    const room = { sid: `RM_${randomUUID()}`, name: `${inboundRoomPrefix}${randomUUID()}` };
    const participant = new ParticipantInfo({ sid: `PA_${randomUUID()}`, identity: `sip_${randomUUID()}`, kind: 3,
      attributes: { 'sip.callID': `SCL_${randomUUID()}`, 'sip.trunkID': 'ST_inbound', 'sip.trunkPhoneNumber': '+14155550100', 'sip.phoneNumber': caller, 'sip.callStatus': 'ringing', ...attributes } });
    participants.set(room.name, participant);
    return { id: randomUUID(), createdAt: now, event: 'participant_joined', room, participant: participant.toJson() };
  };
  const webhook = async event => {
    const body = JSON.stringify(event);
    const token = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, { ttl: '1m' });
    token.sha256 = createHash('sha256').update(body).digest('base64');
    return handleInboundWebhook(new Request('https://porch.example/api/calls/inbound/webhook', { method: 'POST', headers: { Authorization: await token.toJwt() }, body }), dependencies);
  };
  const house = bedside => JSON.parse(store.values.get(`house:${bedside.state.householdID}`));
  return { store, notices, ended, send, json, join, setup, alerts, phoneCall, webhook, house, advance: s => now += s, now: () => now };
}
const verified = { 'porch.callerVerification': 'TN-Validation-Passed-A' };

test('every call is turned on only by a caregiver who types the PIN', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { caregiver: true }), lee = await f.join(bedside, 'Lee');
  assert.equal((await f.send('setDropInMode', { mode: 'everyCall' }, bedside.credential, '000000')).status, 403);
  assert.equal((await f.send('setDropInMode', { mode: 'everyCall' }, bedside.credential)).status, 403);
  assert.equal((await f.send('setDropInMode', { mode: 'everyCall' }, lee.credential, '123456')).status, 403);
  assert.equal((await f.send('setDropInMode', { mode: 'everyone' }, tom.credential, '123456')).status, 400);
  assert.equal(f.house(bedside).everyCall, undefined);
  const on = await f.json('setDropInMode', { mode: 'everyCall' }, tom.credential, '123456');
  assert.deepEqual(on.admin.everyCall, { by: 'Tom', at: f.now() });
  assert.equal(on.admin.dropInEnabled, true);
  // Everyone's app knows, so their calls can drop in.
  assert.deepEqual((await f.json('poll', { available: true }, lee.credential)).state.everyCall, { by: 'Tom', at: f.now() });
  // Choosing it again keeps who turned it on, and when.
  f.advance(60);
  assert.equal((await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456')).admin.everyCall.by, 'Tom');
});

test('at the bedside, every call says so', async () => {
  const f = fixture(), bedside = await f.setup();
  const on = await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  assert.deepEqual(on.state.everyCall, { by: 'Mom', at: f.now(), atBedside: true });
});

test('No one and People you approve turn every call off and keep approvals', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { permissions: { audio: true, video: false } });
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  let state = (await f.json('setDropInMode', { mode: 'approved' }, bedside.credential, legacy)).admin;
  assert.equal(state.everyCall, undefined); assert.equal(state.dropInEnabled, true);
  assert.deepEqual(state.people.find(p => p.id === tom.state.me.id).permissions, { audio: true, video: false });
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  state = (await f.json('setDropInMode', { mode: 'off' }, bedside.credential, legacy)).admin;
  assert.equal(state.everyCall, undefined); assert.equal(state.dropInEnabled, false);
  // Older apps' switch turns it off too.
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  state = (await f.json('setDropIn', { enabled: false }, bedside.credential, legacy)).admin;
  assert.equal(state.everyCall, undefined); assert.equal(f.house(bedside).everyCall, undefined);
  await f.json('setDropIn', { enabled: true }, bedside.credential, legacy);
  assert.equal(f.house(bedside).everyCall, undefined);
});

test('while every call is on, anyone in the family drops in, with audio or video', async () => {
  const f = fixture(), bedside = await f.setup(), lee = await f.join(bedside, 'Lee');
  await f.json('setDropInMode', { mode: 'approved' }, bedside.credential, legacy);
  assert.equal((await f.send('startCall', { targetID: bedside.state.me.id, mode: 'video', kind: 'dropIn' }, lee.credential)).status, 403);
  let call = (await f.json('startCall', { targetID: bedside.state.me.id, mode: 'video', kind: 'call' }, lee.credential)).state.call;
  assert.equal(call.kind, 'call');
  await f.json('endCall', { callID: call.id }, lee.credential);
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  await f.json('poll', { available: true }, bedside.credential);
  // An ordinary call drops in now, as for someone approved.
  call = (await f.json('startCall', { targetID: bedside.state.me.id, mode: 'video', kind: 'call' }, lee.credential)).state.call;
  assert.equal(call.kind, 'dropIn');
  await f.json('endCall', { callID: call.id }, lee.credential);
  call = (await f.json('startCall', { targetID: bedside.state.me.id, mode: 'voice', kind: 'dropIn' }, lee.credential)).state.call;
  assert.equal(call.kind, 'dropIn');
});

test('any caregiver turns every call off without the PIN, which ends a drop-in only it let in', async () => {
  const f = fixture(), bedside = await f.setup();
  const linda = await f.join(bedside, 'Linda', { caregiver: true }), lee = await f.join(bedside, 'Lee');
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  await f.json('poll', { available: true }, bedside.credential);
  const call = (await f.json('startCall', { targetID: bedside.state.me.id, mode: 'voice', kind: 'dropIn' }, lee.credential)).state.call;
  assert.equal((await f.send('turnOffEveryCall', {}, lee.credential)).status, 403);
  const off = await f.json('turnOffEveryCall', {}, linda.credential);
  assert.equal(off.state.everyCall, undefined); assert.equal(off.state.dropInEnabled, true); assert.equal(off.admin, undefined);
  assert.equal(f.house(bedside).call.state, 'ended');
  assert.ok(f.ended.some(room => room.includes(call.id)));
  // Again is harmless.
  await f.json('turnOffEveryCall', {}, linda.credential);
});

test('the other caregivers are told when every call is turned on or off', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { caregiver: true }), linda = await f.join(bedside, 'Linda', { caregiver: true });
  const lee = await f.join(bedside, 'Lee');
  await f.alerts(tom, 1); await f.alerts(linda, 2); await f.alerts(lee, 3);
  await f.json('setDropInMode', { mode: 'everyCall' }, tom.credential, '123456');
  assert.deepEqual(f.notices, [{ token: '2'.repeat(64), type: 'everyCall', recipientID: linda.state.me.id, title: 'Every call drops in on Mom', body: 'Tom turned it on.' }]);
  // Nothing changes, nothing is sent.
  await f.json('setDropInMode', { mode: 'everyCall' }, linda.credential, '123456');
  assert.equal(f.notices.length, 1);
  f.notices.length = 0;
  await f.json('turnOffEveryCall', {}, linda.credential);
  assert.deepEqual(f.notices, [{ token: '1'.repeat(64), type: 'everyCall', recipientID: tom.state.me.id, title: 'Every call is off for Mom', body: 'Linda turned it off.' }]);
  f.notices.length = 0;
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  assert.deepEqual(f.notices.map(n => [n.recipientID, n.body]).sort(), [[tom.state.me.id, 'Turned on at Mom’s iPad.'], [linda.state.me.id, 'Turned on at Mom’s iPad.']].sort());
  f.notices.length = 0;
  await f.json('setDropInMode', { mode: 'off' }, bedside.credential, legacy);
  assert.equal(f.notices.length, 2); assert.ok(f.notices.every(n => n.title === 'Every call is off for Mom'));
  // Changing who's approved doesn't tell anyone.
  f.notices.length = 0;
  await f.json('setDropInMode', { mode: 'approved' }, bedside.credential, legacy);
  assert.equal(f.notices.length, 0);
});

test('while every call is on, a phone call drops in when the carrier verified its caller ID', async () => {
  const cases = [
    { attributes: verified, kind: 'dropIn' },
    { attributes: {}, kind: 'call' },
    { attributes: { 'porch.callerVerification': 'TN-Validation-Passed-B' }, kind: 'call' },
    { caller: 'anonymous', attributes: verified, kind: 'call' },
    { attributes: verified, kind: 'call', mode: 'off' },
    { attributes: verified, kind: 'call', mode: 'approved' },
  ];
  for (const { caller, attributes, kind, mode = 'everyCall' } of cases) {
    const f = fixture(), bedside = await f.setup();
    await f.json('setDropInMode', { mode }, bedside.credential, mode === 'everyCall' ? '123456' : legacy);
    await f.json('poll', { available: true }, bedside.credential);
    await f.webhook(f.phoneCall(caller, attributes));
    const call = (await f.json('poll', { available: true }, bedside.credential)).state.call;
    assert.equal(call.kind, kind, JSON.stringify({ caller, attributes, mode }));
    assert.equal(call.mode, 'voice');
  }
});

test('every caregiver hears about each phone call while every call is on, with its number', async () => {
  const cases = [
    { caller: '+14155550200', attributes: verified, title: 'Dropping in on Mom', body: '(415) 555-0200 · Unknown number' },
    { caller: '+14155550200', attributes: {}, title: 'Calling Mom', body: '(415) 555-0200 · Not verified' },
    { caller: '+14155550300', attributes: verified, title: 'Dropping in on Mom', body: '(415) 555-0300 · On Mom’s keypad' },
    { caller: '+14155550400', attributes: verified, title: 'Dropping in on Mom', body: 'David · (415) 555-0400' },
    // An approved name is never given to a caller ID that wasn't verified.
    { caller: '+14155550400', attributes: {}, title: 'Calling Mom', body: '(415) 555-0400 · Not verified' },
    { caller: 'anonymous', attributes: verified, title: 'Calling Mom', body: 'Hidden number' },
    { caller: '+447700900123', attributes: verified, title: 'Dropping in on Mom', body: '+447700900123 · Unknown number' },
  ];
  for (const { caller, attributes, title, body } of cases) {
    const f = fixture(), bedside = await f.setup();
    const tom = await f.join(bedside, 'Tom', { caregiver: true }), linda = await f.join(bedside, 'Linda', { caregiver: true });
    const lee = await f.join(bedside, 'Lee');
    await f.alerts(tom, 1); await f.alerts(linda, 2); await f.alerts(lee, 3);
    await f.json('setKeypadNumbers', { numbers: ['+14155550300'] }, bedside.credential, legacy);
    await f.json('setPhoneDropIn', { number: '+14155550400', name: 'David', enabled: true }, bedside.credential, legacy);
    await f.json('setDropInMode', { mode: 'everyCall' }, tom.credential, '123456');
    await f.json('poll', { available: true }, bedside.credential);
    f.notices.length = 0;
    const event = f.phoneCall(caller, attributes);
    await f.webhook(event);
    // A retried webhook doesn't tell anyone twice.
    await f.webhook(event);
    const call = f.house(bedside).call;
    // Whoever turned it on hears too; family who aren't caregivers don't.
    assert.deepEqual(f.notices.map(n => n.recipientID).sort(), [tom.state.me.id, linda.state.me.id].sort(), caller);
    for (const notice of f.notices) assert.deepEqual({ type: notice.type, callID: notice.callID, title: notice.title, body: notice.body },
      { type: 'callNotice', callID: call.id, title, body }, JSON.stringify({ caller, attributes }));
  }
});

test('no call notices while every call is off', async () => {
  const f = fixture(), bedside = await f.setup(), tom = await f.join(bedside, 'Tom', { caregiver: true });
  await f.alerts(tom, 1);
  await f.webhook(f.phoneCall('+14155550200', verified));
  assert.equal(f.notices.length, 0);
  assert.equal((await f.json('poll', { available: true }, tom.credential)).state.bedsideCall, undefined);
});

test('caregivers see the call live and end it without the PIN', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { caregiver: true }), lee = await f.join(bedside, 'Lee');
  await f.json('setPhoneDropIn', { number: '+14155550200', name: 'David', enabled: true }, bedside.credential, legacy);
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  await f.json('poll', { available: true }, bedside.credential);
  const event = f.phoneCall('+14155550200', verified);
  await f.webhook(event);
  const id = f.house(bedside).call.id;
  assert.deepEqual((await f.json('poll', { available: true }, tom.credential)).state.bedsideCall, { id, title: 'David', kind: 'dropIn', state: 'pending' });
  assert.equal((await f.json('poll', { available: true }, lee.credential)).state.bedsideCall, undefined);
  await f.json('poll', { available: true }, bedside.credential);
  f.advance(5);
  await f.json('acceptCall', { callID: id, available: true }, bedside.credential);
  assert.deepEqual((await f.json('poll', { available: true }, tom.credential)).state.bedsideCall, { id, title: 'David', kind: 'dropIn', state: 'accepted', acceptedAt: f.now() });
  // An approved number's call goes on after every call is turned off, and stays on the Call tab to be ended.
  await f.json('turnOffEveryCall', {}, tom.credential);
  assert.equal(f.house(bedside).call.state, 'accepted');
  assert.equal((await f.send('endBedsideCall', { callID: id }, lee.credential)).status, 403);
  assert.equal((await f.send('endBedsideCall', { callID: id }, bedside.credential)).status, 403);
  await f.json('endBedsideCall', { callID: randomUUID() }, tom.credential);
  assert.equal(f.house(bedside).call.state, 'accepted');
  const ended = await f.json('endBedsideCall', { callID: id }, tom.credential);
  assert.equal(ended.state.bedsideCall, undefined);
  assert.equal(f.house(bedside).call.state, 'ended');
  assert.ok(f.ended.includes(event.room.name));
  // From the notice after it's over: nothing to do.
  await f.json('endBedsideCall', { callID: id }, tom.credential);
});

test('a phone call that came in before every call was turned on can’t be ended from a caregiver’s phone', async () => {
  const f = fixture(), bedside = await f.setup(), tom = await f.join(bedside, 'Tom', { caregiver: true });
  await f.webhook(f.phoneCall('+14155550200', verified));
  const id = f.house(bedside).call.id;
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  assert.equal((await f.json('poll', { available: true }, tom.credential)).state.bedsideCall, undefined);
  await f.json('endBedsideCall', { callID: id }, tom.credential);
  assert.equal(f.house(bedside).call.state, 'pending');
});

test('turning every call off ends an unknown number’s drop-in', async () => {
  const f = fixture(), bedside = await f.setup(), tom = await f.join(bedside, 'Tom', { caregiver: true });
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  await f.json('poll', { available: true }, bedside.credential);
  const event = f.phoneCall('+14155550200', verified);
  await f.webhook(event);
  assert.equal((await f.json('poll', { available: true }, tom.credential)).state.bedsideCall.title, '(415) 555-0200');
  await f.json('turnOffEveryCall', {}, tom.credential);
  assert.equal(f.house(bedside).call.state, 'ended');
  assert.ok(f.ended.includes(event.room.name));
});

test('turning every call on leaves an approved number’s drop-in going, and calls don’t carry how they came in', async () => {
  const f = fixture(), bedside = await f.setup();
  await f.json('setPhoneDropIn', { number: '+14155550200', name: 'David', enabled: true }, bedside.credential, legacy);
  await f.json('setDropInMode', { mode: 'approved' }, bedside.credential, legacy);
  await f.json('poll', { available: true }, bedside.credential);
  await f.webhook(f.phoneCall('+14155550200', verified));
  assert.equal(f.house(bedside).call.kind, 'dropIn');
  await f.json('setDropInMode', { mode: 'everyCall' }, bedside.credential, '123456');
  assert.equal(f.house(bedside).call.state, 'pending');
  await f.json('endCall', { callID: f.house(bedside).call.id }, bedside.credential);
  await f.webhook(f.phoneCall('+14155550300', verified));
  assert.ok(f.house(bedside).call.everyCall);
  assert.equal((await f.json('poll', { available: true }, bedside.credential)).state.call.everyCall, undefined);
});
