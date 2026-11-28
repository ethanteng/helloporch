import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { leaveCall } from '../lib/family/household.ts';
import { handleFamily } from '../lib/family/service.ts';
import { translationOffered } from '../lib/family/translation.ts';

// Fake storage and a fake translator service: these tests never reach LiveKit.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real',
  PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', LIVEKIT_TRANSLATOR_AGENT:'porch-translator' };
const pin = env.PORCH_CONTACT_SETUP_CODE;
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });

function fixture() {
  const store = new MemoryStore(), calls = [], failing = { value: false };
  const services = {
    start: async (room, metadata) => { if (failing.value) throw new Error('down'); calls.push({ start: room, metadata: JSON.parse(metadata) }); },
    configure: async (room, message) => { if (failing.value) throw new Error('down'); calls.push({ configure: room, message }); },
    stop: async room => { if (failing.value) throw new Error('down'); calls.push({ stop: room }); },
  };
  let now = 1_800_000_000;
  const send = (action, values={}, credential, code) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',
    headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(code?{'X-Porch-Setup-Code':code}:{})},
    body:JSON.stringify({action,...(['claimInvite','createHousehold'].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')}:{}),...values})}),
    {store,now:()=>now,endRoom:async()=>{},translationServices:()=>services});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const member = async (bedside, name) => {
    const invitation = await json('createInvite',{name,permissions:{audio:true,video:true}},bedside.credential,pin);
    return json('claimInvite',{code:invitation.code,name});
  };
  // Ethan calls Mom's bedside, whose app can show translation. David is family but not on the call.
  const connected = async ({ features = ['translation'] } = {}) => {
    const bedside = await json('createHousehold',{name:'Mom'},undefined,pin);
    const ethan = await member(bedside,'Ethan'), david = await member(bedside,'David');
    await json('setBedsideLanguage',{language:'zh-Hant'},bedside.credential,pin);
    await json('poll',{available:true,features},bedside.credential); await json('poll',{available:true},ethan.credential);
    const callID = (await json('startCall',{targetID:bedside.state.me.id,mode:'video',kind:'call'},ethan.credential)).state.call.id;
    await json('acceptCall',{callID,available:true},bedside.credential);
    return { bedside, ethan, david, callID, room:`porch-paired-${callID}`, ids:{ mom:bedside.state.me.id, ethan:ethan.state.me.id } };
  };
  return { store, calls, failing, send, json, connected, advance:s=>now+=s, now:()=>now };
}

test('the family member on the call is offered translation once the bedside app can show it; the bedside is not', async () => {
  const f=fixture(),{bedside,ethan,callID}=await f.connected();
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translationAvailable,true);
  assert.equal((await f.json('poll',{available:true,features:['translation']},bedside.credential)).state.call.translationAvailable,undefined);
  // A check-in that doesn't say, such as the app going to the background, changes nothing.
  await f.json('poll',{available:false},bedside.credential);
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translationAvailable,true);
  // A bedside app that says it can't: the button goes away, and the server refuses.
  await f.json('poll',{available:true,features:[]},bedside.credential);
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translationAvailable,undefined);
  const refused=await f.send('setCallTranslation',{callID,on:true},ethan.credential);
  assert.equal(refused.status,409); assert.match((await refused.json()).error,/Update Porch on the bedside/);
  assert.deepEqual(f.calls,[]);
});

test("the bedside's check-ins keep its language current, so translation starts in it without anyone saving settings", async () => {
  const f=fixture(),{bedside,ethan,callID}=await f.connected();
  await f.json('poll',{available:true,features:['translation'],language:'ko'},bedside.credential);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.bedsideLanguage,'ko');
  await f.json('poll',{available:true,features:['translation'],language:'klingon'},bedside.credential);
  await f.json('setCallTranslation',{callID,on:true},ethan.credential);
  assert.equal(f.calls[0].metadata.bedsideLanguage,'ko');
  assert.equal(f.calls[0].metadata.bedsideVoice,'uyVNoMrnUku1dZyVEXwD');
  // A family phone can't set it.
  await f.json('poll',{available:true,language:'es'},ethan.credential);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.bedsideLanguage,'ko');
});

test('an earlier check-in cannot put the bedside language back or hide translation', async () => {
  const f=fixture(),{bedside,ethan}=await f.connected(), launch=randomUUID();
  await f.json('poll',{available:true,features:['translation'],language:'ko',launch,sequence:2},bedside.credential);
  // The one sent just before, arriving late: the language Porch had, and an app that says it can't translate.
  await f.json('poll',{available:true,features:[],language:'en',launch,sequence:1},bedside.credential);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.bedsideLanguage,'ko');
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translationAvailable,true);
  // The newest check-in still counts, including one that says the app can't show translation.
  await f.json('poll',{available:true,features:[],language:'es',launch,sequence:3},bedside.credential);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.bedsideLanguage,'es');
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translationAvailable,undefined);
  // Closing Porch sends a newer check-in that doesn't mention language. It must not wipe what was just said.
  await f.json('poll',{available:false,launch,sequence:4},bedside.credential);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.bedsideLanguage,'es');
});

test('translation is offered only once the server knows the translator', async () => {
  const f=fixture(),{ethan,callID}=await f.connected();
  delete process.env.LIVEKIT_TRANSLATOR_AGENT;
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translationAvailable,undefined);
  assert.equal((await f.send('setCallTranslation',{callID,on:true},ethan.credential)).status,409);
});

test('translation speaks a caregiver’s words in their own voice, and everyone else in a listed one', async () => {
  const f = fixture(), { bedside, ethan, callID } = await f.connected();
  const key = `house:${bedside.state.householdID}`;
  const house = JSON.parse(f.store.values.get(key));
  const member = house.members.find(m => m.id === ethan.state.me.id);
  member.caregiver = true;
  member.voice = { id: 'familyVoice00000001', createdAt: 1 };
  house.speechVoices = { 'zh-Hant': 'familyVoice00000001', en: 'familyVoice00000001', ko: 'familyVoice00000001' };
  f.store.values.set(key, JSON.stringify(house));
  await f.json('setCallTranslation', { callID, on: true }, ethan.credential);
  assert.equal(f.calls[0].metadata.bedsideVoice, 'Z8Aisvg1z70p27kGvkZZ');
  assert.equal(f.calls[0].metadata.familyVoice, 'OYTbf65OHHFELVut7v2H');
  // The translator speaks only Ethan's own words in his voice (translator/src/agent.ts).
  assert.deepEqual(f.calls[0].metadata.ownVoices, { [ethan.state.me.id]: 'familyVoice00000001' });
  await f.json('setCallTranslation', { callID, on: true, language: 'ko' }, ethan.credential);
  assert.equal(f.calls[1].message.voice, 'uyVNoMrnUku1dZyVEXwD');
});

test('turning translation on brings the translator in with the bedside language and the family voices', async () => {
  const f=fixture(),{bedside,ethan,callID,room,ids}=await f.connected();
  const on=await f.json('setCallTranslation',{callID,on:true},ethan.credential);
  assert.deepEqual(f.calls,[{ start:room, metadata:{ bedside:ids.mom, bedsideLanguage:'zh-Hant', bedsideVoice:'Z8Aisvg1z70p27kGvkZZ',
    familyLanguage:'en', familyVoice:'OYTbf65OHHFELVut7v2H', by:ids.ethan } }]);
  assert.deepEqual(on.translation,{on:true,language:'zh-Hant',by:ids.ethan,at:f.now()});
  assert.deepEqual(on.state.call.translation,on.translation);
  assert.deepEqual((await f.json('poll',{available:true,features:['translation']},bedside.credential)).state.call.translation,on.translation);
  // Turning it on again while it's on doesn't bring in a second translator.
  await f.json('setCallTranslation',{callID,on:true},ethan.credential);
  assert.equal(f.calls.length,1);
});

test('choosing another language during the call tells the translator; it lasts only for this call', async () => {
  const f=fixture(),{ethan,callID,room}=await f.connected();
  await f.json('setCallTranslation',{callID,on:true},ethan.credential);
  const changed=await f.json('setCallTranslation',{callID,on:true,language:'yue-Hant'},ethan.credential);
  assert.deepEqual(f.calls[1],{ configure:room, message:{ type:'language', language:'yue-Hant', voice:'7rrBp44bogxpbQBDkenR' } });
  assert.equal(changed.translation.language,'yue-Hant');
  // Off and on again keeps the call's choice; the bedside setting itself is unchanged.
  await f.json('setCallTranslation',{callID,on:false},ethan.credential);
  await f.json('setCallTranslation',{callID,on:true},ethan.credential);
  assert.equal(f.calls[3].metadata.bedsideLanguage,'yue-Hant');
  assert.equal((await f.json('setCallTranslation',{callID,on:false},ethan.credential)).translation.on,false);
});

test('turning it off takes the translator out', async () => {
  const f=fixture(),{ethan,callID,room}=await f.connected();
  await f.json('setCallTranslation',{callID,on:true},ethan.credential);
  const off=await f.json('setCallTranslation',{callID,on:false},ethan.credential);
  assert.deepEqual(f.calls[1],{ stop:room });
  assert.equal(off.state.call.translation.on,false);
  await f.json('setCallTranslation',{callID,on:false},ethan.credential);
  assert.equal(f.calls.length,2,'already off: nothing to take out');
});

test('only the family member on the call can turn it on, and only while the call is on', async () => {
  const f=fixture(),{bedside,ethan,david,callID}=await f.connected();
  assert.equal((await f.send('setCallTranslation',{callID,on:true},bedside.credential)).status,403);
  assert.equal((await f.send('setCallTranslation',{callID,on:true},david.credential)).status,403);
  assert.equal((await f.send('setCallTranslation',{callID:'other',on:true},ethan.credential)).status,409);
  assert.equal((await f.send('setCallTranslation',{callID,on:'yes'},ethan.credential)).status,400);
  assert.equal((await f.send('setCallTranslation',{callID,on:true,language:'fr'},ethan.credential)).status,400);
  await f.json('endCall',{callID},ethan.credential);
  assert.equal((await f.send('setCallTranslation',{callID,on:true},ethan.credential)).status,409);
  assert.deepEqual(f.calls,[]);
});

test('a call that goes on turns translation off when either end leaves, and it is no longer offered', () => {
  const call = () => ({ from: 'ethan', to: 'mom', state: 'accepted', left: {},
    porchGuests: [{ id: 'g', memberID: 'david', state: 'joined' }],
    translation: { on: true, language: 'zh-Hant', by: 'ethan', at: 1 } });
  const guestLeft = call();
  leaveCall(guestLeft, 'david', 2);
  assert.equal(guestLeft.translation.on, true, 'a guest leaving leaves translation on');
  assert.equal(guestLeft.porchGuests[0].state, 'left');
  const ethanLeft = call();
  leaveCall(ethanLeft, 'ethan', 3);
  assert.deepEqual(ethanLeft.translation, { on: false, language: 'zh-Hant', by: 'ethan', at: 3 });
  const momLeft = call();
  leaveCall(momLeft, 'mom', 4);
  assert.equal(momLeft.translation.on, false);
  const bedside = { id: 'mom', role: 'bedside', revoked: false, features: ['translation'] };
  const ethan = { id: 'ethan', role: 'family' };
  const house = { members: [bedside, ethan] };
  const live = { id: 'c', from: 'ethan', to: 'mom', state: 'accepted', left: {} };
  assert.equal(translationOffered(house, live, ethan), true);
  live.left = { mom: 4 };
  assert.equal(translationOffered(house, live, ethan), false);
});

test('when the translator service fails, the call says so and nothing changes', async () => {
  const f=fixture(),{ethan,callID}=await f.connected();
  f.failing.value=true;
  const failed=await f.send('setCallTranslation',{callID,on:true},ethan.credential);
  assert.equal(failed.status,502); assert.match((await failed.json()).error,/couldn't start/);
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.translation,undefined);
});
