import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';
import { inDoNotDisturb, noteDoNotDisturb } from '../lib/family/do-not-disturb.ts';

// Fake storage, push and LiveKit: these tests never ring a real device.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
class FakeMedia {
  blobs = new Map();
  async uploadTarget(pathname, contentType, _size, validUntil) { return { url: `https://blob.test/put?pathname=${pathname}`, method: 'PUT', headers: { 'x-content-type': contentType }, expiresAt: validUntil }; }
  async downloadURL(pathname, validUntil) { return `https://blob.test/get/${pathname}?until=${validUntil}`; }
  async stat(pathname) { return this.blobs.get(pathname) ?? null; }
  async remove(pathnames) { for (const p of pathnames) this.blobs.delete(p); }
  upload(target) { const pathname = new URL(target.url).searchParams.get('pathname'); this.blobs.set(pathname, { size: 1000, contentType: target.headers['x-content-type'] }); }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret' };
const pin = env.PORCH_CONTACT_SETUP_CODE;
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });

// 1_800_000_000 is 08:00 UTC on a January day: midnight in Los Angeles, 5 PM in Tokyo.
const start = 1_800_000_000, hour = 3600;
async function fixture() {
  const store = new MemoryStore(), media = new FakeMedia(), pushes = [], alerts = [];
  let now = start;
  const send = (action, values={}, credential, code) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',
    headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(code?{'X-Porch-Setup-Code':code}:{})},
    body:JSON.stringify({action,...(['claimInvite','createHousehold'].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')}:{}),...values})}),
    {store,media,now:()=>now,endRoom:async()=>{},
     // Everyone on a call is in its room, as far as a fake LiveKit says.
     phoneGuestServices:()=>({ rooms:{ async getParticipant(_room,identity){ return { identity, attributes:{} }; }, async removeParticipant(){} }, sip:{} }),
     sendPush:async(device,call)=>{ pushes.push({device,call}); return {delivered:true}; },
     sendAlert:async(device,alert)=>{ alerts.push({device,alert}); return {delivered:true}; }});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const bedside = await json('createHousehold',{name:'Mom'},undefined,pin);
  const join = async name => json('claimInvite',{code:(await json('createInvite',{name,permissions:{audio:true,video:true}},bedside.credential,pin)).code});
  const ethan = await join('Ethan'), david = await join('David');
  for (const device of [bedside, ethan, david]) await json('poll',{available:true},device.credential);
  const call = (who, values={}) => send('startCall',{targetID:who.state.me.id,mode:'video',kind:'call',...values},bedside.credential);
  const error = async response => ({ status: response.status, ...(await response.json()) });
  return { store, media, pushes, alerts, send, json, bedside, ethan, david, call, error, advance: s => now += s };
}

test('a family phone on Do Not Disturb turns the bedside\'s call into an offer to leave a message, never a ring',async()=>{
  const f=await fixture();
  await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'sandbox'},f.ethan.credential);
  await f.json('poll',{available:true,doNotDisturb:{on:true}},f.ethan.credential);
  const refused=await f.error(await f.call(f.ethan));
  assert.deepEqual(refused,{status:409,error:"Ethan isn't taking calls right now.",errorCode:'doNotDisturb'});
  assert.equal(f.pushes.length,0,'nothing rings');
  assert.equal((await f.json('poll',{available:true},f.bedside.credential)).state.busy,false,'no call was started');
  // Before whether the app can ring at all: the bedside mustn't take an unreachable phone as its cue to try their regular phone.
  await f.json('poll',{available:false},f.ethan.credential); f.advance(31);
  await f.json('poll',{available:true},f.bedside.credential); await f.json('poll',{available:true},f.david.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  await f.json('registerVoIP',{token:null},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  // Only Ethan: David's phone still rings.
  const david=await f.call(f.david);
  assert.equal(david.status,200);
  await f.json('endCall',{callID:(await david.json()).state.call.id},f.bedside.credential);
  // Ethan's own calls still go out.
  const own=await f.json('startCall',{targetID:f.bedside.state.me.id,mode:'voice',kind:'call'},f.ethan.credential);
  assert.equal(own.state.call.state,'pending');
  await f.json('endCall',{callID:own.state.call.id},f.ethan.credential);
  // Turned off, the bedside's calls ring again.
  await f.json('poll',{available:true,doNotDisturb:{on:false}},f.ethan.credential);
  assert.equal((await f.call(f.ethan)).status,200);
});

test('a check-in that doesn\'t say, or says it wrong, keeps Do Not Disturb as it was; a late one can\'t undo it',async()=>{
  const f=await fixture();
  await f.json('poll',{available:true,doNotDisturb:{on:true}},f.ethan.credential);
  // An app from before Do Not Disturb, or a background check-in, says nothing about it.
  await f.json('poll',{available:true},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  // Malformed values never fail the check-in.
  for (const doNotDisturb of [null,'on',{},{on:'yes'},{on:false,hours:{start:22,end:7}},{on:false,hours:{start:22,end:7},timeZone:'Mars/Olympus'},
    {on:false,hours:{start:24,end:7},timeZone:'America/Los_Angeles'},{on:false,hours:{start:1.5,end:7},timeZone:'America/Los_Angeles'},{on:false,hours:'22-7',timeZone:'America/Los_Angeles'}])
    await f.json('poll',{available:true,doNotDisturb},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb','still on');
  // Check-ins from one launch can arrive out of order. The one sent before turning it on mustn't turn it back off.
  const launch=randomUUID();
  await f.json('poll',{available:true,launch,sequence:2,doNotDisturb:{on:true}},f.ethan.credential);
  await f.json('poll',{available:true,launch,sequence:1,doNotDisturb:{on:false}},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  await f.json('poll',{available:true,launch,sequence:3,doNotDisturb:{on:false}},f.ethan.credential);
  assert.equal((await f.call(f.ethan)).status,200);
  // The bedside's own check-ins never set it.
  const house=JSON.parse(await f.store.get(`house:${f.bedside.state.householdID}`));
  assert.equal(house.members.find(m=>m.role==='bedside').doNotDisturb,undefined);
  assert.equal(house.members.find(m=>m.id===f.ethan.state.me.id).doNotDisturb,undefined,'all off is forgotten');
});

test('Do Not Disturb hours follow the phone\'s own clock, including past midnight',async()=>{
  const f=await fixture();
  // 10 PM until 7 AM in Los Angeles, where it's midnight.
  await f.json('poll',{available:true,doNotDisturb:{on:false,hours:{start:22,end:7},timeZone:'America/Los_Angeles'}},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  f.advance(7*hour);
  await f.json('poll',{available:true},f.ethan.credential); await f.json('poll',{available:true},f.bedside.credential); await f.json('poll',{available:true},f.david.credential);
  const morning=await f.call(f.ethan);
  assert.equal(morning.status,200,'7 AM: it rings');
  await f.json('endCall',{callID:(await morning.json()).state.call.id},f.bedside.credential);
  // Midnight in Tokyo now, though: a phone that has travelled says its new time zone with its next check-in.
  await f.json('poll',{available:true,doNotDisturb:{on:false,hours:{start:22,end:7},timeZone:'Asia/Tokyo'}},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  // The same hours in London, where it's 3 PM.
  await f.json('poll',{available:true,doNotDisturb:{on:false,hours:{start:22,end:7},timeZone:'Europe/London'}},f.ethan.credential);
  const london=await f.call(f.ethan);
  assert.equal(london.status,200);
  await f.json('endCall',{callID:(await london.json()).state.call.id},f.bedside.credential);
  // Daytime hours that don't cross midnight: 9 AM until 5 PM in London.
  await f.json('poll',{available:true,doNotDisturb:{on:false,hours:{start:9,end:17},timeZone:'Europe/London'}},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
  // On now, as well as on a schedule, is on whatever the hour.
  await f.json('poll',{available:true,doNotDisturb:{on:true,hours:{start:1,end:2},timeZone:'Europe/London'}},f.ethan.credential);
  assert.equal((await f.error(await f.call(f.ethan))).errorCode,'doNotDisturb');
});

test('the same hour for start and end is all day, as for the bedside\'s message hours',()=>{
  const member={role:'family'};
  noteDoNotDisturb(member,{on:false,hours:{start:9,end:9},timeZone:'Europe/London'});
  for (let h=0;h<24;h++) assert.equal(inDoNotDisturb(member,start+h*hour),true);
  noteDoNotDisturb(member,{on:false,hours:{start:9,end:10},timeZone:'Europe/London'});
  assert.deepEqual([...Array(24).keys()].filter(h=>inDoNotDisturb(member,start-8*hour+h*hour)),[9],'08:00 UTC is 08:00 in London in January');
  const bedside={role:'bedside'};
  noteDoNotDisturb(bedside,{on:true});
  assert.equal(inDoNotDisturb(bedside,start),false);
});

test('someone on Do Not Disturb can\'t be rung into a call, and caregivers see why Porch calls don\'t reach them',async()=>{
  const f=await fixture();
  await f.json('setCaregiver',{memberID:f.david.state.me.id,enabled:true},f.bedside.credential,pin);
  await f.json('poll',{available:true,doNotDisturb:{on:true}},f.ethan.credential);
  // David calls Mom; Ethan isn't offered to ring in, and asking anyway is refused before anything rings.
  const callID=(await f.json('startCall',{targetID:f.bedside.state.me.id,mode:'video',kind:'call'},f.david.credential)).state.call.id;
  await f.json('acceptCall',{callID,available:true},f.bedside.credential);
  const family=(await f.json('poll',{available:true},f.david.credential)).state.family;
  assert.deepEqual(family.map(m=>[m.name,m.canReceiveCalls]),[['Ethan',false]]);
  const refused=await f.error(await f.send('addPorchGuest',{callID,memberID:f.ethan.state.me.id},f.david.credential));
  assert.deepEqual(refused,{status:409,error:"Ethan isn't taking calls right now.",errorCode:'doNotDisturb'});
  assert.equal(f.pushes.length,0);
  // Turned on while the room is being checked: the update that would ring him looks again.
  await f.json('poll',{available:true,doNotDisturb:{on:false}},f.ethan.credential);
  const late=f.store.compareAndSet.bind(f.store);
  let turnedOn=false;
  f.store.compareAndSet=async(key,before,after)=>{
    if (!turnedOn && JSON.parse(after).call?.porchGuests?.length) {
      turnedOn=true;
      const house=JSON.parse(before); house.members.find(m=>m.id===f.ethan.state.me.id).doNotDisturb={on:true};
      await late(key,before,JSON.stringify(house));
    }
    return late(key,before,after);
  };
  const raced=await f.error(await f.send('addPorchGuest',{callID,memberID:f.ethan.state.me.id},f.david.credential));
  f.store.compareAndSet=late;
  assert.deepEqual([turnedOn,raced.status,raced.errorCode,f.pushes.length],[true,409,'doNotDisturb',0]);
  // The bedside and caregivers see it on Ethan; David, who isn't on it, has nothing to show.
  const people=(await f.json('poll',{available:true},f.bedside.credential)).state.people;
  assert.deepEqual(people.map(p=>[p.name,p.doNotDisturb]),[['Ethan',true],['David',undefined]]);
  const admin=await f.json('verifyPIN',{},f.david.credential,pin);
  assert.deepEqual(admin.admin.people.map(p=>[p.name,p.doNotDisturb]),[['Ethan',true],['David',undefined]]);
  // What the phone said isn't shown to anyone else, only whether it applies now.
  assert.ok(!JSON.stringify(admin).includes('timeZone') && !JSON.stringify(people).includes('hours'));
});

test('the notice of a message left while someone is on Do Not Disturb comes quietly',async()=>{
  const f=await fixture();
  await f.json('registerAlerts',{token:'cd'.repeat(32),environment:'production'},f.ethan.credential);
  const leave=async()=>{
    const created=await f.json('createMessage',{mode:'audio',kind:'voicemail',to:f.ethan.state.me.id,contentType:'audio/mp4',sizeBytes:1000,durationSeconds:5},f.bedside.credential);
    f.media.upload(created.upload);
    await f.json('completeMessage',{messageID:created.message.id},f.bedside.credential);
  };
  await f.json('poll',{available:true,doNotDisturb:{on:true}},f.ethan.credential);
  await leave();
  await f.json('poll',{available:true,doNotDisturb:{on:false}},f.ethan.credential);
  await leave();
  assert.deepEqual(f.alerts.map(a=>a.alert.quiet),[true,undefined]);
});
