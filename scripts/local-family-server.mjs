// A Porch server on this computer for trying the apps without real families: the real POST /api/family handler with
// the in-memory store the server tests use. Nothing is kept, and nothing leaves this process: no Redis, no LiveKit
// calls, no push, and phone numbers come from a stand-in for Twilio that makes them up. It sets up a household, "Mom",
// whose stand-in bedside checks in every few seconds, and prints an invitation for a phone to join it and a setup link
// for a new bedside tablet.
//
//   node scripts/local-family-server.mjs [port] [--livekit]
//
// For the Android emulator, forward the port and open a link (android/README.md):
//   adb reverse tcp:3010 tcp:3010
//   adb shell am start -a android.intent.action.VIEW -d '<the porch://pair or porch://activate link>'
//
// --livekit makes calls connect, through a LiveKit server on this computer in dev mode, which is all test keys:
//   livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1
//   adb reverse tcp:7880 tcp:7880 && adb reverse tcp:7881 tcp:7881
// Porch's server only hands out secure LiveKit addresses, so this one says wss:// to the handler and this script
// changes it to ws:// on the way out. The apps take ws:// only for this device.
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { RoomServiceClient } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';

const options = process.argv.slice(2), livekit = options.includes('--livekit');
const port = Number(options.find(option => !option.startsWith('--')) ?? 3010), origin = `http://localhost:${port}`;
// livekit-server --dev's address and keys, which are public test values.
const localLiveKit = { url: 'ws://localhost:7880', secure: 'wss://localhost:7880', key: 'devkey', secret: 'secret' };
const setupCode = randomBytes(24).toString('hex'), pin = '246810';
// What buying a Porch number needs (lib/family/numbers.ts). None of it is real: the stand-ins below are all it reaches.
Object.assign(process.env, { LIVEKIT_URL: livekit ? localLiveKit.secure : 'wss://local.invalid', LIVEKIT_API_KEY: livekit ? localLiveKit.key : 'local',
  LIVEKIT_API_SECRET: livekit ? localLiveKit.secret : randomBytes(24).toString('hex'), PORCH_CONTACT_SETUP_CODE: setupCode,
  TWILIO_ACCOUNT_SID: `AC${'0'.repeat(32)}`, TWILIO_AUTH_TOKEN: 'local', PORCH_SERVER_ORIGIN: 'https://local.invalid', LIVEKIT_SIP_OUTBOUND_TRUNK_ID: 'ST_local',
  LIVEKIT_SIP_URI: 'sip:local.invalid', PORCH_MAX_PHONE_NUMBERS: '20' });
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key, value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key, after); return true; }
}
const store = new MemoryStore();

// A stand-in for Twilio's numbers and LiveKit's trunks, as the server tests fake them. Each area code has made-up 555
// numbers, except 212, which has none, to try choosing another.
const owned = [], trunks = [], rules = [];
const numberServices = () => ({
  provider: {
    async search(query) {
      if ('near' in query) return ['+15105550100', '+14155550100', '+19255550100', '+16505550100'].map(number => ({ number }));
      if (query.areaCode === '212') return [];
      return [1, 2, 3].map(n => `+1${query.areaCode}55501${String(owned.length + n).padStart(2, '0')}`).filter(number => !owned.some(o => o.number === number)).map(number => ({ number }));
    },
    async buy(number, { label }) {
      const bought = { sid: `PN${String(owned.length + 1).padStart(32, '0')}`, number, label };
      owned.push(bought);
      console.log(`${time()} Bought a made-up number for ${label}: ${number}`);
      return { sid: bought.sid, number };
    },
    async find(label) { const found = owned.find(o => o.label === label); return found && { sid: found.sid, number: found.number }; },
  },
  sip: {
    async listSipDispatchRule() { return rules; },
    async listSipInboundTrunk() { return trunks.map(t => ({ ...t, numbers: [...t.numbers] })); },
    async createSipInboundTrunk(name, numbers, options) { const trunk = { sipTrunkId: `ST_local_${trunks.length}`, name, numbers: [...numbers], ...options }; trunks.push(trunk); return { ...trunk, numbers: [...numbers] }; },
    async updateSipInboundTrunk(id, trunk) { trunks[trunks.findIndex(t => t.sipTrunkId === id)] = { ...trunk }; return { ...trunk }; },
    async updateSipInboundTrunkFields(id, fields) { const trunk = trunks.find(t => t.sipTrunkId === id); trunk.numbers.push(...fields.numbers.add); return trunk; },
    async updateSipOutboundTrunkFields() { return {}; },
    async createSipDispatchRule(rule, options) { const made = { sipDispatchRuleId: `SDR_${rules.length}`, rule, ...options }; rules.push(made); return made; },
  },
});
// Closing a call's room: the local LiveKit over plain HTTP, since the handler would use HTTPS, or nothing without one.
const endRoom = async room => {
  if (!livekit) return;
  try { await new RoomServiceClient(localLiveKit.url.replace(/^ws:/, 'http:'), localLiveKit.key, localLiveKit.secret).deleteRoom(room); }
  catch (error) { if (error?.code !== 'not_found') throw error; }
};
const dependencies = { store, numberServices, endRoom };

const time = () => new Date().toISOString().slice(11, 19);
const call = async (action, values = {}, credential, code) => {
  const response = await handleFamily(new Request(`${origin}/api/family`, { method: 'POST', body: JSON.stringify({ action, ...values }),
    headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(code ? { 'X-Porch-Setup-Code': code } : {}) } }), dependencies);
  const body = await response.json();
  if (!response.ok) throw new Error(`${action}: ${body.error}`);
  return body;
};

const bedside = await call('createHousehold', { name: 'Mom', deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') }, undefined, setupCode);
await call('initializeCaregiverPIN', { pin }, bedside.credential);
// Every household has its own number. This one is made up, and shown on family phones' Porch number card.
{
  const key = `house:${bedside.state.householdID}`, raw = await store.get(key), house = JSON.parse(raw);
  house.porchNumber = { number: '+15105550100', assignedAt: Math.floor(Date.now() / 1000) };
  await store.compareAndSet(key, raw, JSON.stringify(house));
}
const invite = async name => (await call('createInvite', { name, permissions: { audio: true, video: true }, caregiver: true }, bedside.credential, pin)).code;
// A new bedside's setup link, as the admin page's invitation sends it: the operator's code authorizes one new household.
const activation = async () => (await call('createBedsideInvite', {}, undefined, setupCode)).code;

// Each device's last check-in, so the log shows when one starts checking in or can take calls, not every poll.
const checkingIn = new Map();
const onRequest = async (request, response) => {
  let body = '';
  for await (const chunk of request) body += chunk;
  if (request.method !== 'POST' || request.url !== '/api/family') { response.writeHead(404).end(); return; }
  // Where Vercel says the request came from, as it does in production, so phoneNumberOptions has a suggestion: Oakland.
  const headers = new Headers(request.headers);
  for (const [name, value] of Object.entries({ 'x-vercel-ip-country': 'US', 'x-vercel-ip-latitude': '37.80', 'x-vercel-ip-longitude': '-122.27' })) if (!headers.has(name)) headers.set(name, value);
  const result = await handleFamily(new Request(`${origin}${request.url}`, { method: 'POST', headers, body }), dependencies);
  let text = await result.text();
  let input = {}, output = {};
  try { input = JSON.parse(body); } catch { /* the handler already answered it */ }
  try { output = JSON.parse(text); } catch { /* not JSON */ }
  // A call's media goes to the LiveKit server on this computer, which has no certificate (see the top of this file).
  if (livekit && output.serverUrl === localLiveKit.secure) text = JSON.stringify({ ...output, serverUrl: localLiveKit.url });
  if (input.action === 'poll' && result.status === 200 && output.state) {
    const me = output.state.me, seen = `${input.available}`;
    if (checkingIn.get(me.id) !== seen) console.log(`${time()} ${me.name}'s ${me.platform ?? 'ios'} ${me.role} is checking in${input.available ? ' and can take calls' : ', not ready for calls'}`);
    checkingIn.set(me.id, seen);
  } else console.log(`${time()} ${input.action ?? '?'} -> ${result.status}${output.error ? ` (${output.error})` : ''}`);
  // An invitation made on a bedside, such as setup's QR code, so a phone can be joined without a camera.
  if (input.action === 'createInvite' && output.code) console.log(`  Invitation it made: porch://pair?${new URLSearchParams({ server: origin, code: output.code })}`);
  const responseHeaders = Object.fromEntries(result.headers);
  delete responseHeaders['content-length'];
  response.writeHead(result.status, responseHeaders).end(text);
};
// `adb reverse` connects to 127.0.0.1. Binding `localhost` is often only ::1, which that forward cannot reach.
const ipv4 = createServer(onRequest);
const ipv6 = createServer(onRequest);
ipv4.listen(port, '127.0.0.1', async () => {
  ipv6.on('error', error => {
    if (error.code !== 'EADDRNOTAVAIL' && error.code !== 'EAFNOSUPPORT' && error.code !== 'EINVAL') throw error;
  });
  ipv6.listen(port, '::1');
  console.log(`Porch is running at ${origin}, with an in-memory household for "Mom". The caregiver PIN is ${pin}.`);
  console.log(livekit ? `Calls connect through LiveKit at ${localLiveKit.url}.` : 'Calls start but never connect. Add --livekit to connect them (see the top of this file).');
  console.log(`Invitation for a phone to join (works once, for a day):\n  porch://pair?${new URLSearchParams({ server: origin, code: await invite('Ethan') })}`);
  console.log(`Setup link for a new bedside tablet (works once, for a day):\n  porch://activate?${new URLSearchParams({ server: origin, code: await activation() })}`);
});

// The bedside checks in, as an iPad on its stand does, and says whenever a family phone comes online or goes off.
const seen = new Map();
setInterval(async () => {
  const { state } = await call('poll', { available: true }, bedside.credential);
  for (const person of state.people) {
    if (seen.get(person.id) === person.online) continue;
    seen.set(person.id, person.online);
    console.log(`${time()} ${person.name}'s ${person.platform} device is ${person.online ? 'online' : 'offline'}`);
  }
}, 5000);
