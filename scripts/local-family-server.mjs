// A Porch server on this computer for trying the apps without real families: the real POST /api/family handler with
// the in-memory store the server tests use. Nothing is kept, and nothing leaves this process: no Redis, no LiveKit
// calls, no push. It sets up a household, "Mom", whose stand-in bedside checks in every few seconds, and prints an
// invitation for a phone to join it.
//
//   node scripts/local-family-server.mjs [port]
//
// For the Android emulator, forward the port and open the link (android/README.md):
//   adb reverse tcp:3010 tcp:3010
//   adb shell am start -a android.intent.action.VIEW -d '<the porch://pair link>'
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { handleFamily } from '../lib/family/service.ts';

const port = Number(process.argv[2] ?? 3010), origin = `http://localhost:${port}`;
const setupCode = randomBytes(24).toString('hex'), pin = '246810';
Object.assign(process.env, { LIVEKIT_URL: 'wss://local.invalid', LIVEKIT_API_KEY: 'local', LIVEKIT_API_SECRET: randomBytes(24).toString('hex'), PORCH_CONTACT_SETUP_CODE: setupCode });
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key, value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key, after); return true; }
}
const store = new MemoryStore();
const call = async (action, values = {}, credential, code) => {
  const response = await handleFamily(new Request(`${origin}/api/family`, { method: 'POST', body: JSON.stringify({ action, ...values }),
    headers: { ...(credential ? { Authorization: `Bearer ${credential}` } : {}), ...(code ? { 'X-Porch-Setup-Code': code } : {}) } }), { store });
  const body = await response.json();
  if (!response.ok) throw new Error(`${action}: ${body.error}`);
  return body;
};

const bedside = await call('createHousehold', { name: 'Mom', deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') }, undefined, setupCode);
await call('initializeCaregiverPIN', { pin }, bedside.credential);
const invite = async name => (await call('createInvite', { name, permissions: { audio: true, video: true }, caregiver: true }, bedside.credential, pin)).code;

const onRequest = async (request, response) => {
  let body = '';
  for await (const chunk of request) body += chunk;
  if (request.method !== 'POST' || request.url !== '/api/family') { response.writeHead(404).end(); return; }
  const result = await handleFamily(new Request(`${origin}${request.url}`, { method: 'POST', headers: request.headers, body }), { store });
  let action = '?';
  try { action = JSON.parse(body).action; } catch { /* the handler already answered it */ }
  if (action !== 'poll' || result.status !== 200) console.log(`${new Date().toISOString().slice(11, 19)} ${action} -> ${result.status}`);
  response.writeHead(result.status, Object.fromEntries(result.headers)).end(await result.text());
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
  console.log(`Invitation for a phone to join (works once, for a day):\n  porch://pair?${new URLSearchParams({ server: origin, code: await invite('Ethan') })}`);
});

// The bedside checks in, as an iPad on its stand does, and says whenever a family phone comes online or goes off.
const seen = new Map();
setInterval(async () => {
  const { state } = await call('poll', { available: true }, bedside.credential);
  for (const person of state.people) {
    if (seen.get(person.id) === person.online) continue;
    seen.set(person.id, person.online);
    console.log(`${new Date().toISOString().slice(11, 19)} ${person.name}'s ${person.platform} device is ${person.online ? 'online' : 'offline'}`);
  }
}, 5000);
