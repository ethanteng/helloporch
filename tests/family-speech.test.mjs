import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';
import { FamilyError } from '../lib/family/household.ts';
import { speechLimits } from '../lib/family/speech.ts';

class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
class FakeMedia {
  blobs = new Map();
  async downloadURL(pathname, validUntil) { return `https://blob.test/get/${pathname}?until=${validUntil}`; }
  async stat(pathname) { return this.blobs.get(pathname) ?? null; }
  async put(pathname, body, contentType) { this.blobs.set(pathname, { size: body.length, contentType }); }
  async remove(pathnames) { for (const p of pathnames) this.blobs.delete(p); }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', PORCH_CALL_ACCESS_CODE:'private-test-calling-code', ELEVENLABS_API_KEY:'test-speech-key' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });

const voices = { hope:'OYTbf65OHHFELVut7v2H', sukYee:'7rrBp44bogxpbQBDkenR', luckyChan:'R5E9sH7cGUEbuu7YE7K7', sage:'APSIkVZudNbPAwyPoeVO' };
const dropIn = 'Ethan想同您視像通話，五秒後接通。';

async function fixture({ failing = false } = {}) {
  const store = new MemoryStore(), media = new FakeMedia(), spoken = [];
  let now = 1_800_000_000;
  const synthesize = async (voiceID, code, text) => {
    if (failing) throw new FamilyError("Natural voices aren't available right now.", 503);
    spoken.push({ voiceID, code, text }); return new Uint8Array([1, 2, 3]);
  };
  const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")}:{}),...values})}),{store,media,now:()=>now,endRoom:async()=>{},synthesize});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const status = async (...args) => (await send(...args)).status;
  const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
  await json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
  const join = async (name, caregiver=false) => json('claimInvite',{code:(await json('createInvite',{name,permissions:{audio:true,video:true},caregiver},bedside.credential,'123456')).code});
  const ethan = await join('Ethan'), sam = await join('Sam', true);
  const speech = async credential => (await json('poll',{available:true},credential)).state.speech;
  const speak = (text, language = 'yue-Hant', credential = bedside.credential) => send('speech',{language,text},credential);
  return { store, media, spoken, send, json, status, bedside, ethan, sam, speech, speak, advance: s => now += s };
}

test('the bedside offers each language the voices the family listened to, starting with their picks',async()=>{
  const f=await fixture();
  const { languages } = await f.speech(f.bedside.credential);
  assert.deepEqual(Object.keys(languages).sort(),['en','es','yue-Hant','zh-Hans','zh-Hant']);
  assert.equal(languages.en.selected,voices.hope); assert.equal(languages['yue-Hant'].selected,voices.sukYee); assert.equal(languages['zh-Hans'].selected,voices.sage);
  assert.equal(languages['yue-Hant'].voices.length,4); assert.equal(languages.en.voices.length,3);
  for (const language of Object.values(languages)) {
    assert.equal(language.defaultVoice,language.voices[0].id);
    for (const voice of language.voices) assert.ok(voice.name && voice.detail);
  }
  assert.equal(await f.speech(f.ethan.credential),undefined,'family phones never speak announcements');
  delete process.env.ELEVENLABS_API_KEY;
  assert.equal(await f.speech(f.bedside.credential),undefined,'without a speech service the bedside keeps its built-in voices');
});

test('each sentence is read once per voice, then reused',async()=>{
  const f=await fixture();
  const first=await (await f.speak(dropIn)).json();
  assert.deepEqual(f.spoken,[{voiceID:voices.sukYee,code:'yue',text:dropIn}]);
  assert.equal(first.clip.voiceID,voices.sukYee);
  assert.match(first.clip.url,new RegExp(`^https://blob\\.test/get/speech/${f.bedside.state.householdID}/[a-f0-9]{64}\\.mp3\\?`));
  assert.ok(!first.clip.url.includes('Ethan'),'names stay out of where clips are stored');
  assert.deepEqual([...f.media.blobs.values()],[{size:3,contentType:'audio/mpeg'}]);
  const again=await (await f.speak(`  ${dropIn}\n`)).json();
  assert.equal(f.spoken.length,1,'a stored clip is never paid for twice');
  assert.equal(new URL(again.clip.url).pathname,new URL(first.clip.url).pathname);
  // The same words in another language are another clip, in that language's voice.
  await f.speak('Ethan is dropping in with video. Connecting in five seconds.','en');
  assert.deepEqual(f.spoken.at(-1),{voiceID:voices.hope,code:'en',text:'Ethan is dropping in with video. Connecting in five seconds.'});
});

test('a caregiver chooses a listed voice per language, or the built-in voice',async()=>{
  const f=await fixture();
  assert.equal(await f.status('setSpeechVoice',{language:'yue-Hant',voiceID:voices.luckyChan},f.bedside.credential),403,'the PIN is required');
  const saved=await f.json('setSpeechVoice',{language:'yue-Hant',voiceID:voices.luckyChan},f.bedside.credential,'123456');
  assert.equal(saved.state.speech.languages['yue-Hant'].selected,voices.luckyChan);
  assert.equal(saved.state.speech.languages.en.selected,voices.hope,'other languages keep their voices');
  await f.speak(dropIn);
  assert.equal(f.spoken.at(-1).voiceID,voices.luckyChan);
  assert.equal(await f.status('setSpeechVoice',{language:'yue-Hant',voiceID:voices.hope},f.bedside.credential,'123456'),400,'only that language\'s voices');
  assert.equal(await f.status('setSpeechVoice',{language:'fr',voiceID:voices.hope},f.bedside.credential,'123456'),400);
  assert.equal(await f.status('setSpeechVoice',{language:'yue-Hant',voiceID:voices.sukYee},f.ethan.credential,'123456'),403,'only caregivers');
  await f.json('setSpeechVoice',{language:'yue-Hant',voiceID:null},f.sam.credential,'123456');
  assert.equal((await f.speech(f.bedside.credential)).languages['yue-Hant'].selected,null);
  assert.equal((await f.speak(dropIn)).status,409,'the built-in voice needs no clip');
  // Settings preview any listed voice before saving it, but only that language's.
  const preview=await f.send('speech',{language:'yue-Hant',text:dropIn,voiceID:voices.sukYee},f.bedside.credential);
  assert.equal((await preview.json()).clip.voiceID,voices.sukYee);
  assert.equal(f.spoken.at(-1).voiceID,voices.sukYee);
  assert.equal((await f.send('speech',{language:'yue-Hant',text:dropIn,voiceID:voices.hope},f.bedside.credential)).status,400);
});

test('only the bedside asks for announcements, a sentence at a time',async()=>{
  const f=await fixture();
  assert.equal((await f.speak(dropIn,'yue-Hant',f.ethan.credential)).status,403);
  assert.equal((await f.speak('   ')).status,400);
  assert.equal((await f.speak('a'.repeat(speechLimits.textCharacters + 1))).status,400);
  assert.equal((await f.speak(dropIn,'fr')).status,400);
  assert.equal(f.spoken.length,0);
});

test('a daily allowance limits new clips, not stored ones',async()=>{
  const f=await fixture();
  const sentence = n => `${n}`.padEnd(speechLimits.textCharacters,'.');
  const fits = Math.floor(speechLimits.dailyCharacters / speechLimits.textCharacters);
  for (let n=0; n<fits; n++) assert.equal((await f.speak(sentence(n))).status,200);
  assert.equal((await f.speak(sentence(fits))).status,429);
  assert.equal((await f.speak(sentence(0))).status,200,'stored clips still play');
  assert.equal(f.spoken.length,fits);
  f.advance(86400);
  assert.equal((await f.speak(sentence(fits))).status,200,'the allowance resets each day');
});

test('a failed reading stores nothing, so the bedside uses its built-in voice',async()=>{
  const f=await fixture({ failing: true });
  const response=await f.speak(dropIn);
  assert.equal(response.status,503);
  assert.match((await response.json()).error,/aren't available/);
  assert.equal(f.media.blobs.size,0);
});
