import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';
import { porchGuestLimits } from '../lib/family/porch-guests.ts';

// Fake LiveKit, push and storage: these tests never ring a real device or dial a number.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', LIVEKIT_SIP_OUTBOUND_TRUNK_ID:'ST_test' };
const pin = env.PORCH_CONTACT_SETUP_CODE, bank = '+18005550123';
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });

function liveKit() {
  const rooms = new Map(), removed = [], deleted = [], hooks = {};
  const missing = () => Object.assign(new Error('not found'), { code:'not_found' });
  const join = (room, identity, attributes={}) => { if (!rooms.has(room)) rooms.set(room,new Map()); rooms.get(room).set(identity,attributes); };
  const leave = (room, identity) => rooms.get(room)?.delete(identity);
  const services = {
    rooms: {
      async getParticipant(room, identity) {
        await hooks.beforeGet?.();
        const attributes = rooms.get(room)?.get(identity); if (!attributes) throw missing(); return { identity, attributes };
      },
      async removeParticipant(room, identity) { removed.push(identity); if (!leave(room,identity)) throw missing(); },
    },
    sip: { async createSipParticipant(_trunk, _number, room, options) { join(room, options.participantIdentity, { 'sip.callStatus':'active' }); return {}; } },
  };
  return { rooms, removed, deleted, hooks, join, leave, services, endRoom: async room => { deleted.push(room); rooms.delete(room); } };
}

function fixture() {
  const store = new MemoryStore(), livekit = liveKit(), pushes = [], push = { result: { delivered: true } };
  let now = 1_800_000_000;
  const send = (action, values={}, credential, code) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',
    headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(code?{'X-Porch-Setup-Code':code}:{})},
    body:JSON.stringify({action,...(['claimInvite','createHousehold'].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')}:{}),...values})}),
    {store,now:()=>now,endRoom:livekit.endRoom,phoneGuestServices:()=>livekit.services,sendPush:async (registration,payload)=>{ pushes.push({registration,payload}); return push.result; }});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const member = async (bedside, name) => {
    const invitation = await json('createInvite',{name,permissions:{audio:true,video:true}},bedside.credential,pin);
    return json('claimInvite',{code:invitation.code,name});
  };
  // Ethan (a caregiver) calls Mom's bedside and both join the room. David is family too and has Porch open.
  const connected = async ({ davidOpen = true } = {}) => {
    const bedside = await json('createHousehold',{name:'Mom'},undefined,pin);
    const ethan = await member(bedside,'Ethan'), david = await member(bedside,'David');
    await json('setCaregiver',{memberID:ethan.state.me.id,enabled:true},bedside.credential,pin);
    await json('poll',{available:true},bedside.credential); await json('poll',{available:true},ethan.credential);
    if (davidOpen) await json('poll',{available:true},david.credential);
    const callID = (await json('startCall',{targetID:bedside.state.me.id,mode:'video',kind:'call'},ethan.credential)).state.call.id;
    await json('acceptCall',{callID,available:true},bedside.credential);
    const room = `porch-paired-${callID}`;
    livekit.join(room,bedside.state.me.id); livekit.join(room,ethan.state.me.id);
    return { bedside, ethan, david, callID, room, ids: { mom: bedside.state.me.id, ethan: ethan.state.me.id, david: david.state.me.id } };
  };
  // David answers his invitation and joins the room.
  const answer = async (setup, inviteID) => {
    await json('acceptCall',{callID:inviteID,available:true},setup.david.credential);
    await json('joinCall',{callID:inviteID},setup.david.credential);
    livekit.join(setup.room,setup.ids.david);
  };
  const keepAlive = async (...credentials) => { for (const credential of credentials) await json('poll',{available:true},credential); };
  // Time passes while these devices keep checking in, as open apps do every few seconds.
  const pass = async (seconds, ...credentials) => {
    for (let left=seconds; left>0; left-=10) { now+=Math.min(10,left); await keepAlive(...credentials); }
  };
  return { store, livekit, pushes, push, send, json, connected, answer, keepAlive, pass, advance:seconds=>now+=seconds, now:()=>now };
}

test('family phones list the rest of the family to ring in; the bedside and the guest list stay apart',async()=>{
  const f=fixture(),{bedside,ethan,david,ids}=await f.connected();
  const listed=(await f.json('poll',{available:true},ethan.credential)).state.family;
  assert.deepEqual(listed,[{id:ids.david,name:'David',canReceiveCalls:true}]);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.family,undefined);
  assert.deepEqual((await f.json('poll',{available:true},david.credential)).state.family.map(p=>p.name),['Ethan']);
  assert.ok(!JSON.stringify(listed).includes('voip') && !JSON.stringify(listed).includes('permissions'));
});

test('ringing David in: his phone gets its own incoming call, and answering joins the same room with video',async()=>{
  const f=fixture(),{bedside,ethan,david,callID,room,ids}=await f.connected();
  await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'sandbox'},david.credential);
  const added=await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential);
  const invite=added.porchGuest;
  assert.deepEqual(invite,{id:invite.id,memberID:ids.david,name:'David',state:'ringing'});
  assert.notEqual(invite.id,callID,'the invitation is a call of its own on his phone');
  assert.equal(f.pushes.length,1);
  assert.deepEqual(f.pushes[0].payload,{callID:invite.id,recipientID:ids.david,callerName:'Ethan with Mom',mode:'video',expiresAt:f.now()+porchGuestLimits.ringSeconds});
  const ringing=(await f.json('poll',{available:true},david.credential)).state;
  assert.equal(ringing.call.id,invite.id); assert.equal(ringing.call.to,ids.david); assert.equal(ringing.call.from,ids.ethan);
  assert.equal(ringing.call.state,'pending'); assert.equal(ringing.call.kind,'call'); assert.equal(ringing.call.guest,true);
  assert.equal(ringing.call.callerName,'Ethan with Mom'); assert.equal(ringing.busy,true);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call.porchGuest.state,'ringing');
  assert.equal((await f.send('joinCall',{callID:invite.id},david.credential)).status,403,'not before he answers');
  await f.json('acceptCall',{callID:invite.id,available:true},david.credential);
  const join=await f.json('joinCall',{callID:invite.id},david.credential);
  const token=await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(join.token);
  assert.equal(token.video.room,room); assert.equal(token.sub,ids.david);
  assert.deepEqual(token.video.canPublishSources,['microphone','camera']);
  assert.equal(token.video.canPublishData,false); assert.equal(token.roomConfig.maxParticipants,4);
  assert.equal((await f.json('poll',{available:true},david.credential)).state.call.state,'accepted');
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.porchGuest.state,'joined');
  assert.equal((await f.send('acceptCall',{callID:invite.id,available:true},david.credential)).status,409);
  // His ringing call's receipt is recorded like any other.
  const g=fixture(),other=await g.connected();
  const second=(await g.json('addPorchGuest',{callID:other.callID,memberID:other.ids.david},other.ethan.credential)).porchGuest;
  await g.json('poll',{available:false,receivedCallID:second.id},other.david.credential);
  const stored=JSON.parse(g.store.values.get(`house:${other.bedside.state.householdID}`));
  assert.equal(stored.call.porchGuests[0].receivedAt,g.now());
});

test('only family on an answered call with the bedside can ring someone in, one at a time',async()=>{
  const f=fixture(),{bedside,ethan,david,callID,room,ids}=await f.connected();
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.david},bedside.credential)).status,403);
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.ethan},ethan.credential)).status,404,'not someone already on the call');
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.mom},ethan.credential)).status,404);
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.ethan},david.credential)).status,404,'not from outside the call');
  f.livekit.leave(room,ids.mom);
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).status,409,'not until both are connected');
  assert.equal(f.pushes.length,0);
  f.livekit.join(room,ids.mom);
  const first=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).status,409,'one at a time');
  // He declines; Ethan can try again, and the new invitation rings as a new call.
  await f.json('endCall',{callID:first.id},david.credential);
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.porchGuest.state,'declined');
  assert.equal((await f.json('poll',{available:true},david.credential)).state.call.state,'ended');
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call.state,'accepted','declining leaves the call alone');
  const second=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  assert.notEqual(second.id,first.id);
  // Pending calls can't ring anyone in.
  const g=fixture(),pending=await g.connected();
  await g.json('endCall',{callID:pending.callID},pending.ethan.credential);
  await g.json('poll',{available:true},pending.bedside.credential);
  const next=(await g.json('startCall',{targetID:pending.ids.mom,mode:'video',kind:'call'},pending.ethan.credential)).state.call.id;
  assert.equal((await g.send('addPorchGuest',{callID:next,memberID:pending.ids.david},pending.ethan.credential)).status,409);
});

test("someone whose Porch can't ring isn't added, and a failed push marks the invitation missed",async()=>{
  const f=fixture(),{ethan,callID,ids}=await f.connected({davidOpen:false});
  const offline=await f.send('addPorchGuest',{callID,memberID:ids.david},ethan.credential);
  assert.equal(offline.status,409); assert.equal((await offline.json()).errorCode,'offline');
  const g=fixture(),other=await g.connected({davidOpen:false});
  await g.json('registerVoIP',{token:'cd'.repeat(32),environment:'sandbox'},other.david.credential);
  g.push.result={delivered:false};
  const failed=await g.send('addPorchGuest',{callID:other.callID,memberID:other.ids.david},other.ethan.credential);
  assert.equal(failed.status,409); assert.equal((await failed.json()).errorCode,'offline');
  assert.equal((await g.json('poll',{available:true},other.ethan.credential)).state.call.porchGuest.state,'missed');
  // A push that APNs accepted rings even while his app is closed.
  g.push.result={delivered:true};
  assert.equal((await g.json('addPorchGuest',{callID:other.callID,memberID:other.ids.david},other.ethan.credential)).porchGuest.state,'ringing');
});

test('an unanswered invitation stops ringing after the standard ring time',async()=>{
  const f=fixture(),{bedside,ethan,david,callID,ids}=await f.connected();
  const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  await f.pass(porchGuestLimits.ringSeconds,bedside.credential,ethan.credential);
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.porchGuest.state,'missed');
  assert.equal((await f.send('acceptCall',{callID:invite.id,available:true},david.credential)).status,410);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call.state,'accepted');
});

test('the call goes on while two people remain: Ethan can leave Mom and David talking',async()=>{
  const f=fixture(),{bedside,ethan,david,callID,room,ids}=await f.connected();
  const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  await f.answer({david,room,ids},invite.id);
  f.livekit.leave(room,ids.ethan);
  const left=await f.json('endCall',{callID},ethan.credential);
  assert.equal(left.state.call,null); assert.equal(left.state.busy,true);
  assert.deepEqual(f.livekit.deleted,[]);
  assert.equal((await f.send('joinCall',{callID},ethan.credential)).status,410,"he can't rejoin");
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call.state,'accepted');
  assert.equal((await f.json('poll',{available:true},david.credential)).state.call.state,'accepted');
  // Ethan's phone stops checking in; that no longer matters.
  await f.pass(40,bedside.credential,david.credential);
  assert.equal((await f.json('poll',{available:true},david.credential)).state.call.state,'accepted');
  // Then David hangs up, leaving only Mom: the call ends.
  f.livekit.leave(room,ids.david);
  await f.json('endCall',{callID:invite.id},david.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call.state,'ended');
});

test("Mom's hang-up leaves Ethan and David talking, and David's leaves Mom and Ethan",async()=>{
  const f=fixture(),{bedside,ethan,david,callID,room,ids}=await f.connected();
  const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  await f.answer({david,room,ids},invite.id);
  f.livekit.leave(room,ids.david);
  await f.json('endCall',{callID:invite.id},david.credential);
  assert.equal((await f.json('poll',{available:true},david.credential)).state.call.state,'ended');
  const ethanView=(await f.json('poll',{available:true},ethan.credential)).state.call;
  assert.equal(ethanView.state,'accepted'); assert.equal(ethanView.porchGuest.state,'left');
  assert.deepEqual(f.livekit.deleted,[]);

  const g=fixture(),other=await g.connected();
  const second=(await g.json('addPorchGuest',{callID:other.callID,memberID:other.ids.david},other.ethan.credential)).porchGuest;
  await g.answer({david:other.david,room:other.room,ids:other.ids},second.id);
  g.livekit.leave(other.room,other.ids.mom);
  const mom=await g.json('endCall',{callID:other.callID},other.bedside.credential);
  assert.equal(mom.state.call,null);
  assert.equal((await g.send('joinCall',{callID:other.callID},other.bedside.credential)).status,410);
  assert.equal((await g.json('poll',{available:true},other.ethan.credential)).state.call.bedsideLeft,true);
  assert.deepEqual(g.livekit.deleted,[]);
  assert.equal((await g.send('addPorchGuest',{callID:other.callID,memberID:other.ids.david},other.ethan.credential)).status,409,'nobody new joins without Mom');
});

test('hanging up ends the call for everyone when the person who would remain is already gone',async()=>{
  const f=fixture(),{ethan,david,callID,room,ids}=await f.connected();
  const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  await f.answer({david,room,ids},invite.id);
  f.livekit.leave(room,ids.david); // His app crashed before telling Porch.
  f.livekit.leave(room,ids.ethan);
  await f.json('endCall',{callID},ethan.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
});

test("a phone Ethan added hangs up when he leaves, while Mom and David keep talking",async()=>{
  const f=fixture(),{bedside,ethan,david,callID,room,ids}=await f.connected();
  const phone=(await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},ethan.credential)).phoneGuest;
  const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  await f.answer({david,room,ids},invite.id);
  f.livekit.leave(room,ids.ethan);
  await f.json('endCall',{callID},ethan.credential);
  assert.ok(f.livekit.removed.includes(`phone-guest-${phone.id}`),'the bank is hung up');
  assert.equal(f.livekit.rooms.get(room)?.has(`phone-guest-${phone.id}`),false);
  const mom=(await f.json('poll',{available:true},bedside.credential)).state.call;
  assert.equal(mom.state,'accepted'); assert.equal(mom.phoneGuest,undefined);
  assert.deepEqual(f.livekit.deleted,[]);
});

test('a guest whose phone stops checking in drops off, and revoking him takes only him off the call',async()=>{
  const f=fixture(),{bedside,ethan,david,callID,room,ids}=await f.connected();
  const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
  await f.answer({david,room,ids},invite.id);
  await f.pass(40,bedside.credential,ethan.credential);
  const view=(await f.json('poll',{available:true},ethan.credential)).state.call;
  assert.equal(view.state,'accepted'); assert.equal(view.porchGuest.state,'left');
  assert.equal((await f.send('joinCall',{callID:invite.id},david.credential)).status,410);

  const g=fixture(),other=await g.connected();
  const second=(await g.json('addPorchGuest',{callID:other.callID,memberID:other.ids.david},other.ethan.credential)).porchGuest;
  await g.answer({david:other.david,room:other.room,ids:other.ids},second.id);
  await g.json('revoke',{memberID:other.ids.david},other.bedside.credential,pin);
  assert.deepEqual(g.livekit.deleted,[],'Mom and Ethan keep talking');
  assert.ok(g.livekit.removed.includes(other.ids.david)); assert.equal(g.livekit.rooms.get(other.room)?.has(other.ids.david),false);
  const ethanView=(await g.json('poll',{available:true},other.ethan.credential)).state.call;
  assert.equal(ethanView.state,'accepted'); assert.equal(ethanView.porchGuest.state,'left');

  // If he was the only one left with Mom, losing access ends the call.
  const h=fixture(),alone=await h.connected();
  const third=(await h.json('addPorchGuest',{callID:alone.callID,memberID:alone.ids.david},alone.ethan.credential)).porchGuest;
  await h.answer({david:alone.david,room:alone.room,ids:alone.ids},third.id);
  h.livekit.leave(alone.room,alone.ids.ethan);
  await h.json('endCall',{callID:alone.callID},alone.ethan.credential);
  await h.json('revoke',{memberID:alone.ids.david},alone.bedside.credential,pin);
  assert.deepEqual(h.livekit.deleted,[alone.room]);
});

test('revoking someone whose invitation is still ringing cancels it and leaves the call alone',async()=>{
  const f=fixture(),{bedside,ethan,callID,ids}=await f.connected();
  await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential);
  await f.json('revoke',{memberID:ids.david},bedside.credential,pin);
  assert.deepEqual(f.livekit.deleted,[]); assert.deepEqual(f.livekit.removed,[]);
  const view=(await f.json('poll',{available:true},ethan.credential)).state.call;
  assert.equal(view.state,'accepted'); assert.equal(view.porchGuest.state,'cancelled');
  assert.deepEqual((await f.json('poll',{available:true},ethan.credential)).state.family,[]);
});

test('someone who loses access while the room is checked is not rung',async()=>{
  const f=fixture(),{bedside,ethan,david,callID,ids}=await f.connected();
  await f.json('registerVoIP',{token:'ef'.repeat(32),environment:'sandbox'},david.credential);
  let revoked=false;
  f.livekit.hooks.beforeGet=async()=>{ if (!revoked) { revoked=true; await f.json('revoke',{memberID:ids.david},bedside.credential,pin); } };
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).status,404);
  assert.equal(f.pushes.length,0);
  assert.equal((await f.json('poll',{available:true},ethan.credential)).state.call.porchGuest,undefined);
});

test('a call can ring in a limited number of people',async()=>{
  const f=fixture(),{ethan,david,callID,ids}=await f.connected();
  for (let n=0;n<porchGuestLimits.perCall;n++) {
    const invite=(await f.json('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).porchGuest;
    await f.json('endCall',{callID:invite.id},david.credential);
  }
  assert.equal((await f.send('addPorchGuest',{callID,memberID:ids.david},ethan.credential)).status,429);
});
