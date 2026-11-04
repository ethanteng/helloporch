import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { test } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';

// Real responses from POST /api/family, saved in tests/fixtures/ for the iOS (PorchCore) and Android (:core) tests
// to decode, so a server change that would break either app fails CI. A change here that's meant: run
// `UPDATE_CONTRACT_FIXTURES=1 npm test`, then check both apps still decode the new files.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key, value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key, after); return true; }
}
const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-not-real', PORCH_CONTACT_SETUP_CODE: 'private-test-caregiver-secret' };
const fixtures = new URL('./fixtures/', import.meta.url);

// Server-made IDs are random, so each one becomes a stable stand-in, numbered by first appearance across all files.
const ids = new Map();
const stable = value => JSON.parse(JSON.stringify(value).replace(/[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/g, id => {
  if (!ids.has(id)) ids.set(id, `00000000-0000-4000-8000-${String(ids.size + 1).padStart(12, '0')}`);
  return ids.get(id);
}));

test('saved server responses still match what the server sends', async () => {
  const saved = Object.fromEntries(Object.keys(env).map(key => [key, process.env[key]]));
  Object.assign(process.env, env);
  try {
    const store = new MemoryStore(), now = 1_800_000_000;
    const device = n => ({ deviceID: `00000000-0000-4000-8000-${String(900 + n).padStart(12, '0')}`, deviceSecret: String(n).repeat(64).slice(0, 64) });
    const send = (action, values = {}, credential, pin) => handleFamily(new Request('https://porch.example/api/family', { method: 'POST',
      headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(pin ? { 'X-Porch-Setup-Code': pin } : {}) },
      body: JSON.stringify({ action, ...values }) }), { store, now: () => now, sendPush: async () => ({ delivered: true }) });
    const json = async (status, ...args) => { const response = await send(...args); assert.equal(response.status, status, await response.clone().text()); return response.json(); };

    // Mom's iPad, a caregiver on an iPhone and a cousin on an Android phone.
    const bedside = await json(200, 'createHousehold', { name: 'Mom', ...device(1) }, undefined, env.PORCH_CONTACT_SETUP_CODE);
    await json(200, 'initializeCaregiverPIN', { pin: '123456' }, bedside.credential);
    const invite = (name, caregiver) => json(200, 'createInvite', { name, permissions: { audio: true, video: true }, caregiver }, bedside.credential, '123456');
    const ethan = await json(200, 'claimInvite', { code: (await invite('Ethan', true)).code, ...device(2) });
    const lee = await json(200, 'claimInvite', { code: (await invite('Lee', false)).code, platform: 'android', ...device(3) });
    await invite('Sam', false);
    for (const credential of [bedside.credential, ethan.credential, lee.credential]) await json(200, 'poll', { available: true }, credential);

    const responses = {
      'bedside-poll': await json(200, 'poll', { available: true }, bedside.credential),
      'family-poll': await json(200, 'poll', { available: true }, ethan.credential),
      'caregiver-admin': await json(200, 'verifyPIN', {}, ethan.credential, '123456'),
    };
    await json(200, 'startCall', { targetID: ethan.state.me.id, mode: 'video', kind: 'call' }, bedside.credential);
    responses['family-incoming-call'] = await json(200, 'poll', { available: true }, ethan.credential);
    // An answered call has no time limit, so its expiresAt is Number.MAX_SAFE_INTEGER: more than 32 bits.
    await json(200, 'acceptCall', { callID: responses['family-incoming-call'].state.call.id, available: true }, ethan.credential);
    responses['family-answered-call'] = await json(200, 'poll', { available: true }, ethan.credential);
    assert.equal(responses['family-answered-call'].state.call.expiresAt, Number.MAX_SAFE_INTEGER);
    responses['error-busy'] = await json(409, 'startCall', { targetID: lee.state.me.id, mode: 'voice', kind: 'call' }, bedside.credential);

    for (const [name, response] of Object.entries(responses)) {
      const file = new URL(`${name}.json`, fixtures), body = `${JSON.stringify(stable(response), null, 2)}\n`;
      if (process.env.UPDATE_CONTRACT_FIXTURES) { await writeFile(file, body); continue; }
      assert.equal(await readFile(file, 'utf8'), body, `${name}.json no longer matches. If that's intended, run UPDATE_CONTRACT_FIXTURES=1 npm test.`);
    }
    assert.ok(!JSON.stringify(responses).includes(env.PORCH_CONTACT_SETUP_CODE));
  } finally {
    for (const [key, value] of Object.entries(saved)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});
