import assert from 'node:assert/strict';
import { createHmac, randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';
import { handleTwilioVoice, voicemailMessageID } from '../lib/family/voicemail.ts';

class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
class FakeMedia {
  blobs = new Map(); removed = [];
  async uploadTarget(pathname, contentType, maximumSizeInBytes, validUntil) { return { url: `https://blob.test/put?pathname=${pathname}`, method: 'PUT', headers: { 'x-content-type': contentType }, expiresAt: validUntil }; }
  async downloadURL(pathname) { return `https://blob.test/get/${pathname}`; }
  async stat(pathname) { return this.blobs.get(pathname) ?? null; }
  async remove(pathnames) { for (const p of pathnames) { this.blobs.delete(p); this.removed.push(p); } }
  async put(pathname, body, contentType) { this.blobs.set(pathname, { size: body.byteLength, contentType }); }
  upload(target, size = 1000) { const pathname = new URL(target.url).searchParams.get('pathname'); this.blobs.set(pathname, { size, contentType: target.headers['x-content-type'] }); }
}
class FakeRecordings {
  downloaded = []; removed = [];
  async download(sid) { this.downloaded.push(sid); return new Uint8Array(4000); }
  async remove(sid) { this.removed.push(sid); }
}
const account = 'AC' + 'a'.repeat(32), token = 'twilio-test-token-not-real', porchNumber = '+15550001111', caller = '+15557654321';
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', PORCH_CALL_ACCESS_CODE:'private-test-calling-code',
  TWILIO_ACCOUNT_SID: account, TWILIO_AUTH_TOKEN: token, LIVEKIT_SIP_URI: 'sip:test-project.sip.livekit.cloud' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });
const day = 86400;
const paths = { incoming: '', dialed: '/dialed', recorded: '/recorded', recording: '/recording' };
const sid = (prefix, n) => prefix + n.toString(16).padStart(32, '0');

async function fixture() {
  const store = new MemoryStore(), media = new FakeMedia(), recordings = new FakeRecordings();
  let now = 1_800_000_000;
  const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")}:{}),...values})}),{store,media,now:()=>now,endRoom:async()=>{}});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
  await json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
  const join = async (name, caregiver=false) => json('claimInvite',{code:(await json('createInvite',{name,permissions:{audio:false,video:false},caregiver},bedside.credential,'123456')).code});
  const ethan = await join('Ethan'), sam = await join('Sam', true);
  await store.create(`phone-number:${porchNumber}`, JSON.stringify({ householdID: bedside.state.householdID, bedsideID: bedside.state.me.id, trunkID: 'ST_test' }));
  // A signed Twilio webhook request, as Twilio sends it.
  const twilio = async (step, values, { signature, accountSid = account } = {}) => {
    const url = `https://porch.example/api/calls/inbound/voice${paths[step]}`;
    const params = new URLSearchParams({ AccountSid: accountSid, ...values });
    const data = url + [...params.entries()].sort(([a],[b]) => a < b ? -1 : 1).map(([k,v]) => k+v).join('');
    const response = await handleTwilioVoice(new Request(url, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Twilio-Signature': signature ?? createHmac('sha1', token).update(data).digest('base64') }, body: params.toString() }),
      step, { store, media, recordings, now: () => now });
    return { status: response.status, body: await response.text() };
  };
  // An unanswered call: Twilio asks what to do after the dial, then reports the recording.
  let calls = 0;
  const voicemail = async (from = caller, { status = 'completed', duration = '12' } = {}) => {
    const callSid = sid('CA', ++calls), recordingSid = sid('RE', calls);
    const dialed = await twilio('dialed', { CallSid: callSid, From: from, To: porchNumber, DialCallStatus: 'no-answer' });
    if (!dialed.body.includes('<Record')) return { dialed };
    const recorded = await twilio('recording', { CallSid: callSid, RecordingSid: recordingSid, RecordingStatus: status, RecordingDuration: duration, RecordingUrl: `https://api.twilio.com/2010-04-01/Accounts/${account}/Recordings/${recordingSid}` });
    return { dialed, recorded, callSid, recordingSid, id: voicemailMessageID(recordingSid) };
  };
  const queue = async () => (await json('poll',{available:true},bedside.credential)).state.messages;
  return { store, media, recordings, send, json, bedside, ethan, sam, twilio, voicemail, queue, advance: s => now += s };
}

test('Twilio rings the bedside through LiveKit, and only signed requests are accepted', async () => {
  const f = await fixture();
  const incoming = await f.twilio('incoming', { CallSid: sid('CA', 99), From: caller, To: porchNumber });
  assert.equal(incoming.status, 200);
  assert.match(incoming.body, /<Dial answerOnBridge="true" timeout="25" action="https:\/\/porch\.example\/api\/calls\/inbound\/voice\/dialed" method="POST">/);
  // The SIP login is derived from the LiveKit secret, matching what the setup script sets on the trunk.
  const password = createHmac('sha256', env.LIVEKIT_API_SECRET).update('porch-sip-inbound-v1').digest('base64url');
  assert.ok(incoming.body.includes(`<Sip username="porch" password="${password}">sip:+15550001111@test-project.sip.livekit.cloud;transport=tcp</Sip>`));
  assert.equal((await f.twilio('incoming', { From: caller, To: porchNumber }, { signature: 'bm90LXJpZ2h0' })).status, 403);
  assert.equal((await f.twilio('incoming', { From: caller, To: porchNumber }, { accountSid: 'AC' + 'b'.repeat(32) })).status, 403, 'another Twilio account');
  assert.match((await f.twilio('incoming', { From: caller, To: '+15550009999' })).body, /<Reject\/>/, 'a number with no household');
  assert.match((await f.twilio('dialed', { CallSid: sid('CA', 98), From: caller, To: porchNumber, DialCallStatus: 'completed' })).body, /^<\?xml[^>]*><Response><Hangup\/><\/Response>$/, 'answered calls just end');
  delete process.env.TWILIO_AUTH_TOKEN;
  assert.equal((await f.twilio('incoming', { From: caller, To: porchNumber })).status, 503);
});

test('an unanswered phone call leaves a voicemail that is held until it is released', async () => {
  const f = await fixture();
  const { dialed, recorded, id, recordingSid } = await f.voicemail();
  assert.match(dialed.body, /leave a message after the tone/);
  assert.match(dialed.body, /<Record maxLength="120"[^>]*recordingStatusCallback="https:\/\/porch\.example\/api\/calls\/inbound\/voice\/recording"/);
  assert.equal(recorded.status, 200);
  assert.deepEqual(f.recordings.downloaded, [recordingSid]);
  assert.deepEqual(f.recordings.removed, [recordingSid], 'the provider copy is deleted');
  const pathname = `messages/${f.bedside.state.householdID}/${id}.mp3`;
  assert.deepEqual(f.media.blobs.get(pathname), { size: 4000, contentType: 'audio/mpeg' });
  const [held] = await f.queue();
  assert.deepEqual({ ...held, sentAt: undefined }, { id, from: 'phone', fromName: caller, kind: 'voicemail', mode: 'audio', contentType: 'audio/mpeg', durationSeconds: 12, callerNumber: caller, sentAt: undefined, delivered: false, held: true });
  // A repeated callback doesn't add it twice.
  await f.twilio('recording', { CallSid: sid('CA', 1), RecordingSid: recordingSid, RecordingStatus: 'completed', RecordingDuration: '12' });
  assert.equal((await f.queue()).length, 1);
  assert.match((await f.twilio('recorded', { CallSid: sid('CA', 1) })).body, /Thank you/);
  // The bedside can't play it until it's released.
  assert.equal((await f.send('messageMedia', { messageID: id }, f.bedside.credential)).status, 403);
  // Approved caregivers see that something is waiting; other family members don't.
  assert.equal((await f.json('poll', { available: true }, f.sam.credential)).state.heldMessages, 1);
  assert.equal((await f.json('poll', { available: true }, f.ethan.credential)).state.heldMessages, undefined);
  const review = await f.json('verifyPIN', {}, f.sam.credential, '123456');
  assert.deepEqual(review.admin.messages.map(m => [m.id, m.held, m.callerNumber]), [[id, true, caller]]);
  assert.ok((await f.json('caregiverMessageMedia', { messageID: id }, f.sam.credential, '123456')).media.url, 'caregivers can listen first');
  assert.equal((await f.send('releaseMessage', { messageID: id }, f.sam.credential)).status, 403, 'PIN required');
  assert.equal((await f.json('releaseMessage', { messageID: id }, f.sam.credential, '123456')).admin.messages[0].held, false);
  assert.equal((await f.json('poll', { available: true }, f.sam.credential)).state.heldMessages, 0);
  assert.ok((await f.json('messageMedia', { messageID: id }, f.bedside.credential)).media.url);
  await f.json('messagePlayed', { messageID: id }, f.bedside.credential);
  assert.deepEqual(await f.queue(), []);
});

test('the bedside releases voicemail from callers saved on its keypad; withheld numbers need a caregiver', async () => {
  const f = await fixture();
  const known = await f.voicemail(caller);
  const anonymous = await f.voicemail('+266696687');
  const queued = await f.queue();
  assert.equal(queued.find(m => m.id === anonymous.id).callerNumber, undefined);
  assert.equal(queued.find(m => m.id === anonymous.id).fromName, 'Phone caller');
  assert.equal((await f.send('releaseKnownCaller', { messageID: known.id }, f.sam.credential)).status, 403, 'only the bedside');
  assert.equal((await f.send('releaseKnownCaller', { messageID: anonymous.id }, f.bedside.credential)).status, 403, 'no number to match');
  await f.json('releaseKnownCaller', { messageID: known.id }, f.bedside.credential);
  assert.deepEqual((await f.queue()).map(m => [m.id, m.held]), [[known.id, false], [anonymous.id, true]]);
  await f.json('removeMessage', { messageID: anonymous.id }, f.sam.credential, '123456');
  assert.deepEqual((await f.queue()).map(m => m.id), [known.id]);
  // Held voicemail expires after a week like any other message.
  await f.voicemail('+15551112222');
  f.advance(7 * day + 1);
  assert.deepEqual(await f.queue(), []);
});

test('callers get an apology instead of a recording when voicemail is off, full or empty', async () => {
  const f = await fixture();
  for (let n = 0; n < 3; n++) assert.ok((await f.voicemail()).recorded);
  const limited = await f.voicemail();
  assert.match(limited.dialed.body, /please try again later/i, 'three waiting per caller');
  assert.ok((await f.voicemail('+15559990000')).recorded, 'other callers can still leave one');
  // A call that recorded nothing leaves nothing behind.
  const empty = await f.voicemail('+15558887777', { status: 'absent', duration: '0' });
  assert.ok(f.recordings.removed.includes(empty.recordingSid));
  assert.ok(!(await f.queue()).some(m => m.id === empty.id));
  await f.json('setMessages', { enabled: false }, f.sam.credential, '123456');
  assert.match((await f.voicemail('+15556665555')).dialed.body, /please try again later/i);
});

test('senders replay their own messages while the recording is kept', async () => {
  const f = await fixture();
  const send = async () => {
    const created = await f.json('createMessage', { mode: 'video', contentType: 'video/mp4', sizeBytes: 1000, durationSeconds: 10 }, f.ethan.credential);
    f.media.upload(created.upload);
    return (await f.json('completeMessage', { messageID: created.message.id }, f.ethan.credential)).message;
  };
  const played = await send(), unsent = await send();
  assert.equal(played.replayable, true);
  assert.match((await f.json('sentMessageMedia', { messageID: played.id }, f.ethan.credential)).media.url, /^https:\/\/blob\.test\/get\//);
  assert.equal((await f.send('sentMessageMedia', { messageID: played.id }, f.sam.credential)).status, 404, 'only the sender');
  assert.equal((await f.send('sentMessageMedia', { messageID: played.id }, f.bedside.credential)).status, 403);
  await f.json('unsendMessage', { messageID: unsent.id }, f.ethan.credential);
  assert.equal((await f.send('sentMessageMedia', { messageID: unsent.id }, f.ethan.credential)).status, 404);
  await f.json('messagePlayed', { messageID: played.id }, f.bedside.credential);
  const list = async () => Object.fromEntries((await f.json('listMessages', {}, f.ethan.credential)).messages.map(m => [m.id, m.replayable]));
  assert.deepEqual(await list(), { [played.id]: true, [unsent.id]: false });
  f.advance(91 * day);
  assert.deepEqual(await list(), { [played.id]: false, [unsent.id]: false });
  assert.equal((await f.send('sentMessageMedia', { messageID: played.id }, f.ethan.credential)).status, 404);
});
