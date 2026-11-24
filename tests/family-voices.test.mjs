import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';
import { FamilyError } from '../lib/family/household.ts';
import { speechVoice } from '../lib/family/speech.ts';

class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
class FakeMedia {
  blobs = new Map(); folders = [];
  async uploadTarget(pathname, contentType, maximumSizeInBytes, validUntil) { return { url: `https://blob.test/put/${pathname}`, method: 'PUT', headers: { 'x-content-type': contentType }, expiresAt: validUntil }; }
  async downloadURL(pathname, validUntil) { return `https://blob.test/get/${pathname}?until=${validUntil}`; }
  async stat(pathname) { return this.blobs.get(pathname) ?? null; }
  async put(pathname, body, contentType) { this.blobs.set(pathname, { size: body.length, contentType }); }
  async remove(pathnames) { for (const p of pathnames) this.blobs.delete(p); }
  async removeFolder(prefix) { this.folders.push(prefix); for (const p of [...this.blobs.keys()]) if (p.startsWith(prefix)) this.blobs.delete(p); }
}
class FakeVoices {
  made = []; removed = []; used = 0; limit = 10; failRemove = false; failAdd = null; count = 0;
  async slots() { return { used: this.used, limit: this.limit }; }
  async add(name, url) {
    if (this.failAdd) throw this.failAdd;
    const id = `familyVoice${String(++this.count).padStart(8, '0')}`;
    this.made.push({ id, name, url }); this.used++; return id;
  }
  async remove(id) { if (this.failRemove) throw new FamilyError('down', 503); this.removed.push(id); this.used--; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', PORCH_CALL_ACCESS_CODE:'private-test-calling-code', ELEVENLABS_API_KEY:'test-speech-key' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });
const hope = 'OYTbf65OHHFELVut7v2H', jon = 'MFZUKuGQUsGJPQjTS4wC', sukYee = '7rrBp44bogxpbQBDkenR';
const pin = '123456';

async function fixture() {
  const store = new MemoryStore(), media = new FakeMedia(), voices = new FakeVoices(), spoken = [];
  let now = 1_800_000_000;
  const synthesize = async (voiceID, code, text) => { spoken.push({ voiceID, code, text }); return new Uint8Array([1, 2, 3]); };
  const send = (action, values={}, credential, code) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(code?{'X-Porch-Setup-Code':code}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")}:{}),...values})}),{store,media,now:()=>now,endRoom:async()=>{},synthesize,voices});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const failure = async (...args) => { const response=await send(...args); return { status: response.status, error: (await response.json()).error }; };
  const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
  await json('initializeCaregiverPIN',{pin},bedside.credential);
  const join = async (name, caregiver=false) => json('claimInvite',{code:(await json('createInvite',{name,permissions:{audio:true,video:true},caregiver},bedside.credential,pin)).code});
  const linda = await join('Linda', true), tom = await join('Tom', true), ethan = await join('Ethan');
  const house = () => JSON.parse(store.values.get(`house:${bedside.state.householdID}`));
  // A recording uploaded the way the apps do: ask for the upload, PUT it, then make the voice.
  const record = async (credential, { consent = true, seconds = 62 } = {}) => {
    const { upload, pathname } = await json('voiceUpload',{contentType:'audio/mp4',sizeBytes:480_000,durationSeconds:seconds},credential,pin);
    assert.match(upload.url, /^https:\/\/blob\.test\/put\/voices\//);
    await media.put(pathname, new Uint8Array(480_000), 'audio/mp4');
    return { pathname, response: await send('createVoice',{pathname,consent},credential,pin) };
  };
  const bedsideSpeech = async () => (await json('poll',{available:true},bedside.credential)).state.speech;
  return { store, media, voices, spoken, send, json, failure, bedside, linda, tom, ethan, house, record, bedsideSpeech, advance: s => now += s };
}

test('a caregiver records their voice on their phone, and the bedside speaks in it', async () => {
  const f = await fixture();
  const admin = (await f.json('verifyPIN',{},f.linda.credential,pin)).admin;
  assert.equal(admin.bedsideLanguage, 'en');
  assert.equal(admin.speech.languages.en.selected, hope, 'caregiver phones see the voices after the PIN');
  assert.equal(admin.speech.languages.en.voices.length, 3);

  const { pathname, response } = await f.record(f.linda.credential);
  assert.equal(response.status, 200, await response.clone().text());
  const { voiceID, admin: after } = await response.json();
  assert.equal(f.voices.made.length, 1);
  assert.equal(f.voices.made[0].id, voiceID);
  assert.ok(!f.voices.made[0].name.includes('Linda'), 'ElevenLabs never sees names');
  assert.match(f.voices.made[0].url, new RegExp(`^https://blob.test/get/${pathname}`));
  assert.equal(f.media.blobs.has(pathname), false, 'the recording is deleted once the voice is made');
  assert.equal(f.house().members.find(m => m.name === 'Linda').pendingVoice, undefined);

  const mine = after.speech.languages.en.voices.at(-1);
  assert.deepEqual(mine, { id: voiceID, name: 'Linda', detail: 'Family voice', family: true, memberID: f.linda.state.me.id });
  assert.equal(after.speech.languages.en.selected, voiceID, 'it is chosen for the bedside language once made');
  assert.equal(after.speech.languages['yue-Hant'].selected, sukYee, 'other languages keep their choice');
  assert.ok(after.speech.languages.ko.voices.some(v => v.id === voiceID), 'and it is offered in every language');

  const speech = await f.bedsideSpeech();
  assert.equal(speech.languages.en.selected, voiceID);
  const spoken = await f.json('speech',{language:'en',text:'Ethan is dropping in with video.'},f.bedside.credential);
  assert.equal(spoken.clip.voiceID, voiceID);
  assert.deepEqual(f.spoken.at(-1), { voiceID, code: 'en', text: 'Ethan is dropping in with video.' });
  const clip = [...f.media.blobs.keys()].find(p => p.startsWith('speech/'));
  assert.ok(clip.startsWith(`speech/${f.bedside.state.householdID}/voices/${voiceID}/`), 'its clips are kept in its own folder');
});

test('only caregivers record, on their own phone, with the PIN, after agreeing', async () => {
  const f = await fixture();
  const upload = { contentType:'audio/mp4', sizeBytes:480_000, durationSeconds:60 };
  assert.equal((await f.failure('voiceUpload',upload,f.ethan.credential,pin)).status, 403, 'not a caregiver');
  assert.equal((await f.failure('voiceUpload',upload,f.bedside.credential,pin)).status, 403, 'the bedside has no voice of its own');
  assert.equal((await f.failure('voiceUpload',upload,f.linda.credential)).status, 403, 'the PIN is needed');
  assert.equal((await f.failure('voiceUpload',{...upload,durationSeconds:12},f.linda.credential,pin)).error, 'Read for at least 20 seconds.');
  assert.equal((await f.failure('voiceUpload',{...upload,durationSeconds:200},f.linda.credential,pin)).status, 400);
  assert.equal((await f.failure('voiceUpload',{...upload,sizeBytes:6_000_000},f.linda.credential,pin)).status, 413);
  assert.equal((await f.failure('voiceUpload',{...upload,contentType:'video/mp4'},f.linda.credential,pin)).status, 400);

  const { pathname, response } = await f.record(f.linda.credential, { consent: false });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, 'Confirm that this is your voice.');
  assert.equal(f.voices.made.length, 0);
  // Someone else can't use a recording uploaded by another caregiver.
  assert.equal((await f.failure('createVoice',{pathname,consent:true},f.tom.credential,pin)).status, 409);
  assert.equal((await f.json('createVoice',{pathname,consent:true},f.linda.credential,pin)).voiceID, f.voices.made[0].id);
  assert.equal((await f.failure('createVoice',{pathname,consent:true},f.linda.credential,pin)).status, 409, 'a recording makes one voice');
});

test('a full account says so before the recording is sent', async () => {
  const f = await fixture();
  f.voices.used = 10;
  const failed = await f.failure('voiceUpload',{contentType:'audio/mp4',sizeBytes:480_000,durationSeconds:60},f.linda.credential,pin);
  assert.deepEqual(failed, { status: 503, error: 'Recorded voices are full for now.' });
  assert.equal(f.house().members.find(m => m.name === 'Linda').pendingVoice, undefined);
});

test('a recording ElevenLabs rejects is still deleted, and nothing changes', async () => {
  const f = await fixture();
  f.voices.failAdd = new FamilyError("That recording didn't work. Record again somewhere quiet.", 422);
  const { pathname, response } = await f.record(f.linda.credential);
  assert.equal(response.status, 422);
  assert.equal(f.media.blobs.has(pathname), false);
  assert.equal(f.house().members.find(m => m.name === 'Linda').pendingVoice, undefined);
  assert.equal(f.house().speechVoices, undefined);
});

test('recording again replaces the voice wherever it was chosen, and deletes the old one', async () => {
  const f = await fixture();
  const first = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  await f.json('setSpeechVoice',{language:'es',voiceID:first},f.tom.credential,pin);
  await f.json('speech',{language:'en',text:'Hello.'},f.bedside.credential);
  const second = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  assert.notEqual(first, second);
  assert.deepEqual(f.voices.removed, [first]);
  assert.deepEqual(f.media.folders, [`speech/${f.bedside.state.householdID}/voices/${first}/`]);
  assert.equal([...f.media.blobs.keys()].filter(p => p.includes(first)).length, 0, 'its clips are deleted with it');
  const { languages } = await f.bedsideSpeech();
  assert.equal(languages.en.selected, second); assert.equal(languages.es.selected, second);
  assert.equal(languages.en.voices.filter(v => v.family).length, 1);
  assert.equal(f.house().retiredVoices, undefined);
});

test('any caregiver can choose a caregiver’s voice and preview it on their phone', async () => {
  const f = await fixture();
  const lindas = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  await f.json('setSpeechVoice',{language:'en',voiceID:jon},f.tom.credential,pin);
  const preview = await f.json('previewSpeech',{language:'zh-Hant',voiceID:lindas,text:'A family member is dropping in.'},f.tom.credential,pin);
  assert.equal(preview.clip.voiceID, lindas);
  assert.equal(f.spoken.at(-1).code, 'zh', 'a family voice speaks the bedside language');
  assert.equal((await f.failure('previewSpeech',{language:'en',text:'Hi'},f.ethan.credential,pin)).status, 403);
  assert.equal((await f.failure('previewSpeech',{language:'en',text:'Hi'},f.tom.credential)).status, 403, 'the PIN is needed');
  assert.equal((await f.failure('setSpeechVoice',{language:'en',voiceID:'notAVoiceOfThisFamily1'},f.tom.credential,pin)).status, 400);
  await f.json('setSpeechVoice',{language:'en',voiceID:lindas},f.tom.credential,pin);
  assert.equal((await f.bedsideSpeech()).languages.en.selected, lindas);
});

test('phone callers never hear a family voice', async () => {
  const f = await fixture();
  const lindas = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  const house = f.house();
  assert.equal(speechVoice(house, 'en'), lindas);
  assert.equal(speechVoice(house, 'en', false), hope, 'the voicemail greeting uses the language default');
  house.speechVoices.en = null;
  assert.equal(speechVoice(house, 'en', false), null);
});

test('a voice is removed by its caregiver, and when they stop being one or leave', async () => {
  const f = await fixture();
  const householdID = f.bedside.state.householdID;
  const lindas = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  const removed = await f.json('removeVoice',{},f.linda.credential,pin);
  assert.equal(removed.admin.speech.languages.en.selected, hope, 'back to the default');
  assert.equal(removed.admin.speech.languages.en.voices.length, 3);
  assert.deepEqual(f.voices.removed, [lindas]);
  assert.ok(f.media.folders.includes(`speech/${householdID}/voices/${lindas}/`));

  const toms = (await (await f.record(f.tom.credential)).response.json()).voiceID;
  await f.json('setCaregiver',{memberID:f.tom.state.me.id,enabled:false},f.bedside.credential,pin);
  assert.ok(f.voices.removed.includes(toms), 'no longer a caregiver');
  assert.equal(f.house().members.find(m => m.name === 'Tom').voice, undefined);

  const again = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  await f.json('leaveHousehold',{},f.linda.credential);
  assert.ok(f.voices.removed.includes(again), 'left the family');
  assert.equal((await f.bedsideSpeech()).languages.en.selected, hope);
  assert.equal(f.house().retiredVoices, undefined);
});

test('a voice ElevenLabs couldn’t delete is retried on the bedside’s poll, and is never offered meanwhile', async () => {
  const f = await fixture();
  const lindas = (await (await f.record(f.linda.credential)).response.json()).voiceID;
  await f.json('setCaregiver',{memberID:f.tom.state.me.id,enabled:true},f.bedside.credential,pin);
  f.voices.failRemove = true;
  await f.json('revoke',{memberID:f.linda.state.me.id},f.bedside.credential,pin);
  assert.deepEqual(f.house().retiredVoices, [lindas]);
  assert.equal((await f.bedsideSpeech()).languages.en.voices.some(v => v.id === lindas), false);
  f.voices.failRemove = false;
  await f.bedsideSpeech();
  assert.deepEqual(f.voices.removed, [lindas]);
  assert.equal(f.house().retiredVoices, undefined);
});

test('a recording that was never made into a voice is deleted after half an hour', async () => {
  const f = await fixture();
  const { pathname } = await f.json('voiceUpload',{contentType:'audio/mp4',sizeBytes:480_000,durationSeconds:60},f.linda.credential,pin);
  await f.media.put(pathname, new Uint8Array(10), 'audio/mp4');
  await f.bedsideSpeech();
  assert.ok(f.media.blobs.has(pathname));
  f.advance(1801);
  await f.bedsideSpeech();
  assert.equal(f.media.blobs.has(pathname), false);
  assert.equal(f.house().members.find(m => m.name === 'Linda').pendingVoice, undefined);
  assert.equal((await f.failure('createVoice',{pathname,consent:true},f.linda.credential,pin)).status, 409);
});
