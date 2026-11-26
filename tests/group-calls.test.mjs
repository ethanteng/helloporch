import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';

// A bedside key that rings Ethan and David at once. Fake LiveKit, push and storage: nothing rings a real device.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret' };
const pin = env.PORCH_CONTACT_SETUP_CODE;
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });

function fixture() {
  const store = new MemoryStore(), rooms = new Map(), deleted = [], pushes = [], failing = new Set();
  let now = 1_800_000_000;
  const services = { rooms: {
    async getParticipant(room, identity) { if (!rooms.get(room)?.has(identity)) throw Object.assign(new Error('not found'), { code:'not_found' }); return { identity, attributes:{} }; },
    async removeParticipant(room, identity) { rooms.get(room)?.delete(identity); },
  } };
  let duringPush = null;
  const send = (action, values={}, credential, code) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',
    headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(code?{'X-Porch-Setup-Code':code}:{})},
    body:JSON.stringify({action,...(['claimInvite','createHousehold'].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')}:{}),...values})}),
    {store,now:()=>now,endRoom:async room=>{ deleted.push(room); rooms.delete(room); },phoneGuestServices:()=>services,
      sendPush:async (registration,payload)=>{ pushes.push({registration,payload}); if (duringPush) await duringPush(payload); return { delivered: !failing.has(payload.recipientID) }; }});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const member = async (bedside, name) => {
    const invitation = await json('createInvite',{name,permissions:{audio:true,video:true}},bedside.credential,pin);
    return json('claimInvite',{code:invitation.code,name});
  };
  const join = (room, id) => { if (!rooms.has(room)) rooms.set(room,new Set()); rooms.get(room).add(id); };
  // Mom's bedside with Ethan and David on Porch, both phones closed but able to ring by push.
  const family = async ({ open = false } = {}) => {
    const bedside = await json('createHousehold',{name:'Mom'},undefined,pin);
    const ethan = await member(bedside,'Ethan'), david = await member(bedside,'David');
    await json('poll',{available:true},bedside.credential);
    for (const phone of [ethan,david]) {
      await json('registerVoIP',{token:randomBytes(32).toString('hex'),environment:'sandbox'},phone.credential);
      await json('poll',{available:open},phone.credential);
    }
    const ids = { mom: bedside.state.me.id, ethan: ethan.state.me.id, david: david.state.me.id };
    return { bedside, ethan, david, ids };
  };
  const call = (setup, values={}) => json('startCall',{targetIDs:[setup.ids.ethan,setup.ids.david],groupName:'Kids',mode:'video',kind:'call',waitSeconds:45,...values},setup.bedside.credential);
  const view = async credential => (await json('poll',{available:false},credential)).state.call;
  const stored = setup => JSON.parse(store.values.get(`house:${setup.bedside.state.householdID}`));
  return { store, rooms, deleted, pushes, failing, send, json, family, call, view, stored, join, duringPush:fn=>{ duringPush=fn; }, advance:seconds=>now+=seconds, now:()=>now };
}

test('a group key rings both phones at once, each with its own incoming call from Mom',async()=>{
  const f=fixture(),setup=await f.family(),{bedside,ethan,david,ids}=setup;
  const started=(await f.call(setup)).state.call;
  assert.equal(started.to,ids.ethan); assert.equal(started.state,'pending');
  assert.deepEqual(started.porchGuest,{id:started.porchGuest.id,memberID:ids.david,name:'David',state:'ringing'},'the bedside sees David ringing too');
  assert.equal(f.pushes.length,2);
  const [toEthan,toDavid]=['ethan','david'].map(who=>f.pushes.find(p=>p.payload.recipientID===ids[who]).payload);
  assert.deepEqual(toEthan,{callID:started.id,recipientID:ids.ethan,callerName:'Mom',mode:'video',expiresAt:f.now()+75});
  assert.deepEqual(toDavid,{callID:started.porchGuest.id,recipientID:ids.david,callerName:'Mom',mode:'video',expiresAt:f.now()+75});
  const ethanSees=await f.view(ethan.credential), davidSees=await f.view(david.credential);
  assert.equal(ethanSees.id,started.id); assert.equal(ethanSees.state,'pending'); assert.equal(ethanSees.guest,undefined);
  assert.equal(davidSees.id,toDavid.callID); assert.equal(davidSees.state,'pending'); assert.equal(davidSees.guest,true);
  assert.equal(davidSees.from,ids.mom); assert.equal(davidSees.callerName,'Mom');
  assert.equal((await f.send('joinCall',{callID:davidSees.id},david.credential)).status,403,'not before he answers');
  // Caregivers' call history names the key.
  const history=(await f.json('callHistory',{},bedside.credential,pin)).calls;
  assert.equal(history[0].name,'Kids'); assert.equal(history[0].outcome,'ringing');
});

test('Ethan answers first: he talks with Mom while David can still answer and join',async()=>{
  const f=fixture(),setup=await f.family(),{bedside,ethan,david,ids}=setup;
  const started=(await f.call(setup)).state.call, invite=started.porchGuest.id;
  await f.json('acceptCall',{callID:started.id,available:true},ethan.credential);
  assert.equal((await f.view(bedside.credential)).state,'accepted');
  const davidSees=await f.view(david.credential);
  assert.equal(davidSees.id,invite); assert.equal(davidSees.state,'pending','still ringing after Ethan answered');
  await f.json('acceptCall',{callID:invite,available:true},david.credential);
  const join=await f.json('joinCall',{callID:invite},david.credential);
  const token=await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(join.token);
  assert.equal(token.video.room,`porch-paired-${started.id}`); assert.equal(token.sub,ids.david);
  assert.equal((await f.view(ethan.credential)).porchGuest.state,'joined');
  const history=(await f.json('callHistory',{},bedside.credential,pin)).calls;
  assert.equal(history[0].memberID,ids.ethan); assert.equal(history[0].outcome,'ongoing');
});

test('David answers first: he becomes the person called under his own call, and Ethan can still join',async()=>{
  const f=fixture(),setup=await f.family(),{bedside,ethan,david,ids}=setup;
  const started=(await f.call(setup)).state.call, invite=started.porchGuest.id;
  await f.json('poll',{available:false,receivedCallID:started.id},ethan.credential);
  await f.json('acceptCall',{callID:invite,available:true},david.credential);
  const davidSees=await f.view(david.credential);
  assert.equal(davidSees.id,invite,'his phone keeps the call it rang with'); assert.equal(davidSees.state,'accepted');
  assert.equal(davidSees.to,ids.david); assert.equal(davidSees.guest,undefined); assert.equal(davidSees.toCallID,undefined);
  assert.deepEqual(davidSees.porchGuest,{id:started.id,memberID:ids.ethan,name:'Ethan',state:'ringing'});
  const momSees=await f.view(bedside.credential);
  assert.equal(momSees.id,started.id); assert.equal(momSees.state,'accepted'); assert.equal(momSees.to,ids.david);
  // Ethan's phone rang with the call's own ID, and keeps it: now an invitation to join.
  const ethanSees=await f.view(ethan.credential);
  assert.equal(ethanSees.id,started.id); assert.equal(ethanSees.state,'pending'); assert.equal(ethanSees.guest,true); assert.equal(ethanSees.callerName,'Mom');
  assert.equal(f.stored(setup).call.porchGuests[0].receivedAt,f.now(),'his receipt went with him');
  // David's requests use his own ID; the call's is Ethan's.
  const room=`porch-paired-${started.id}`;
  const join=await f.json('joinCall',{callID:invite},david.credential);
  assert.equal((await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(join.token)).video.room,room);
  assert.equal((await f.send('joinCall',{callID:started.id},david.credential)).status,404);
  assert.equal((await f.send('addPorchGuest',{callID:invite,memberID:ids.ethan},david.credential)).status,409,'Ethan is already being rung');
  await f.json('acceptCall',{callID:started.id,available:true},ethan.credential);
  await f.json('joinCall',{callID:started.id},ethan.credential);
  assert.equal((await f.view(ethan.credential)).state,'accepted');
  assert.equal((await f.view(bedside.credential)).porchGuest.state,'joined');
  const history=(await f.json('callHistory',{},bedside.credential,pin)).calls;
  assert.equal(history[0].memberID,ids.david); assert.equal(history[0].name,'Kids');
  // Ethan leaving leaves Mom and David talking; David hanging up with his own ID then ends it.
  f.join(room,ids.mom); f.join(room,ids.ethan); f.join(room,ids.david);
  await f.json('endCall',{callID:started.id,available:true},ethan.credential);
  assert.equal((await f.view(bedside.credential)).state,'accepted');
  f.rooms.get(room).delete(ids.ethan);
  await f.json('endCall',{callID:invite,available:true},david.credential);
  assert.equal(f.stored(setup).call.state,'ended');
});

test('declining leaves the other phone ringing; the call ends once both decline',async()=>{
  const f=fixture(),setup=await f.family(),{bedside,ethan,david,ids}=setup;
  const started=(await f.call(setup)).state.call, invite=started.porchGuest.id;
  await f.json('endCall',{callID:started.id,available:false},ethan.credential);
  assert.equal((await f.view(ethan.credential)).state,'ended','his call is over');
  const davidSees=await f.view(david.credential);
  assert.equal(davidSees.id,invite); assert.equal(davidSees.state,'pending'); assert.equal(davidSees.guest,undefined,'he is the person called now');
  const momSees=await f.view(bedside.credential);
  assert.equal(momSees.state,'pending'); assert.equal(momSees.to,ids.david);
  await f.json('endCall',{callID:invite,available:false},david.credential);
  assert.equal((await f.view(bedside.credential)).state,'ended');
  const history=(await f.json('callHistory',{},bedside.credential,pin)).calls;
  assert.equal(history[0].outcome,'declined');
  // The other order: David declines as a guest, and Ethan still answers.
  const g=fixture(),other=await g.family();
  const second=(await g.call(other)).state.call;
  await g.json('endCall',{callID:second.porchGuest.id,available:false},other.david.credential);
  assert.equal((await g.view(other.david.credential)).state,'ended');
  await g.json('acceptCall',{callID:second.id,available:true},other.ethan.credential);
  assert.equal((await g.view(other.bedside.credential)).state,'accepted');
  assert.equal((await g.view(other.bedside.credential)).porchGuest.state,'declined');
});

test('when no one answers, the bedside ends it as unanswered and both phones stop ringing',async()=>{
  const f=fixture(),setup=await f.family(),{bedside,ethan,david}=setup;
  const started=(await f.call(setup)).state.call;
  f.advance(45);
  await f.json('endCall',{callID:started.id,available:true,unanswered:true},bedside.credential);
  assert.equal((await f.view(ethan.credential)).state,'ended');
  assert.equal((await f.view(david.credential)).state,'ended');
  assert.equal((await f.send('acceptCall',{callID:started.porchGuest.id,available:true},david.credential)).status,410);
  const history=(await f.json('callHistory',{},bedside.credential,pin)).calls;
  assert.equal(history[0].outcome,'missed');
  // A call nobody ends runs out on its own.
  const g=fixture(),other=await g.family();
  const second=(await g.call(other)).state.call;
  g.advance(80);
  assert.equal((await g.view(other.david.credential)).state,'ended');
  assert.equal((await g.send('acceptCall',{callID:second.porchGuest.id,available:true},other.david.credential)).status,410);
});

test('a phone that can\'t be reached is skipped, and the call fails only when neither can ring',async()=>{
  const f=fixture(),setup=await f.family(),{ethan,david,ids}=setup;
  f.failing.add(ids.ethan);
  const started=(await f.call(setup)).state.call;
  assert.equal(started.to,ids.david,'David is the person called');
  assert.equal(started.porchGuest.state,'missed');
  const davidSees=await f.view(david.credential);
  assert.equal(davidSees.id,f.pushes.find(p=>p.payload.recipientID===ids.david).payload.callID); assert.equal(davidSees.state,'pending');
  assert.equal((await f.view(ethan.credential)).state,'ended');
  await f.json('acceptCall',{callID:davidSees.id,available:true},david.credential);
  // David's phone can't be reached: Ethan rings alone, as the person called.
  const g=fixture(),other=await g.family();
  g.failing.add(other.ids.david);
  const second=(await g.call(other)).state.call;
  assert.equal(second.to,other.ids.ethan); assert.equal(second.porchGuest.state,'missed');
  // Neither: the bedside hears that neither app could ring, and can leave a message.
  const h=fixture(),both=await h.family();
  h.failing.add(both.ids.ethan); h.failing.add(both.ids.david);
  const failed=await h.send('startCall',{targetIDs:[both.ids.ethan,both.ids.david],mode:'video',kind:'call'},both.bedside.credential);
  assert.equal(failed.status,409);
  assert.deepEqual(await failed.json().then(body=>[body.errorCode,body.error]),['offline',"Couldn't reach their Porch apps."]);
  assert.equal(h.stored(both).call.state,'ended');
});

test('only someone who can ring is rung; one left in the group gets an ordinary call',async()=>{
  const f=fixture(),setup=await f.family(),{bedside,ids}=setup;
  // David turned off his phone's calls: no push token and Porch closed.
  const stored=f.stored(setup); delete stored.members.find(m=>m.id===ids.david).voip;
  f.store.values.set(`house:${setup.bedside.state.householdID}`,JSON.stringify(stored));
  const started=(await f.call(setup)).state.call;
  assert.equal(started.to,ids.ethan); assert.equal(started.porchGuest,undefined);
  assert.equal(f.pushes.length,1);
  // A person removed from the family drops out of the group.
  const g=fixture(),other=await g.family();
  await g.json('revoke',{memberID:other.ids.ethan},other.bedside.credential,pin);
  const second=(await g.call(other)).state.call;
  assert.equal(second.to,other.ids.david); assert.equal(second.porchGuest,undefined);
});

test('only the bedside calls a group, of at most two people on Porch',async()=>{
  const f=fixture(),setup=await f.family({ open:true }),{bedside,ethan,ids}=setup;
  assert.equal((await f.send('startCall',{targetIDs:[ids.mom,ids.david],mode:'video',kind:'call'},ethan.credential)).status,403);
  assert.equal((await f.send('startCall',{targetIDs:[ids.ethan,ids.david],mode:'voice',kind:'dropIn'},bedside.credential)).status,403);
  assert.equal((await f.send('startCall',{targetIDs:[ids.ethan,ids.david,randomUUID()],mode:'video',kind:'call'},bedside.credential)).status,400);
  assert.equal((await f.send('startCall',{targetIDs:[],mode:'video',kind:'call'},bedside.credential)).status,400);
  assert.equal((await f.send('startCall',{targetIDs:[randomUUID()],mode:'video',kind:'call'},bedside.credential)).status,403);
  // Repeats count once, and the name falls back to the people's names.
  const started=(await f.json('startCall',{targetIDs:[ids.ethan,ids.ethan],mode:'video',kind:'call'},bedside.credential)).state.call;
  assert.equal(started.porchGuest,undefined);
  await f.json('endCall',{callID:started.id,available:true},bedside.credential);
  await f.json('startCall',{targetIDs:[ids.ethan,ids.david],mode:'video',kind:'call'},bedside.credential);
  const history=(await f.json('callHistory',{},bedside.credential,pin)).calls;
  assert.equal(history[0].name,'Ethan and David');
});

test('someone on Do Not Disturb isn\'t rung: the other is, and with both on it the bedside offers a message',async()=>{
  const f=fixture(),setup=await f.family(),{ethan,david,ids}=setup;
  await f.json('poll',{available:false,doNotDisturb:{on:true}},ethan.credential);
  const started=(await f.call(setup)).state.call;
  assert.equal(started.to,ids.david); assert.equal(started.porchGuest,undefined);
  assert.deepEqual(f.pushes.map(p=>p.payload.recipientID),[ids.david]);
  await f.json('endCall',{callID:started.id,available:true},setup.bedside.credential);
  await f.json('poll',{available:false,doNotDisturb:{on:true}},david.credential);
  const both=await f.send('startCall',{targetIDs:[ids.ethan,ids.david],mode:'video',kind:'call'},setup.bedside.credential);
  assert.equal(both.status,409);
  assert.deepEqual(await both.json().then(body=>[body.errorCode,body.error]),['doNotDisturb',"Ethan and David aren't taking calls right now."]);
});

test('a push that fails after the other person has answered stops ringing that phone',async()=>{
  const f=fixture(),setup=await f.family(),{ethan,ids}=setup;
  // David can't be reached, and Ethan answers while that push is still being reported.
  f.failing.add(ids.david);
  f.duringPush(async payload=>{
    if (payload.recipientID!==ids.ethan) return;
    const callID=f.pushes.find(p=>p.payload.recipientID===ids.ethan).payload.callID;
    await f.json('acceptCall',{callID,available:true},ethan.credential);
  });
  const started=(await f.call(setup)).state.call;
  assert.equal(started.state,'accepted'); assert.equal(started.to,ids.ethan);
  assert.equal(started.porchGuest.state,'missed','David is not left ringing after his push failed');
  assert.equal((await f.view(setup.david.credential)).state,'ended');
});
