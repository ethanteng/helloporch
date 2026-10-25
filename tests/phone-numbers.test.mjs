import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { authorizeBedsideCalling, handleFamily } from '../lib/family/service.ts';
import { twilioNumbers } from '../lib/family/numbers.ts';

// Fake Twilio, LiveKit and storage: these tests never buy a number or place a call.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key, value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key, after); return true; }
}
const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-not-real', PORCH_CONTACT_SETUP_CODE: 'private-test-caregiver-secret',
  LIVEKIT_SIP_OUTBOUND_TRUNK_ID: 'ST_outbound', LIVEKIT_SIP_URI: 'sip:test.sip.livekit.cloud', TWILIO_ACCOUNT_SID: `AC${'0'.repeat(32)}`, TWILIO_AUTH_TOKEN: 'test-twilio-token',
  PORCH_SERVER_ORIGIN: 'https://porch.example', PORCH_MAX_PHONE_NUMBERS: '5' };
const pin = env.PORCH_CONTACT_SETUP_CODE;
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k, process.env[k]])); Object.assign(process.env, env); });
afterEach(() => { for (const [k, v] of Object.entries(previous)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });

function providers() {
  const state = { inventory: { 415: ['+14155550101', '+14155550102'], 628: ['+16285550101'] }, near: ['+14155550103', '+15105550101', '+14155550104'],
    owned: [], searches: [], buys: [], trunks: [], rules: [], inboundAdds: [], outboundAdds: [], loseBuyResponse: false, failSearch: false, liveKitDown: false, onBuy: undefined };
  const down = () => { if (state.liveKitDown) throw Error('LiveKit unavailable'); };
  const provider = {
    async search(query) {
      state.searches.push(query);
      if (state.failSearch) throw Error('Twilio unavailable');
      if ('near' in query) return state.near.map(number => ({ number }));
      return (state.inventory[query.areaCode] ?? []).filter(number => !state.owned.some(o => o.number === number)).map(number => ({ number }));
    },
    async buy(number, options) {
      await state.onBuy?.();
      const owned = { sid: `PN${String(state.owned.length + 1).padStart(32, '0')}`, number, ...options };
      state.owned.push(owned); state.buys.push(owned);
      if (state.loseBuyResponse) { state.loseBuyResponse = false; throw Error('timed out after Twilio sold it'); }
      return { sid: owned.sid, number };
    },
    async find(label) { const o = state.owned.find(o => o.label === label); return o && { sid: o.sid, number: o.number }; },
  };
  const sip = {
    async listSipDispatchRule() { down(); return state.rules; },
    async listSipInboundTrunk() { down(); return state.trunks.map(t => ({ ...t, numbers: [...t.numbers] })); },
    async createSipInboundTrunk(name, numbers, options) {
      down(); const trunk = { sipTrunkId: `ST_shared_${state.trunks.length}`, name, numbers: [...numbers], ...options };
      state.trunks.push(trunk); return { ...trunk, numbers: [...trunk.numbers] };
    },
    async updateSipInboundTrunk(id, trunk) {
      down(); if (state.failTrunkUpdate) { state.failTrunkUpdate = false; throw Error('LiveKit timed out'); }
      state.trunks[state.trunks.findIndex(t => t.sipTrunkId === id)] = { ...trunk }; return { ...trunk };
    },
    async updateSipInboundTrunkFields(id, fields) {
      down(); state.inboundAdds.push({ id, numbers: fields.numbers.add });
      const trunk = state.trunks.find(t => t.sipTrunkId === id);
      for (const n of fields.numbers.add) if (!trunk.numbers.includes(n)) trunk.numbers.push(n);
      return trunk;
    },
    async updateSipOutboundTrunkFields(id, fields) { down(); state.outboundAdds.push({ id, numbers: fields.numbers.add }); return {}; },
    async createSipDispatchRule(rule, options) { down(); const r = { sipDispatchRuleId: `SDR_${state.rules.length}`, rule, ...options }; state.rules.push(r); return r; },
  };
  return { state, services: () => ({ provider, sip }) };
}

function fixture() {
  const store = new MemoryStore(), numbers = providers();
  let now = 1_800_000_000;
  const send = (action, values = {}, credential, code, headers = {}) => handleFamily(new Request('https://porch.example/api/family', { method: 'POST',
    headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(code ? { 'X-Porch-Setup-Code': code } : {}), ...headers },
    body: JSON.stringify({ action, ...(['claimInvite', 'createHousehold', 'enrollBedside'].includes(action) ? { deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') } : {}), ...values }) }),
  { store, now: () => now, numberServices: numbers.services });
  const json = async (...args) => { const response = await send(...args); assert.equal(response.status, 200, await response.clone().text()); return response.json(); };
  const household = async (name = 'Mom') => {
    const bedside = await json('createHousehold', { name }, undefined, pin);
    const invitation = await json('createInvite', { name: 'Ethan', permissions: { audio: true, video: false } }, bedside.credential, pin);
    const family = await json('claimInvite', { code: invitation.code });
    return { bedside, family, id: bedside.state.householdID };
  };
  const house = async id => JSON.parse(await store.get(`house:${id}`));
  const poll = credential => json('poll', { available: true }, credential);
  return { store, numbers, send, json, household, house, poll, advance: seconds => { now += seconds; }, now: () => now };
}

test('a bedside gets a local number that rings it and is its caller ID', async () => {
  const f = fixture(), mom = await f.household();
  assert.equal(mom.bedside.state.porchNumber, undefined);
  const assigned = await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin);
  assert.equal(assigned.porchNumber, '+14155550101');
  assert.equal(assigned.state.porchNumber, '+14155550101');
  assert.equal(assigned.state.phoneSetup, undefined);
  assert.deepEqual(f.numbers.state.buys.map(({ number, voiceURL, label }) => ({ number, voiceURL, label })),
    [{ number: '+14155550101', voiceURL: 'https://porch.example/api/calls/inbound/voice', label: `Porch ${mom.id}` }]);
  // The first number makes the shared trunk: Porch's voicemail login only, its forwarded caller verification, and limits.
  const [trunk] = f.numbers.state.trunks;
  assert.equal(f.numbers.state.trunks.length, 1);
  assert.equal(trunk.name, 'Porch inbound (shared)');
  assert.deepEqual(trunk.numbers, ['+14155550101']);
  assert.equal(trunk.authUsername, 'porch'); assert.ok(trunk.authPassword.length > 20);
  assert.deepEqual(trunk.headersToAttributes, { 'X-Porch-VerStat': 'porch.callerVerification' });
  assert.equal(trunk.ringingTimeout, 120); assert.equal(trunk.maxCallDuration.seconds, 1800n);
  assert.equal(f.numbers.state.rules.length, 1);
  assert.deepEqual(f.numbers.state.rules[0].trunkIds, [trunk.sipTrunkId]);
  assert.equal(f.numbers.state.rules[0].rule.roomPrefix, 'porch-inbound-');
  assert.deepEqual(f.numbers.state.outboundAdds, [{ id: 'ST_outbound', numbers: ['+14155550101'] }]);
  assert.deepEqual(JSON.parse(await f.store.get('phone-number:+14155550101')), { householdID: mom.id, bedsideID: mom.bedside.state.me.id, trunkID: trunk.sipTrunkId });
  assert.equal((await f.house(mom.id)).porchNumber.sid, f.numbers.state.buys[0].sid);
  // Everyone in the family sees the number; only the bedside and caregivers would see a setup still under way.
  assert.equal((await f.poll(mom.family.credential)).state.porchNumber, '+14155550101');

  // A second household shares the trunk, and asking again keeps the number.
  const dad = await f.household('Dad');
  assert.equal((await f.json('assignPhoneNumber', { areaCode: '415' }, dad.bedside.credential, pin)).porchNumber, '+14155550102');
  assert.equal(f.numbers.state.trunks.length, 1);
  assert.deepEqual(f.numbers.state.trunks[0].numbers, ['+14155550101', '+14155550102']);
  assert.equal(f.numbers.state.rules.length, 1);
  assert.equal((await f.json('assignPhoneNumber', { areaCode: '628' }, mom.bedside.credential, pin)).porchNumber, '+14155550101');
  assert.equal(f.numbers.state.buys.length, 2);
});

test('a shared trunk made by a try that stopped is used again, and a catch-all LiveKit rule stops the first number', async () => {
  const f = fixture(), mom = await f.household();
  f.numbers.state.rules.push({ sipDispatchRuleId: 'SDR_everything', trunkIds: [] });
  assert.equal((await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin)).pending, true);
  assert.equal(f.numbers.state.trunks.length, 0, 'no trunk while a rule without trunks would take its calls');
  f.numbers.state.rules.length = 0;
  f.numbers.state.failTrunkUpdate = true;
  f.advance(60); await f.poll(mom.bedside.credential);
  assert.equal(f.numbers.state.trunks.length, 1);
  f.advance(120);
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, '+14155550101');
  assert.equal(f.numbers.state.trunks.length, 1);
  assert.equal(f.numbers.state.trunks[0].maxCallDuration.seconds, 1800n);
  assert.equal(f.numbers.state.rules.length, 1);
  assert.equal(f.numbers.state.buys.length, 1);
});

test("Twilio requests search US local numbers, buy with Porch's voice webhook, and keep numbers out of errors", async () => {
  const requests = [];
  const respond = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  let next = [];
  const twilio = twilioNumbers(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN, async (url, init) => { requests.push({ url: String(url), init }); return next.shift(); });
  next = [respond(200, { available_phone_numbers: [{ phone_number: '+14155550101', locality: 'San Francisco', region: 'CA' }, { phone_number: '+442079460123' }, { phone_number: 'nope' }] })];
  assert.deepEqual(await twilio.search({ areaCode: '415' }), [{ number: '+14155550101', locality: 'San Francisco', region: 'CA' }]);
  const search = new URL(requests[0].url);
  assert.equal(search.pathname, `/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/AvailablePhoneNumbers/US/Local.json`);
  assert.equal(search.searchParams.get('AreaCode'), '415'); assert.equal(search.searchParams.get('VoiceEnabled'), 'true');
  assert.equal(requests[0].init.headers.authorization, `Basic ${Buffer.from(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`).toString('base64')}`);
  assert.equal(requests[0].init.redirect, 'error');
  next = [respond(200, { available_phone_numbers: [] })];
  await twilio.search({ near: { latitude: 37.77493, longitude: -122.41942 } });
  assert.equal(new URL(requests[1].url).searchParams.get('NearLatLong'), '37.7749,-122.4194');

  const sid = `PN${'a'.repeat(32)}`;
  next = [respond(201, { sid, phone_number: '+14155550101' })];
  assert.deepEqual(await twilio.buy('+14155550101', { voiceURL: 'https://porch.example/api/calls/inbound/voice', label: 'Porch house' }), { sid, number: '+14155550101' });
  assert.equal(requests[2].init.method, 'POST');
  assert.ok(requests[2].url.endsWith('/IncomingPhoneNumbers.json'));
  assert.deepEqual(Object.fromEntries(requests[2].init.body), { PhoneNumber: '+14155550101', VoiceUrl: 'https://porch.example/api/calls/inbound/voice', VoiceMethod: 'POST', FriendlyName: 'Porch house' });

  next = [respond(200, { incoming_phone_numbers: [{ sid: `PN${'b'.repeat(32)}`, phone_number: '+14155550199', friendly_name: 'Porch other' }, { sid, phone_number: '+14155550101', friendly_name: 'Porch house' }] })];
  assert.deepEqual(await twilio.find('Porch house'), { sid, number: '+14155550101' });
  next = [respond(200, { incoming_phone_numbers: [] })];
  assert.equal(await twilio.find('Porch nobody'), undefined);

  next = [respond(400, { code: 21422, message: 'Phone number +14155550101 is not available.' })];
  await assert.rejects(twilio.buy('+14155550101', { voiceURL: 'https://porch.example/api/calls/inbound/voice', label: 'Porch house' }),
    error => !error.message.includes('555') && error.message.includes('400'));
});

test('only the bedside, with the caregiver PIN, sets up its number, and only when the server can', async () => {
  const f = fixture(), mom = await f.household();
  assert.notEqual((await f.send('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential)).status, 200);
  await f.json('setCaregiver', { memberID: mom.family.state.me.id, enabled: true }, mom.bedside.credential, pin);
  assert.equal((await f.send('assignPhoneNumber', { areaCode: '415' }, mom.family.credential, pin)).status, 403);
  for (const areaCode of ['911', '41', '4155', '015', 415, undefined]) {
    assert.equal((await f.send('assignPhoneNumber', { areaCode }, mom.bedside.credential, pin)).status, 400, String(areaCode));
  }
  for (const [name, value] of [['TWILIO_AUTH_TOKEN', undefined], ['PORCH_MAX_PHONE_NUMBERS', undefined], ['PORCH_MAX_PHONE_NUMBERS', '0'],
    ['PORCH_SERVER_ORIGIN', 'https://porch.example/api'], ['PORCH_SERVER_ORIGIN', 'http://porch.example'], ['LIVEKIT_SIP_URI', undefined]]) {
    if (value === undefined) delete process.env[name]; else process.env[name] = value;
    assert.equal((await f.send('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin)).status, 503, name);
    process.env[name] = env[name];
  }
  assert.equal(f.numbers.state.buys.length, 0);
});

test('a purchase whose response was lost is found again, never bought twice', async () => {
  const f = fixture(), mom = await f.household();
  f.numbers.state.loseBuyResponse = true;
  const pending = await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin);
  assert.equal(pending.pending, true);
  assert.equal(pending.state.porchNumber, undefined);
  assert.equal(pending.state.phoneSetup.areaCode, '415');
  assert.match(pending.state.phoneSetup.error, /keep trying/);
  // A family member who isn't a caregiver doesn't see setup details.
  assert.equal((await f.poll(mom.family.credential)).state.phoneSetup, undefined);
  // The bedside's poll waits a minute, then picks up the number Twilio already sold.
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, undefined);
  f.advance(60);
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, '+14155550101');
  assert.equal(f.numbers.state.buys.length, 1);
  assert.equal(f.numbers.state.searches.length, 1);
});

test('when LiveKit fails after buying, polls keep trying with a growing wait and finish without buying again', async () => {
  const f = fixture(), mom = await f.household();
  f.numbers.state.liveKitDown = true;
  assert.equal((await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin)).pending, true);
  assert.equal(f.numbers.state.buys.length, 1);
  f.advance(60); await f.poll(mom.bedside.credential);          // second failure: wait two minutes
  assert.equal((await f.house(mom.id)).phoneSetup.attempts, 2);
  f.numbers.state.liveKitDown = false;
  f.advance(60);
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, undefined, 'still waiting');
  f.advance(60);
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, '+14155550101');
  assert.equal(f.numbers.state.buys.length, 1);
  assert.equal((await f.house(mom.id)).phoneSetup, undefined);
  // Households that never asked for a number, such as ones set up by hand, aren't sold one by their polls.
  const dad = await f.household('Dad');
  f.advance(3600); await f.poll(dad.bedside.credential);
  assert.equal(f.numbers.state.buys.length, 1);
});

test('two requests at once buy one number', async () => {
  const f = fixture(), mom = await f.household();
  let release; const waiting = new Promise(resolve => { release = resolve; });
  f.numbers.state.onBuy = () => waiting;
  const first = f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin);
  await new Promise(resolve => setTimeout(resolve, 10));
  const second = await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin);
  assert.equal(second.pending, true);
  release();
  assert.equal((await first).porchNumber, '+14155550101');
  assert.equal(f.numbers.state.buys.length, 1);
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, '+14155550101');
});

test('an area code with no numbers asks for another', async () => {
  const f = fixture(), mom = await f.household();
  const response = await f.send('assignPhoneNumber', { areaCode: '212' }, mom.bedside.credential, pin);
  assert.equal(response.status, 409);
  const body = await response.json();
  assert.equal(body.errorCode, 'noNumbers'); assert.match(body.error, /212/);
  assert.equal((await f.json('assignPhoneNumber', { areaCode: '628' }, mom.bedside.credential, pin)).porchNumber, '+16285550101');
});

test("Porch's limit on numbers stops new ones, never a household that already has its place", async () => {
  process.env.PORCH_MAX_PHONE_NUMBERS = '1';
  const f = fixture(), mom = await f.household(), dad = await f.household('Dad');
  f.numbers.state.liveKitDown = true;
  assert.equal((await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin)).pending, true);
  f.numbers.state.liveKitDown = false;
  const refused = await f.send('assignPhoneNumber', { areaCode: '415' }, dad.bedside.credential, pin);
  assert.equal(refused.status, 503); assert.equal((await refused.json()).errorCode, 'numberLimit');
  f.advance(60);
  assert.equal((await f.poll(mom.bedside.credential)).state.porchNumber, '+14155550101');
  assert.equal(f.numbers.state.buys.length, 1);
});

test('area codes are suggested from where the iPad is, in the US only', async () => {
  const f = fixture(), mom = await f.household();
  const near = { 'x-vercel-ip-country': 'US', 'x-vercel-ip-latitude': '37.7749', 'x-vercel-ip-longitude': '-122.4194' };
  const options = await f.json('phoneNumberOptions', {}, mom.bedside.credential, pin, near);
  assert.equal(options.areaCode, '415'); assert.deepEqual(options.nearby, ['415', '510']);
  assert.deepEqual(f.numbers.state.searches, [{ near: { latitude: 37.7749, longitude: -122.4194 } }]);
  for (const headers of [{ ...near, 'x-vercel-ip-country': 'CA' }, { 'x-vercel-ip-country': 'US' }, {}]) {
    const none = await f.json('phoneNumberOptions', {}, mom.bedside.credential, pin, headers);
    assert.equal(none.areaCode, null); assert.deepEqual(none.nearby, []);
  }
  assert.equal(f.numbers.state.searches.length, 1);
  f.numbers.state.failSearch = true;
  assert.equal((await f.json('phoneNumberOptions', {}, mom.bedside.credential, pin, near)).areaCode, null, 'the caregiver types one instead');
  assert.equal(f.numbers.state.buys.length, 0, 'suggesting never buys');
});

test("the bedside's phone fallback calls out from its own number", async () => {
  const f = fixture(), mom = await f.household();
  const request = () => new Request('https://porch.example/api/calls/phone/prepare', { method: 'POST', headers: { Authorization: `Bearer ${mom.bedside.credential}` } });
  assert.equal((await authorizeBedsideCalling(request(), f.store)).fromNumber, undefined);
  await f.json('assignPhoneNumber', { areaCode: '415' }, mom.bedside.credential, pin);
  const authorized = await authorizeBedsideCalling(request(), f.store);
  assert.equal(authorized.householdID, mom.id); assert.equal(authorized.fromNumber, '+14155550101');
});

test('a bedside set up in the app blocks unknown callers from the start; older setups keep theirs', async () => {
  const f = fixture();
  const enrolled = await f.json('enrollBedside', { pin: '123456', name: 'Pat' }, undefined, pin);
  assert.equal(enrolled.state.callScreening.enabled, true);
  assert.deepEqual(enrolled.state.callScreening.keypadNumbers, []);
  // The keypad report and the caregiver's switch work as before.
  await f.json('setKeypadNumbers', { numbers: ['+14155550199'] }, enrolled.credential, '123456');
  await f.json('setBlockUnknownCallers', { enabled: false }, enrolled.credential, '123456');
  assert.equal((await f.poll(enrolled.credential)).state.callScreening.enabled, false);
  const { bedside } = await f.household();
  assert.equal(bedside.state.callScreening.enabled, false);
  assert.equal(bedside.state.callScreening.keypadNumbers, null);
});
