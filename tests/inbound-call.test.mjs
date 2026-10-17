import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { AccessToken, ParticipantInfo, TokenVerifier } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';
import { handleInboundWebhook, inboundRoomPrefix } from '../lib/family/inbound.ts';

const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-not-real', PORCH_CONTACT_SETUP_CODE: 'private-test-caregiver-secret' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k, process.env[k]])); Object.assign(process.env, env); });
afterEach(() => { for (const [k, v] of Object.entries(previous)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key, value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key, after); return true; }
}
function fixture(overrides = {}) {
  const store = new MemoryStore(), ended = [], participants = new Map();
  let now = Math.floor(Date.now() / 1000), lookupFailure = false, cleanupFailure = false;
  const dependencies = { store, now: () => now,
    ...overrides,
    endRoom: async room => { if (cleanupFailure) throw Error('unavailable'); ended.push(room); participants.delete(room); },
    getPhoneParticipant: async (room, identity) => {
      if (lookupFailure) throw Error('unavailable');
      const p = participants.get(room);
      if (!p || p.identity !== identity) throw Object.assign(Error('gone'), { code: 'not_found' });
      return p;
    },
  };
  const send = (action, values = {}, credential, pin) => handleFamily(new Request('https://porch.example/api/family', {
    method: 'POST', headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(pin ? { 'X-Porch-Setup-Code': pin } : {}) },
    body: JSON.stringify({ action, ...values }),
  }), dependencies);
  const json = async (...args) => { const r = await send(...args); assert.equal(r.status, 200, await r.clone().text()); return r.json(); };
  const setup = async (number = '+14155550100') => {
    const bedside = await json('createHousehold', { name: 'Mom', deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') }, undefined, env.PORCH_CONTACT_SETUP_CODE);
    const invitation = await json('createInvite', { name: 'Ethan', permissions: { audio: true, video: true } }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);
    const family = await json('claimInvite', { code: invitation.code, deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') });
    await json('poll', { available: true }, bedside.credential);
    await json('poll', { available: true }, family.credential);
    await store.create(`phone-number:${number}`, JSON.stringify({ householdID: bedside.state.householdID, bedsideID: bedside.state.me.id, trunkID: 'ST_inbound' }));
    return { bedside, family };
  };
  const call = (number = '+14155550100', attributes = {}) => {
    const room = { sid: `RM_${randomUUID()}`, name: `${inboundRoomPrefix}${randomUUID()}` };
    const participant = new ParticipantInfo({ sid: `PA_${randomUUID()}`, identity: `sip_${randomUUID()}`, kind: 3,
      attributes: { 'sip.callID': `SCL_${randomUUID()}`, 'sip.trunkID': 'ST_inbound', 'sip.trunkPhoneNumber': number, 'sip.phoneNumber': '+14155550200', 'sip.callStatus': 'ringing', ...attributes } });
    participants.set(room.name, participant);
    return { id: randomUUID(), createdAt: now, event: 'participant_joined', room, participant: participant.toJson() };
  };
  const webhook = async (event, { tamper = false, unsigned = false } = {}) => {
    const body = JSON.stringify(event);
    const token = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, { ttl: '1m' });
    token.sha256 = createHash('sha256').update(body).digest('base64');
    return handleInboundWebhook(new Request('https://porch.example/api/calls/inbound/webhook', { method: 'POST', headers: unsigned ? {} : { Authorization: await token.toJwt() }, body: tamper ? `${body} ` : body }), dependencies);
  };
  const poll = bedside => json('poll', { available: true }, bedside.credential);
  const house = bedside => JSON.parse(store.values.get(`house:${bedside.state.householdID}`));
  return { store, ended, participants, send, json, setup, call, webhook, poll, house,
    advance: seconds => now += seconds, failLookup: value => lookupFailure = value, failCleanup: value => cleanupFailure = value };
}

test('webhooks require a valid LiveKit signature bound to the exact body', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  assert.equal((await f.webhook(event, { unsigned: true })).status, 401);
  assert.equal((await f.webhook(event, { tamper: true })).status, 401);
  assert.equal(f.house(bedside).call, undefined);
  assert.equal((await f.webhook(event)).status, 200);
  assert.equal((await f.poll(bedside)).state.call.source, 'phone');
});

test('the dialed number chooses the household, even when the same person calls both', async () => {
  const f = fixture(), a = await f.setup(), b = await f.setup('+14155550101');
  const first = f.call(), second = f.call('+14155550101');
  assert.equal((await f.webhook(first)).status, 200);
  assert.equal((await f.webhook(second)).status, 200);
  const callA = (await f.poll(a.bedside)).state.call, callB = (await f.poll(b.bedside)).state.call;
  assert.equal(callA.to, a.bedside.state.me.id); assert.equal(callB.to, b.bedside.state.me.id);
  assert.notEqual(callA.id, callB.id); assert.notEqual(first.room.name, second.room.name);
  assert.equal(callA.callerName, '+14155550200');
  assert.equal(callA.phone, undefined);
  assert.equal((await f.send('acceptCall', { callID: callA.id, available: true }, b.bedside.credential)).status, 404);
  assert.equal((await f.poll(a.family)).state.call, null);
});

test('telephone calls require manual acceptance and issue microphone-only tokens for the SIP room', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  await f.webhook(event);
  const callID = (await f.poll(bedside)).state.call.id;
  assert.equal((await f.send('joinCall', { callID }, bedside.credential)).status, 403);
  const accepted = await f.json('acceptCall', { callID, available: true }, bedside.credential);
  assert.equal(accepted.state.call.kind, 'call'); assert.equal(accepted.state.call.mode, 'voice');
  const join = await f.json('joinCall', { callID }, bedside.credential);
  const token = await new TokenVerifier(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET).verify(join.token);
  assert.equal(join.room, event.room.name);
  assert.deepEqual(token.video.canPublishSources, ['microphone']);
  assert.equal(token.video.canPublishData, false);
  for (let i = 0; i < 8; i++) { f.advance(10); assert.equal((await f.poll(bedside)).state.call.state, 'accepted'); }
});

test('duplicate join events never create a second call or extend the ringing deadline', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  await Promise.all([f.webhook(event), f.webhook(event)]);
  const before = (await f.poll(bedside)).state.call;
  f.advance(6); await f.webhook(event);
  const after = (await f.poll(bedside)).state.call;
  assert.equal(before.id, after.id); assert.equal(before.expiresAt, after.expiresAt);
  await f.json('endCall', { callID: before.id }, bedside.credential);
  await f.webhook(event);
  assert.equal((await f.poll(bedside)).state.call.state, 'ended');
});

test('caller hangup before answer dismisses ringing and delayed joins cannot revive it', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  await f.webhook(event);
  const callID = (await f.poll(bedside)).state.call.id;
  await f.webhook({ ...event, event: 'participant_left' });
  assert.equal((await f.poll(bedside)).state.call.state, 'ended');
  assert.equal((await f.send('acceptCall', { callID, available: true }, bedside.credential)).status, 410);
  await f.webhook(event);
  assert.equal((await f.poll(bedside)).state.call.state, 'ended');
  assert.ok(f.ended.includes(event.room.name));
});

test('hangup delivered before join leaves a tombstone and never starts ringing', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  await f.webhook({ ...event, event: 'participant_left' });
  await f.webhook(event);
  assert.equal((await f.poll(bedside)).state.call, null);
});

test('missed hangup webhooks are reconciled and accept checks the caller immediately', async () => {
  for (const immediateAccept of [false, true]) {
    const f = fixture(), { bedside } = await f.setup(), event = f.call();
    await f.webhook(event); const callID = (await f.poll(bedside)).state.call.id;
    f.participants.delete(event.room.name);
    if (immediateAccept) assert.equal((await f.send('acceptCall', { callID, available: true }, bedside.credential)).status, 410);
    else f.advance(6);
    assert.equal((await f.poll(bedside)).state.call.state, 'ended');
  }
});

test('a LiveKit lookup outage is retryable and is not treated as a caller hangup', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  await f.webhook(event); f.advance(6); f.failLookup(true);
  assert.equal((await f.send('poll', { available: true }, bedside.credential)).status, 503);
  assert.equal(f.house(bedside).call.state, 'pending');
  f.failLookup(false); assert.equal((await f.poll(bedside)).state.call.state, 'pending');
});

test('a second telephone caller is disconnected without disturbing the first', async () => {
  const f = fixture(), { bedside } = await f.setup(), first = f.call(), second = f.call();
  await Promise.all([f.webhook(first), f.webhook(second)]);
  const current = f.house(bedside).call;
  assert.equal(current.state, 'pending');
  assert.equal(f.ended.length, 1);
  assert.notEqual(f.ended[0], current.phone.room);
});

test('Porch calls and inbound telephone calls share the same atomic household reservation', async () => {
  const f = fixture(), { bedside, family } = await f.setup(), event = f.call();
  const [app, phone] = await Promise.all([
    f.send('startCall', { targetID: bedside.state.me.id, mode: 'voice', kind: 'call' }, family.credential), f.webhook(event),
  ]);
  assert.equal(phone.status, 200);
  const current = f.house(bedside).call;
  if (app.status === 200) { assert.equal(current.phone, undefined); assert.ok(f.ended.includes(event.room.name)); }
  else { assert.equal(app.status, 409); assert.equal(current.phone.room, event.room.name); }
});

test('unknown destinations and mismatched trunks never ring a household', async () => {
  const f = fixture(), { bedside } = await f.setup();
  for (const event of [f.call('+14155550999'), f.call(undefined, { 'sip.trunkID': 'ST_other' })]) {
    await f.webhook(event); assert.ok(f.ended.includes(event.room.name));
  }
  assert.equal((await f.poll(bedside)).state.call, null);
});

test('ordinary WebRTC participants cannot impersonate an inbound telephone call using attributes', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  event.participant.kind = 'STANDARD';
  await f.webhook(event);
  assert.equal((await f.poll(bedside)).state.call, null);
});

test('offline bedside devices and expired ringing calls release the SIP room', async () => {
  for (const offline of [false, true]) {
    const f = fixture(), { bedside } = await f.setup();
    if (offline) await f.json('poll', { available: false }, bedside.credential);
    const event = f.call(); await f.webhook(event);
    if (!offline) { f.advance(46); assert.equal((await f.poll(bedside)).state.call.state, 'ended'); }
    else assert.equal(f.house(bedside).call, undefined);
    assert.ok(f.ended.includes(event.room.name));
  }
});

test('phone calls ring for the household ring time before the SIP room is released', async () => {
  for (const seconds of [15, 120]) {
    const f = fixture(), { bedside } = await f.setup();
    await f.json('setRingSeconds', { seconds }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);
    const event = f.call(); await f.webhook(event);
    assert.equal(f.house(bedside).call.expiresAt, event.createdAt + seconds);
    f.advance(seconds - 1); assert.equal((await f.poll(bedside)).state.call.state, 'pending');
    assert.ok(!f.ended.includes(event.room.name));
    f.advance(1); assert.equal((await f.poll(bedside)).state.call.state, 'ended');
    assert.ok(f.ended.includes(event.room.name));
  }
  // A join event older than the ring time never starts ringing.
  const f = fixture(), { bedside } = await f.setup();
  await f.json('setRingSeconds', { seconds: 15 }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);
  const stale = f.call(); f.advance(15); await f.webhook(stale);
  assert.equal(f.house(bedside).call, undefined);
  assert.ok(f.ended.includes(stale.room.name));
});

test('cleanup failure can be retried after state becomes ended', async () => {
  const f = fixture(), { bedside } = await f.setup(), event = f.call();
  await f.webhook(event); const callID = f.house(bedside).call.id;
  f.failCleanup(true);
  assert.equal((await f.send('endCall', { callID }, bedside.credential)).status, 502);
  assert.equal(f.house(bedside).call.state, 'ended');
  f.failCleanup(false);
  await f.json('endCall', { callID }, bedside.credential);
  assert.ok(f.ended.includes(event.room.name));
  const count = f.ended.length;
  await f.poll(bedside); await f.poll(bedside);
  assert.equal(f.ended.length, count);
});

test('bedside media disconnect and room-finished events clear an accepted call', async () => {
  for (const type of ['participant_left', 'room_finished']) {
    const f = fixture(), { bedside } = await f.setup(), event = f.call();
    await f.webhook(event); const callID = f.house(bedside).call.id;
    await f.json('acceptCall', { callID, available: true }, bedside.credential);
    await f.webhook({ ...event, event: type, participant: type === 'participant_left' ? { identity: bedside.state.me.id, sid: 'PA_bedside', kind: 'STANDARD' } : undefined });
    assert.equal((await f.poll(bedside)).state.call.state, 'ended');
    assert.ok(f.ended.includes(event.room.name));
  }
});

test('a delayed hangup for a previous room cannot end a newer call', async () => {
  const f = fixture(), { bedside } = await f.setup(), first = f.call();
  await f.webhook(first); await f.json('endCall', { callID: f.house(bedside).call.id }, bedside.credential);
  const second = f.call(); await f.webhook(second); const id = f.house(bedside).call.id;
  await f.webhook({ ...first, event: 'room_finished' });
  assert.equal(f.house(bedside).call.id, id); assert.equal(f.house(bedside).call.state, 'pending');
});

test('a locked bedside receives one telephone push despite simultaneous and retried webhooks', async () => {
  const pushes = [], f = fixture({ sendPush: async (device, call) => { pushes.push({ device, call }); return { delivered: true }; } });
  const { bedside } = await f.setup(), registration = { token: 'ab'.repeat(32), environment: 'production' };
  await f.json('registerVoIP', registration, bedside.credential);
  await f.json('poll', { available: false }, bedside.credential); f.advance(90);
  const event = f.call();
  await Promise.all([f.webhook(event), f.webhook(event)]);
  await f.webhook(event);
  const call = f.house(bedside).call;
  assert.equal(call.state, 'pending'); assert.equal(pushes.length, 1);
  assert.deepEqual(pushes[0], { device: registration, call: { callID: call.id, recipientID: bedside.state.me.id, callerName: '+14155550200', mode: 'voice', expiresAt: call.expiresAt } });
  assert.equal(f.ended.length, 0);
  await f.json('poll', { available: false, receivedCallID: call.id }, bedside.credential);
  await f.json('acceptCall', { callID: call.id, available: true }, bedside.credential);
  for (let n = 0; n < 8; n++) { f.advance(10); assert.equal((await f.json('poll', { available: false }, bedside.credential)).state.call.state, 'accepted'); }
  await f.json('endCall', { callID: call.id }, bedside.credential);
  await f.webhook(event);
  assert.equal(pushes.length, 1); assert.ok(f.ended.includes(event.room.name));
});

test('failed bedside push cleans up an unreachable telephone leg and removes only the invalid token', async () => {
  const f = fixture({ sendPush: async () => ({ delivered: false, invalidToken: true }) }), { bedside } = await f.setup();
  await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, bedside.credential);
  await f.json('poll', { available: false }, bedside.credential);
  const event = f.call(); await f.webhook(event);
  assert.equal(f.house(bedside).call.state, 'ended'); assert.equal(f.house(bedside).members[0].voip, undefined);
  assert.ok(f.ended.includes(event.room.name));
});

test('lost APNs acknowledgment preserves bedside receipt and answer, including rotated registrations', async () => {
  for (const answer of [false, true]) {
    let deliver, arrived;
    const sent = new Promise(resolve => arrived = resolve);
    const f = fixture({ sendPush: async () => { arrived(); return new Promise(resolve => deliver = resolve); } }), { bedside } = await f.setup();
    await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, bedside.credential);
    await f.json('poll', { available: false }, bedside.credential);
    const event = f.call(), pending = f.webhook(event); await sent;
    const callID = f.house(bedside).call.id;
    await f.json('poll', { available: false, receivedCallID: callID }, bedside.credential);
    await f.json('registerVoIP', { token: 'cd'.repeat(32), environment: 'production' }, bedside.credential);
    if (answer) await f.json('acceptCall', { callID, available: true }, bedside.credential);
    deliver({ delivered: false, invalidToken: true });
    assert.equal((await pending).status, 200);
    assert.equal(f.house(bedside).call.state, answer ? 'accepted' : 'pending');
    assert.equal(f.house(bedside).members[0].voip.token, 'cd'.repeat(32));
    assert.equal(f.ended.length, 0);
  }
});

test('failed pushes retain foreground telephone delivery and withheld caller ID uses a generic name', async () => {
  const pushes = [], f = fixture({ sendPush: async (_, call) => { pushes.push(call); return { delivered: false }; } }), { bedside } = await f.setup();
  await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, bedside.credential);
  const event = f.call(undefined, { 'sip.phoneNumber': 'anonymous' }); await f.webhook(event);
  assert.equal(pushes[0].callerName, 'Phone caller'); assert.equal(f.house(bedside).call.state, 'pending');
  assert.equal(f.ended.length, 0);
});

const verified = { 'porch.callerVerification': 'TN-Validation-Passed-A' };
const approve = (f, bedside, values = {}) => f.json('setPhoneDropIn', { number: '+14155550200', name: 'David', enabled: true, ...values }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);
const allowDropIns = (f, bedside, enabled = true) => f.json('setDropIn', { enabled }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);

test('a carrier-verified, caregiver-approved number drops in with audio after the announcement', async () => {
  const f = fixture(), { bedside } = await f.setup();
  await allowDropIns(f, bedside); await approve(f, bedside);
  const event = f.call(undefined, verified); await f.webhook(event);
  const call = (await f.poll(bedside)).state.call;
  assert.equal(call.kind, 'dropIn'); assert.equal(call.mode, 'voice'); assert.equal(call.source, 'phone');
  assert.equal(call.callerName, 'David'); assert.equal(call.callerNumber, '+14155550200');
  assert.equal((await f.send('acceptCall', { callID: call.id, available: true }, bedside.credential)).status, 409);
  f.advance(5);
  await f.json('acceptCall', { callID: call.id, available: true }, bedside.credential);
  const join = await f.json('joinCall', { callID: call.id }, bedside.credential);
  const token = await new TokenVerifier(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET).verify(join.token);
  assert.equal(join.room, event.room.name);
  assert.deepEqual(token.video.canPublishSources, ['microphone']);
});

test('caller ID without full carrier attestation, an unapproved number, or paused drop-in rings normally', async () => {
  const cases = [
    { attributes: {} }, { attributes: { 'porch.callerVerification': 'TN-Validation-Passed-B' } },
    { attributes: { 'porch.callerVerification': 'TN-Validation-Failed-A' } }, { attributes: { 'porch.callerVerification': 'TN-Validation-Passed-A-Diverted' } },
    { attributes: verified, approved: false }, { attributes: verified, paused: true },
    { attributes: { ...verified, 'sip.phoneNumber': 'anonymous' }, name: 'Phone caller' },
  ];
  for (const { attributes, approved = true, paused = false, name = '+14155550200' } of cases) {
    const f = fixture(), { bedside } = await f.setup();
    await allowDropIns(f, bedside, !paused);
    if (approved) await approve(f, bedside);
    await f.webhook(f.call(undefined, attributes));
    const call = (await f.poll(bedside)).state.call;
    assert.equal(call.kind, 'call', JSON.stringify(attributes));
    // An unverified number is shown as a number, never as the approved person's name.
    assert.equal(call.callerName, name);
    f.advance(6);
    assert.equal((await f.send('acceptCall', { callID: call.id, available: true }, bedside.credential)).status, 200);
  }
});

test('carrier verification is read from LiveKit, not trusted from the webhook body', async () => {
  const f = fixture(), { bedside } = await f.setup();
  await allowDropIns(f, bedside); await approve(f, bedside);
  const event = f.call();
  event.participant.attributes['porch.callerVerification'] = 'TN-Validation-Passed-A';
  await f.webhook(event);
  assert.equal((await f.poll(bedside)).state.call.kind, 'call');
});

test('a locked bedside never auto-answers an approved phone caller; it rings through CallKit instead', async () => {
  const pushes = [], f = fixture({ sendPush: async (_, call) => { pushes.push(call); return { delivered: true }; } }), { bedside } = await f.setup();
  await allowDropIns(f, bedside); await approve(f, bedside);
  await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, bedside.credential);
  await f.json('poll', { available: false }, bedside.credential); f.advance(90);
  await f.webhook(f.call(undefined, verified));
  assert.equal(f.house(bedside).call.kind, 'call'); assert.equal(pushes.length, 1);
});

test('foreground phone drop-ins never send a VoIP push', async () => {
  const pushes = [], f = fixture({ sendPush: async (_, call) => { pushes.push(call); return { delivered: true }; } }), { bedside } = await f.setup();
  await allowDropIns(f, bedside); await approve(f, bedside);
  await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, bedside.credential);
  await f.webhook(f.call(undefined, verified));
  assert.equal(f.house(bedside).call.kind, 'dropIn'); assert.equal(pushes.length, 0);
});

test('removing the number or pausing drop-in ends a phone drop-in and releases the telephone leg', async () => {
  for (const change of ['remove', 'pause']) {
    for (const answered of [false, true]) {
      const f = fixture(), { bedside } = await f.setup();
      await allowDropIns(f, bedside); await approve(f, bedside);
      const event = f.call(undefined, verified); await f.webhook(event);
      const callID = (await f.poll(bedside)).state.call.id;
      if (answered) { f.advance(5); await f.json('acceptCall', { callID, available: true }, bedside.credential); }
      if (change === 'remove') await approve(f, bedside, { enabled: false });
      else await allowDropIns(f, bedside, false);
      assert.equal(f.house(bedside).call.state, 'ended');
      assert.ok(f.ended.includes(event.room.name));
      assert.equal((await f.send('joinCall', { callID }, bedside.credential)).status, 410);
    }
  }
});

test('unrelated access changes keep a connected phone drop-in', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  await allowDropIns(f, bedside); await approve(f, bedside);
  await approve(f, bedside, { number: '+14155550300', name: 'Ana' });
  await f.webhook(f.call(undefined, verified));
  const callID = (await f.poll(bedside)).state.call.id;
  f.advance(5); await f.json('acceptCall', { callID, available: true }, bedside.credential);
  await f.json('setPermissions', { memberID: family.state.me.id, permissions: { audio: false, video: false } }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);
  await approve(f, bedside, { number: '+14155550300', enabled: false });
  await approve(f, bedside, { name: 'Dave' });
  assert.equal(f.house(bedside).call.state, 'accepted'); assert.equal(f.ended.length, 0);
});

test('only PIN-checked caregivers manage approved numbers, and family devices never see them', async () => {
  const f = fixture(), { bedside, family } = await f.setup();
  const set = (values, credential = bedside.credential, pin = env.PORCH_CONTACT_SETUP_CODE) =>
    f.send('setPhoneDropIn', { number: '+14155550200', name: 'David', enabled: true, ...values }, credential, pin);
  assert.equal((await set({}, family.credential)).status, 403);
  assert.equal((await set({}, bedside.credential, null)).status, 403);
  assert.equal((await set({ number: '4155550200' })).status, 400);
  assert.equal((await set({ name: '' })).status, 400);
  assert.equal((await set({ enabled: 'yes' })).status, 400);
  const saved = await approve(f, bedside);
  assert.deepEqual(saved.admin.phoneDropIns, [{ number: '+14155550200', name: 'David' }]);
  assert.deepEqual((await approve(f, bedside, { name: 'Dave' })).state.phoneDropIns, [{ number: '+14155550200', name: 'Dave' }]);
  const seen = await f.json('poll', { available: true }, family.credential);
  assert.equal(seen.state.phoneDropIns, undefined);
  assert.ok(!JSON.stringify(seen).includes('+14155550200'));
  for (let n = 1; n < 20; n++) await approve(f, bedside, { number: `+1415555${String(n).padStart(4, '0')}` });
  assert.equal((await set({ number: '+14155559999' })).status, 400);
  assert.equal((await set({ name: 'David' })).status, 200);
  assert.equal((await approve(f, bedside, { number: '+14155559999', enabled: false })).state.phoneDropIns.length, 20);
});

test('changing an approved number swaps it in one update and ends a drop-in from the old number', async () => {
  const f = fixture(), { bedside } = await f.setup();
  await allowDropIns(f, bedside); await approve(f, bedside);
  const event = f.call(undefined, verified); await f.webhook(event);
  assert.equal((await f.poll(bedside)).state.call.kind, 'dropIn');
  const swapped = await approve(f, bedside, { number: '+14155550300', replacing: '+14155550200' });
  assert.deepEqual(swapped.state.phoneDropIns, [{ number: '+14155550300', name: 'David' }]);
  assert.equal(f.house(bedside).call.state, 'ended'); assert.ok(f.ended.includes(event.room.name));
  for (const values of [{ name: 'David', enabled: true, replacing: '4155550300' }, { enabled: false, replacing: '+14155550300' }]) {
    assert.equal((await f.send('setPhoneDropIn', { number: '+14155550200', ...values }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE)).status, 400);
  }
  assert.deepEqual(f.house(bedside).phoneDropIns, [{ number: '+14155550300', name: 'David' }]);
});
