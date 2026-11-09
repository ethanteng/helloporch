// A Porch server on this computer for trying the apps without real families: the real POST /api/family handler with
// the in-memory store the server tests use. Nothing is kept, and nothing leaves this process: no Redis, no LiveKit
// calls, no push, and phone numbers come from a stand-in for Twilio that makes them up. Photos and messages are kept in
// memory too and served from /media/, and /api/calls/contacts/authorize has a stand-in that approves keypad numbers.
// Nothing here takes real phone calls, so a call that Block unknown callers turned away is made up:
//   curl -X POST 'http://localhost:3010/local/blocked-call?number=%2B14155550100'
// It's listed on every household that blocks unknown callers, as the phone webhooks would list it. Nothing receives real
// texts either, so a text to the Porch number is made up too, and every household gets it, held for a caregiver unless the
// number is on its keypad or allowed, as the text webhook would queue it:
//   curl -X POST 'http://localhost:3010/local/text?from=%2B14155550200&body=Hi%20Mom&pictures=1'
// Phone voicemail is made up the same way, from a recording sent as the body, and held for a caregiver as the voicemail
// webhook holds it. Leave out from= for a hidden number, and add verified=1 for a caller ID the phone company checked:
//   curl -X POST --data-binary @message.mp3 'http://localhost:3010/local/voicemail?from=%2B14155550300&seconds=12'
// It sets up a household, "Mom",
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
//
// --phone <env file> --phone-from <number> makes phone fallback real: the bedside's calls to regular phones go through
// LiveKit Cloud's phone trunk and Twilio, which ring a real phone and cost money. Only LIVEKIT_URL, LIVEKIT_API_KEY,
// LIVEKIT_API_SECRET and LIVEKIT_SIP_OUTBOUND_TRUNK_ID are read from the file, so nothing here reaches Redis. Calls come
// from --phone-from, which must be a number the Twilio account owns, since this household's own number is made up.
// Approve only your own numbers on the keypad.
//   node scripts/local-family-server.mjs 3010 --livekit --phone .env.local --phone-from +15105550123
// Without --livekit, --phone puts the calls themselves on LiveKit Cloud too, so a caregiver can add a real phone number
// to a call (Add someone → A phone number…), which joins the call's room through the trunk with --phone-from as its
// caller ID. Devices then reach LiveKit Cloud directly, with no adb reverse for 7880 and 7881.
//   node scripts/local-family-server.mjs 3010 --phone .env.local --phone-from +15105550123
//
// --fcm <service account key> rings Android phones while Porch is closed: calls to them go out as real Firebase Cloud
// Messaging pushes, from the Firebase project the key belongs to (the one in the app's google-services.json). Only its
// project ID, client email and private key are read, and never printed. Keep the key out of the repo.
//   node scripts/local-family-server.mjs 3010 --livekit --fcm ../firebase-adminsdk.json
import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { RoomServiceClient, SipClient } from 'livekit-server-sdk';
import { authorizeBedsideCalling, handleFamily } from '../lib/family/service.ts';
import { blockCall } from '../lib/family/screening.ts';
import { receivePhoneVoicemail } from '../lib/family/messages.ts';
import { receiveText } from '../lib/family/texts.ts';
import { handlePhoneCall } from '../lib/calls/phone.ts';

const options = process.argv.slice(2), livekit = options.includes('--livekit');
const valueOf = flag => { const at = options.indexOf(flag); return at < 0 ? undefined : options[at + 1]; };
const port = Number(options.find((option, index) => /^[0-9]+$/.test(option) && !/^--(phone|fcm)/.test(options[index - 1] ?? '')) ?? 3010), origin = `http://localhost:${port}`;
// Real call pushes to Android (see the top of this file), with lib/family/push.ts's own FCM settings.
const fcmFile = valueOf('--fcm');
const fcm = fcmFile && (() => {
  const key = JSON.parse(readFileSync(fcmFile, 'utf8'));
  if (key.type !== 'service_account' || !key.project_id || !key.client_email || !key.private_key) throw new Error(`${fcmFile} isn't a Firebase service account key.`);
  return { FCM_PROJECT_ID: key.project_id, FCM_CLIENT_EMAIL: key.client_email, FCM_PRIVATE_KEY: key.private_key };
})();
// Real phone calls (see the top of this file). Only these four settings are taken from the file.
const phoneFile = valueOf('--phone'), phoneFrom = valueOf('--phone-from');
const phone = phoneFile && (() => {
  const wanted = ['LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET', 'LIVEKIT_SIP_OUTBOUND_TRUNK_ID'], found = {};
  for (const line of readFileSync(phoneFile, 'utf8').split('\n')) {
    const match = /^\s*(?:export\s+)?([A-Z_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (match && wanted.includes(match[1])) found[match[1]] = match[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  const missing = wanted.filter(name => !found[name]);
  if (missing.length) throw new Error(`${phoneFile} has no ${missing.join(', ')}.`);
  if (!/^wss:\/\//.test(found.LIVEKIT_URL)) throw new Error(`LIVEKIT_URL in ${phoneFile} isn't a wss:// address.`);
  if (!/^\+[1-9][0-9]{6,14}$/.test(phoneFrom ?? '')) throw new Error('--phone needs --phone-from with a number the Twilio account owns, such as +15105550123.');
  return { url: found.LIVEKIT_URL, key: found.LIVEKIT_API_KEY, secret: found.LIVEKIT_API_SECRET, trunk: found.LIVEKIT_SIP_OUTBOUND_TRUNK_ID };
})();
// livekit-server --dev's address and keys, which are public test values.
const localLiveKit = { url: 'ws://localhost:7880', secure: 'wss://localhost:7880', key: 'devkey', secret: 'secret' };
const setupCode = randomBytes(24).toString('hex'), pin = '246810';
// What buying a Porch number needs (lib/family/numbers.ts). None of it is real: the stand-ins below are all it reaches.
// Calls go through the LiveKit server on this computer with --livekit, or LiveKit Cloud with only --phone.
const cloudCalls = !livekit && !!phone;
Object.assign(process.env, { LIVEKIT_URL: livekit ? localLiveKit.secure : cloudCalls ? phone.url : 'wss://local.invalid',
  LIVEKIT_API_KEY: livekit ? localLiveKit.key : cloudCalls ? phone.key : 'local',
  LIVEKIT_API_SECRET: livekit ? localLiveKit.secret : cloudCalls ? phone.secret : randomBytes(24).toString('hex'), PORCH_CONTACT_SETUP_CODE: setupCode,
  TWILIO_ACCOUNT_SID: `AC${'0'.repeat(32)}`, TWILIO_AUTH_TOKEN: 'local', PORCH_SERVER_ORIGIN: 'https://local.invalid',
  // The real trunk only with --phone. Porch numbers stay made up either way: their stand-ins below never use it.
  LIVEKIT_SIP_OUTBOUND_TRUNK_ID: phone ? phone.trunk : 'ST_local', LIVEKIT_SIP_URI: 'sip:local.invalid', PORCH_MAX_PHONE_NUMBERS: '20' });
if (fcm) {
  Object.assign(process.env, fcm);
  // Says when a push went out, and what Firebase answered, so a phone that didn't ring can be told from one never sent.
  const send = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const response = await send(input, init);
    // LiveKit's server SDK passes a URL, and other callers a string or a Request.
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url.startsWith('https://fcm.googleapis.com/')) console.log(`${new Date().toISOString().slice(11, 19)} FCM push -> ${response.status}`);
    return response;
  };
}
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
// A call's rooms: the local LiveKit over plain HTTP, since the handler would use HTTPS, or LiveKit Cloud with only
// --phone, or none.
const rooms = () => livekit ? new RoomServiceClient(localLiveKit.url.replace(/^ws:/, 'http:'), localLiveKit.key, localLiveKit.secret)
  : cloudCalls ? new RoomServiceClient(phone.url.replace(/^wss:/, 'https:'), phone.key, phone.secret, { requestTimeout: 8 }) : undefined;
// Closing a call's room.
const endRoom = async room => {
  const client = rooms();
  if (!client) return;
  try { await client.deleteRoom(room); }
  catch (error) { if (error?.code !== 'not_found') throw error; }
};
// Photos and messages, kept in memory and served from /media/ on this server, where Porch's server keeps them in Vercel
// Blob. Each upload is allowed once, for the type and size the handler signed.
const blobs = new Map(), uploads = new Map();
const media = {
  async uploadTarget(pathname, contentType, maximumSizeInBytes, validUntil) {
    uploads.set(pathname, { contentType, maximumSizeInBytes });
    return { url: `${origin}/media/${pathname}`, method: 'PUT', headers: { 'Content-Type': contentType }, expiresAt: validUntil };
  },
  async downloadURL(pathname) { return `${origin}/media/${pathname}`; },
  async stat(pathname) { const blob = blobs.get(pathname); return blob ? { size: blob.body.length, contentType: blob.contentType } : null; },
  async remove(pathnames) { for (const pathname of pathnames) blobs.delete(pathname); },
  async put(pathname, body, contentType) { blobs.set(pathname, { body: Buffer.from(body), contentType }); },
};
// Who is in a call's room, which adding someone checks first, as for endRoom. A phone number added to a call needs the
// real trunk, so it's dialed only with calls on LiveKit Cloud, and with --phone-from as its caller ID, since this
// household's own number is made up.
const phoneGuestServices = () => ({
  rooms: rooms() ?? { async getParticipant() { throw Object.assign(new Error('No LiveKit here.'), { code: 'not_found' }); },
    async listParticipants() { return []; }, async removeParticipant() {} },
  sip: cloudCalls ? {
    async createSipParticipant(trunk, number, room, options) {
      // failover off, as the real server dials: a retry would ring the number twice.
      return new SipClient(phone.url.replace(/^wss:/, 'https:'), phone.key, phone.secret, { requestTimeout: 10, failover: false })
        .createSipParticipant(trunk, number, room, { ...options, fromNumber: phoneFrom });
    },
  } : { async createSipParticipant() {
    // failed_precondition is a dial the handler treats as never started, so it doesn't stay "Calling…" for 75 seconds.
    throw Object.assign(new Error("This test server has no phone line. Start it with --phone and without --livekit."), { code: 'failed_precondition' });
  } },
});
const dependencies = { store, numberServices, endRoom, media, phoneGuestServices };

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
const serveMedia = (request, response, raw) => {
  const pathname = decodeURIComponent(request.url.slice('/media/'.length));
  if (request.method === 'PUT') {
    const allowed = uploads.get(pathname), type = request.headers['content-type'];
    if (!allowed || blobs.has(pathname) || type !== allowed.contentType || raw.length > allowed.maximumSizeInBytes) { response.writeHead(400).end(); return; }
    uploads.delete(pathname);
    blobs.set(pathname, { body: raw, contentType: type });
    console.log(`${time()} stored ${pathname} (${raw.length} bytes)`);
    response.writeHead(200).end();
    return;
  }
  const blob = request.method === 'GET' ? blobs.get(pathname) : undefined;
  if (!blob) { response.writeHead(404).end(); return; }
  response.writeHead(200, { 'Content-Type': blob.contentType, 'Content-Length': blob.body.length }).end(blob.body);
};
// A made-up text to the Porch number, for every household, as the Twilio text webhook would queue it.
const localText = async (request, response) => {
  try {
    const params = new URL(request.url, origin).searchParams;
    const from = params.get('from') ?? '', body = [...(params.get('body') ?? '').trim()].slice(0, 1600).join('');
    const pictures = Math.max(0, Math.min(10, Math.floor(Number(params.get('pictures')) || 0)));
    if (!/^\+[1-9][0-9]{6,14}$/.test(from) || (!body && !pictures)) { response.writeHead(400).end('Pass ?from= with + and the country code, and ?body= or ?pictures=.\n'); return; }
    let queued = 0;
    for (const key of [...store.values.keys()].filter(key => key.startsWith('house:'))) {
      const messageSID = `SM${randomBytes(16).toString('hex')}`;
      if (await receiveText(store, () => media, key.slice('house:'.length), { messageSID, from, body, pictures, attachments: 0 }, Math.floor(Date.now() / 1000))) queued += 1;
    }
    console.log(`${time()} a text from ${from} reached ${queued} household${queued === 1 ? '' : 's'}`);
    response.writeHead(200).end(`Queued for ${queued} household${queued === 1 ? '' : 's'}.\n`);
  } catch (error) {
    console.log(`${time()} local text failed: ${error.message}`);
    if (!response.headersSent) response.writeHead(500).end(`${error.message}\n`);
  }
};

// A stand-in for /api/calls/contacts/authorize, which reads Redis: the real PIN check, then a made-up approval for 30
// days. Numbers starting +44 are refused, to try a country Porch can't call.
const authorizeContact = async (request, response, body) => {
  const reply = (status, value) => {
    console.log(`${time()} contacts/authorize -> ${status}${value.error ? ` (${value.error})` : ''}`);
    response.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(value));
  };
  let input = {};
  try { input = JSON.parse(body); } catch { /* answered below */ }
  try { await call('verifyPIN', {}, (request.headers.authorization ?? '').replace(/^Bearer /, ''), request.headers['x-porch-setup-code']); }
  catch (error) { return reply(403, { error: error.message.replace(/^verifyPIN: /, '') }); }
  if (typeof input.phoneNumber !== 'string' || !/^\+[1-9][0-9]{6,14}$/.test(input.phoneNumber)) return reply(400, { error: 'Enter a phone number with + and its country code.' });
  if (input.phoneNumber.startsWith('+44')) return reply(400, { error: "Porch can't call phone numbers in United Kingdom yet." });
  const expiresAt = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60;
  if (!phone) return reply(200, { authorization: `local.${Buffer.from(JSON.stringify({ phoneNumber: input.phoneNumber, exp: expiresAt })).toString('base64url')}`, expiresAt });
  // With --phone, signed as lib/calls/contacts.ts signs it, so the real phone handler below accepts it.
  const approval = Buffer.from(JSON.stringify({ phoneNumber: input.phoneNumber, audience: origin, exp: expiresAt })).toString('base64url');
  const signature = createHmac('sha256', phone.secret).update(`porch-contact-v1.${setupCode}.${approval}`).digest('base64url');
  reply(200, { authorization: `${approval}.${signature}`, expiresAt });
};

// With --phone, /api/calls/phone/{prepare,start,end}: the real handler, with this household's bedside checked against
// the in-memory store, LiveKit Cloud for the phone's room, and --phone-from as the caller ID.
const phoneCall = async (request, response, body, action) => {
  const result = await handlePhoneCall(new Request(`${origin}${request.url}`, { method: 'POST', headers: new Headers(request.headers), body }), action, {
    store,
    authorize: async incoming => {
      const bedside = await authorizeBedsideCalling(incoming, store);
      if (bedside instanceof Response) return bedside;
      return { ...bedside, serverUrl: phone.url, apiKey: phone.key, apiSecret: phone.secret, fromNumber: phoneFrom };
    },
  });
  const text = await result.text();
  let output = {};
  try { output = JSON.parse(text); } catch { /* not JSON */ }
  console.log(`${time()} phone/${action} -> ${result.status}${output.error ? ` (${output.error})` : ''}`);
  response.writeHead(result.status, { 'Content-Type': 'application/json' }).end(text);
};
// A made-up phone voicemail for every household that would take one, as the Twilio recording webhook stores it.
const localVoicemail = async (request, response, raw) => {
  try {
    const params = new URL(request.url, origin).searchParams;
    const from = params.get('from') ?? undefined, seconds = Number(params.get('seconds')) || 10;
    if ((from !== undefined && !/^\+[1-9][0-9]{6,14}$/.test(from)) || raw.length === 0) {
      response.writeHead(400).end('Send the recording as the body, and pass ?from= with + and the country code, or leave it out for a hidden number.\n');
      return;
    }
    let queued = 0;
    for (const key of [...store.values.keys()].filter(key => key.startsWith('house:'))) {
      const recording = { id: randomUUID(), callerNumber: from, callerVerified: params.get('verified') === '1', audio: new Uint8Array(raw), durationSeconds: seconds };
      if (await receivePhoneVoicemail(store, media, key.slice('house:'.length), recording, Math.floor(Date.now() / 1000))) queued += 1;
    }
    console.log(`${time()} a voicemail from ${from ?? 'a hidden number'} reached ${queued} household${queued === 1 ? '' : 's'}`);
    response.writeHead(200).end(`Held for ${queued} household${queued === 1 ? '' : 's'}.\n`);
  } catch (error) {
    console.log(`${time()} local voicemail failed: ${error.message}`);
    if (!response.headersSent) response.writeHead(500).end(`${error.message}\n`);
  }
};
const blockedCall = async (request, response) => {
  try {
    const number = new URL(request.url, origin).searchParams.get('number') ?? '';
    if (!/^\+[1-9][0-9]{6,14}$/.test(number)) { response.writeHead(400).end('Pass ?number= with + and the country code.\n'); return; }
    let listed = 0;
    // Snapshot the households first. Recording the call writes into the store while this loop is walking it.
    for (const [key, raw] of [...store.values].filter(([key]) => key.startsWith('house:'))) {
      const house = JSON.parse(raw);
      if (!house.blockUnknownCallers) continue;
      // A number already on the keypad, allowed, or approved for drop-in is not turned away.
      const before = house.blockedCallers?.find(caller => caller.number === number)?.calls ?? 0;
      await blockCall(store, key.slice('house:'.length), randomUUID(), number, Math.floor(Date.now() / 1000));
      const saved = JSON.parse(store.values.get(key));
      const after = saved.blockedCallers?.find(caller => caller.number === number)?.calls ?? 0;
      if (after > before) listed += 1;
    }
    console.log(`${time()} a call from ${number} was blocked by ${listed} household${listed === 1 ? '' : 's'}`);
    response.writeHead(200).end(`Blocked by ${listed} household${listed === 1 ? '' : 's'}.\n`);
  } catch (error) {
    console.log(`${time()} blocked-call failed: ${error.message}`);
    if (!response.headersSent) response.writeHead(500).end(`${error.message}\n`);
  }
};
const onRequest = async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const raw = Buffer.concat(chunks), body = raw.toString();
  if (request.url.startsWith('/media/')) { serveMedia(request, response, raw); return; }
  if (request.method === 'POST' && request.url.startsWith('/local/blocked-call')) { await blockedCall(request, response); return; }
  if (request.method === 'POST' && request.url.startsWith('/local/text')) { await localText(request, response); return; }
  if (request.method === 'POST' && request.url.startsWith('/local/voicemail')) { await localVoicemail(request, response, raw); return; }
  if (request.method === 'POST' && request.url === '/api/calls/contacts/authorize') { await authorizeContact(request, response, body); return; }
  const phoneAction = /^\/api\/calls\/phone\/(prepare|start|end)$/.exec(request.url ?? '')?.[1];
  if (request.method === 'POST' && phoneAction) {
    if (!phone) { response.writeHead(503, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: 'Start the local server with --phone to try phone fallback.' })); return; }
    await phoneCall(request, response, body, phoneAction);
    return;
  }
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
  console.log(livekit ? `Calls connect through LiveKit at ${localLiveKit.url}.` : cloudCalls ? 'Calls connect through LiveKit Cloud, and a caregiver can add a real phone number.'
    : 'Calls start but never connect. Add --livekit to connect them (see the top of this file).');
  if (phone) console.log(`Phone fallback rings real phones through ${new URL(phone.url).host}, from ${phoneFrom}.`);
  if (fcm) console.log(`Android phones ring while Porch is closed, through Firebase project ${fcm.FCM_PROJECT_ID}.`);
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
