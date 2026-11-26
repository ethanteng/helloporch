import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';
import { roughly } from '../lib/family/bedside-phone.ts';

// The bedside reports its desk phone with each check-in. Once it's been out for 10 minutes, caregivers are told, and
// their Call tab shows it until it's back; then the caregivers who were told hear that too.
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
  const store = new MemoryStore(), notices = [];
  let now = 1_800_000_000;
  const dependencies = { store, now: () => now,
    sendNotice: async (registration, notice) => { notices.push({ token: registration.token, ...notice }); return { delivered: true }; } };
  const send = (action, values = {}, credential, pin) => handleFamily(new Request('https://porch.example/api/family', { method: 'POST',
    headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(pin ? { 'X-Porch-Setup-Code': pin } : {}) },
    body: JSON.stringify({ action, ...values }) }), dependencies);
  const json = async (...args) => { const r = await send(...args); assert.equal(r.status, 200, await r.clone().text()); return r.json(); };
  const join = async (bedside, name, { caregiver = false, alerts } = {}) => {
    const invite = await json('createInvite', { name, permissions: { audio: true, video: true }, caregiver }, bedside.credential, legacy);
    const member = await json('claimInvite', { code: invite.code, ...device() });
    if (alerts) await json('registerAlerts', { token: String(alerts).repeat(64), environment: 'sandbox' }, member.credential);
    return member;
  };
  const setup = async () => {
    const bedside = await json('createHousehold', { name: 'Rose', ...device() }, undefined, legacy);
    await json('initializeCaregiverPIN', { pin: '123456' }, bedside.credential);
    return bedside;
  };
  let sequence = 0;
  const report = (bedside, phone) => json('poll', { available: true, launch: 'launch-1', sequence: ++sequence, ...(phone !== undefined ? { phone } : {}) }, bedside.credential);
  const house = bedside => JSON.parse(store.values.get(`house:${bedside.state.householdID}`));
  return { notices, send, json, join, setup, report, house, advance: s => now += s, now: () => now };
}
const out = { kind: 'adapter', connected: false }, back = { kind: 'adapter', connected: true };

test('caregivers are told once the phone has been out for 10 minutes, and their Call tab shows it', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { caregiver: true, alerts: 1 }), ann = await f.join(bedside, 'Ann', { caregiver: true, alerts: 2 });
  const lee = await f.join(bedside, 'Lee', { alerts: 3 }), sam = await f.join(bedside, 'Sam', { caregiver: true });
  await f.report(bedside, back);
  const since = f.advance(60);
  await f.report(bedside, out);
  f.advance(599);
  await f.report(bedside, out);
  assert.deepEqual(f.notices, []);
  assert.equal((await f.json('poll', { available: true }, tom.credential)).state.bedsidePhone, undefined);
  f.advance(1);
  await f.report(bedside, out);
  assert.deepEqual(f.notices.map(n => [n.token[0], n.type, n.state, n.title, n.body]).sort(), [
    ['1', 'phone', 'out', 'Rose’s phone isn’t connected', 'Not connected for 10 minutes. The touchscreen still works.'],
    ['2', 'phone', 'out', 'Rose’s phone isn’t connected', 'Not connected for 10 minutes. The touchscreen still works.'],
  ]);
  assert.equal(f.notices.find(n => n.token[0] === '1').recipientID, tom.state.me.id);
  // Once only.
  f.advance(3600);
  await f.report(bedside, out);
  assert.equal(f.notices.length, 2);
  // Caregivers see since when, and how it's plugged in; the rest of the family doesn't.
  for (const caregiver of [tom, sam]) assert.deepEqual((await f.json('poll', { available: true }, caregiver.credential)).state.bedsidePhone, { since, kind: 'adapter' });
  assert.equal((await f.json('poll', { available: true }, lee.credential)).state.bedsidePhone, undefined);
  assert.equal((await f.json('poll', { available: true }, bedside.credential)).state.bedsidePhone, undefined);
  assert.ok(ann);
});

test('when the phone is back, only the caregivers who were told hear it, with how long it was out', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { caregiver: true, alerts: 1 });
  await f.report(bedside, out);
  f.advance(600);
  await f.report(bedside, out);
  // Joined after the first notice: no "back" for them.
  await f.join(bedside, 'Ann', { caregiver: true, alerts: 2 });
  f.advance(900);
  await f.report(bedside, back);
  assert.deepEqual(f.notices.map(n => [n.token[0], n.state, n.title, n.body]), [
    ['1', 'out', 'Rose’s phone isn’t connected', 'Not connected for 10 minutes. The touchscreen still works.'],
    ['1', 'back', 'Rose’s phone is connected again', 'Back after 25 minutes.'],
  ]);
  assert.equal((await f.json('poll', { available: true }, tom.credential)).state.bedsidePhone, undefined);
  // Out and back again, quickly: nothing.
  await f.report(bedside, out);
  f.advance(300);
  await f.report(bedside, back);
  assert.equal(f.notices.length, 2);
});

test('a quick replug, or the seconds the phone takes to connect, says nothing', async () => {
  const f = fixture(), bedside = await f.setup();
  await f.join(bedside, 'Tom', { caregiver: true, alerts: 1 });
  await f.report(bedside, out);
  f.advance(500);
  await f.report(bedside, back);
  f.advance(5);
  await f.report(bedside, out);
  f.advance(500);
  await f.report(bedside, out);
  assert.deepEqual(f.notices, []);
  f.advance(100);
  await f.report(bedside, out);
  assert.equal(f.notices.length, 1);
});

test('no phone set up forgets it; old apps and the background say nothing; only the bedside reports', async () => {
  const f = fixture(), bedside = await f.setup();
  const tom = await f.join(bedside, 'Tom', { caregiver: true, alerts: 1 });
  await f.report(bedside, out);
  f.advance(600);
  await f.report(bedside);
  await f.report(bedside, { kind: 'telephone', connected: false });
  assert.equal(f.house(bedside).bedsidePhone.noticedAt, undefined);
  await f.report(bedside, out);
  assert.equal(f.notices.length, 1);
  // A caregiver turned the phone keypad off at the bedside: no banner, and no "back" either.
  await f.report(bedside, null);
  assert.equal(f.house(bedside).bedsidePhone, undefined);
  assert.equal((await f.json('poll', { available: true }, tom.credential)).state.bedsidePhone, undefined);
  await f.report(bedside, back);
  assert.equal(f.notices.length, 1);
  // A family phone can't report one.
  await f.json('poll', { available: true, phone: out }, tom.credential);
  f.advance(600);
  await f.json('poll', { available: true, phone: out }, tom.credential);
  assert.deepEqual(f.house(bedside).bedsidePhone, { kind: 'adapter', connected: true, since: f.now() - 600 });
});

test('how long, roughly', () => {
  assert.equal(roughly(30), '1 minute');
  assert.equal(roughly(600), '10 minutes');
  assert.equal(roughly(3599), '1 hour');
  assert.equal(roughly(3600 * 3 + 600), '3 hours');
  assert.equal(roughly(86400 * 3), '3 days');
});
