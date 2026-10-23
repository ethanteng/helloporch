import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';
import { dialableNumber, phoneGuestLimits } from '../lib/family/phone-guests.ts';

// Fake LiveKit and storage: these tests never dial a real number.
class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', LIVEKIT_SIP_OUTBOUND_TRUNK_ID:'ST_test' };
const bank = '+18005550123';
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });

function liveKit() {
  const rooms = new Map(), dialed = [], removed = [], deleted = [], state = {};
  const missing = () => Object.assign(new Error('not found'), { code:'not_found' });
  const join = (room, identity, attributes={}) => { if (!rooms.has(room)) rooms.set(room,new Map()); rooms.get(room).set(identity,attributes); };
  const leave = (room, identity) => rooms.get(room)?.delete(identity);
  const services = {
    rooms: {
      async getParticipant(room, identity) { const attributes = rooms.get(room)?.get(identity); if (!attributes) throw missing(); return { identity, attributes }; },
      async removeParticipant(room, identity) { removed.push(identity); if (!leave(room,identity)) throw missing(); },
    },
    sip: {
      async createSipParticipant(trunk, number, room, options) {
        dialed.push({ trunk, number, room, options });
        if (state.dialError) throw state.dialError;
        await state.onDial?.();
        join(room, options.participantIdentity, { 'sip.callStatus':'dialing' });
        return {};
      },
    },
  };
  const endRoom = async room => { deleted.push(room); rooms.delete(room); };
  return { rooms, dialed, removed, deleted, state, join, leave, services, endRoom };
}

function fixture() {
  const store = new MemoryStore(), livekit = liveKit();
  let now = 1_800_000_000;
  const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',
    headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(pin?{'X-Porch-Setup-Code':pin}:{})},
    body:JSON.stringify({action,...(['claimInvite','createHousehold'].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')}:{}),...values})}),
    {store,now:()=>now,endRoom:livekit.endRoom,phoneGuestServices:()=>livekit.services});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  // Ethan (a caregiver unless told otherwise) calls Mom's bedside, she answers, and both join the room.
  const connected = async ({ caregiver = true } = {}) => {
    const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
    const invitation = await json('createInvite',{name:'Ethan',permissions:{audio:true,video:true}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
    const family = await json('claimInvite',{code:invitation.code,name:'Ethan'});
    if (caregiver) await json('setCaregiver',{memberID:family.state.me.id,enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
    await json('poll',{available:true},bedside.credential); await json('poll',{available:true},family.credential);
    const callID = (await json('startCall',{targetID:bedside.state.me.id,mode:'video',kind:'call'},family.credential)).state.call.id;
    await json('acceptCall',{callID,available:true},bedside.credential);
    const room = `porch-paired-${callID}`;
    livekit.join(room,bedside.state.me.id); livekit.join(room,family.state.me.id);
    return { bedside, family, callID, room };
  };
  return { store, livekit, send, json, connected, advance:seconds=>now+=seconds, now:()=>now };
}

test('only US and Canadian numbers can be dialed, never premium or Caribbean ones',()=>{
  for (const number of [bank,'+14155550123','+16045550123','+18885550199']) assert.ok(dialableNumber(number),number);
  for (const number of ['+18765550123','+18095550123','+14415550123','+19005550123','+12129765555','+14115550123','+442079460123','+1415555012','14155550123',undefined])
    assert.ok(!dialableNumber(number),String(number));
});

test('a caregiver on an answered call adds a number; the bedside sees its name, never the number',async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  assert.equal(family.state.canAddPhoneGuests,undefined,'not a caregiver yet when paired');
  assert.equal((await f.json('poll',{available:true},family.credential)).state.canAddPhoneGuests,true);
  assert.equal((await f.json('poll',{available:true},bedside.credential)).state.canAddPhoneGuests,undefined);
  const before=(await f.json('poll',{available:true},family.credential)).state.call.expiresAt;
  const added=await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:' Bank '},family.credential);
  assert.deepEqual(added.phoneGuest,{id:added.phoneGuest.id,label:'Bank',addedBy:family.state.me.id,number:bank});
  assert.equal(f.livekit.dialed.length,1);
  const [dial]=f.livekit.dialed;
  assert.equal(dial.trunk,'ST_test'); assert.equal(dial.number,bank); assert.equal(dial.room,room);
  assert.equal(dial.options.participantIdentity,`phone-guest-${added.phoneGuest.id}`);
  assert.equal(dial.options.participantName,'Bank');
  assert.equal(dial.options.hidePhoneNumber,true); assert.equal(dial.options.playDialtone,true); assert.equal(dial.options.waitUntilAnswered,false);
  assert.equal(dial.options.maxCallDuration,phoneGuestLimits.callSeconds);
  assert.equal(added.state.call.phoneGuest.number,bank);
  assert.ok(added.state.call.expiresAt>=f.now()+phoneGuestLimits.callSeconds && added.state.call.expiresAt>before,'a bank hold can outlast the usual call limit');
  const mom=await f.json('poll',{available:true},bedside.credential);
  assert.deepEqual(mom.state.call.phoneGuest,{id:added.phoneGuest.id,label:'Bank',addedBy:family.state.me.id});
  assert.ok(!JSON.stringify(mom).includes(bank.slice(2)),'the bedside never receives the number');
  assert.ok(!JSON.stringify(mom).includes('guests'));
});

test('only family caregivers can add numbers, only on an answered call and with the trunk configured',async()=>{
  const f=fixture(),{bedside,family,callID}=await f.connected({caregiver:false});
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,403);
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},bedside.credential)).status,403);
  const join=await f.json('joinCall',{callID},family.credential);
  assert.equal((await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(join.token)).video.canPublishData,false);

  const g=fixture(),other=await g.connected();
  assert.equal((await g.send('addPhoneGuest',{callID:randomUUID(),phoneNumber:bank,label:'Bank'},other.family.credential)).status,404);
  assert.equal((await g.send('addPhoneGuest',{callID:other.callID,phoneNumber:'+18765550123',label:'Bank'},other.family.credential)).status,400);
  assert.equal((await g.send('addPhoneGuest',{callID:other.callID,phoneNumber:bank,label:''},other.family.credential)).status,400);
  assert.equal((await g.send('addPhoneGuest',{callID:other.callID,phoneNumber:bank,label:'x'.repeat(phoneGuestLimits.label+1)},other.family.credential)).status,400);
  delete process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;
  assert.equal((await g.send('addPhoneGuest',{callID:other.callID,phoneNumber:bank,label:'Bank'},other.family.credential)).status,503);
  assert.equal((await g.json('poll',{available:true},other.family.credential)).state.canAddPhoneGuests,undefined);
  assert.equal(g.livekit.dialed.length+f.livekit.dialed.length,0);
  process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID=env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;

  const h=fixture(),ringing=await h.connected();
  await h.json('endCall',{callID:ringing.callID},ringing.family.credential);
  await h.json('poll',{available:true},ringing.bedside.credential);
  const next=(await h.json('startCall',{targetID:ringing.bedside.state.me.id,mode:'voice',kind:'call'},ringing.family.credential)).state.call.id;
  assert.equal((await h.send('addPhoneGuest',{callID:next,phoneNumber:bank,label:'Bank'},ringing.family.credential)).status,409,'not until the bedside answers');
});

test('nobody is dialed until the bedside and the caregiver are both in the room',async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  f.livekit.leave(room,bedside.state.me.id);
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,409);
  f.livekit.join(room,bedside.state.me.id); f.livekit.leave(room,family.state.me.id);
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,409);
  assert.equal(f.livekit.dialed.length,0);
});

test('one number at a time: hanging up, or the far end hanging up, makes way for the next, up to a limit',async()=>{
  const f=fixture(),{family,bedside,callID,room}=await f.connected();
  const first=(await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).phoneGuest;
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:'+14155550123',label:'Pharmacy'},family.credential)).status,409);
  assert.equal((await f.send('removePhoneGuest',{callID,guestID:first.id},bedside.credential)).status,403,'only whoever added it hangs it up');
  const removed=await f.json('removePhoneGuest',{callID,guestID:first.id},family.credential);
  assert.deepEqual(f.livekit.removed,[`phone-guest-${first.id}`]);
  assert.equal(removed.state.call.phoneGuest,undefined);
  await f.json('removePhoneGuest',{callID,guestID:first.id},family.credential);
  assert.equal(f.livekit.removed.length,1,'hanging up twice is harmless');
  // The bank answers, then hangs up on its own; LiveKit marks the leg before it leaves.
  const second=(await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).phoneGuest;
  f.livekit.join(room,`phone-guest-${second.id}`,{'sip.callStatus':'hangup'});
  const third=(await f.json('addPhoneGuest',{callID,phoneNumber:'+14155550123',label:'Pharmacy'},family.credential)).phoneGuest;
  assert.notEqual(third.id,second.id);
  for (let n=3;n<phoneGuestLimits.perCall;n++) {
    const current=(await f.json('poll',{available:true},family.credential)).state.call.phoneGuest;
    f.livekit.leave(room,`phone-guest-${current.id}`);
    await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential);
  }
  f.livekit.leave(room,`phone-guest-${(await f.json('poll',{available:true},family.credential)).state.call.phoneGuest.id}`);
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,429);
});

test("Mom's hang-up leaves the bank with the caregiver; the caregiver's hang-up ends everything",async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential);
  f.livekit.leave(room,bedside.state.me.id);
  const left=await f.json('endCall',{callID},bedside.credential);
  assert.equal(left.state.call,null); assert.equal(left.state.busy,true);
  assert.deepEqual(f.livekit.deleted,[],'the bank stays on with the caregiver');
  assert.equal((await f.send('joinCall',{callID},bedside.credential)).status,410);
  assert.equal((await f.send('acceptCall',{callID,available:true},bedside.credential)).status,410);
  await f.json('endCall',{callID},bedside.credential);
  assert.deepEqual(f.livekit.deleted,[],'a repeated hang-up from the bedside changes nothing');
  const ethan=await f.json('poll',{available:true},family.credential);
  assert.equal(ethan.state.call.state,'accepted'); assert.equal(ethan.state.call.bedsideLeft,true);
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,409);
  await f.json('endCall',{callID},family.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
  await f.json('poll',{available:true},bedside.credential);
  assert.deepEqual(f.livekit.deleted,[room],'once the room is gone, it is not deleted again');
});

test("Mom's hang-up ends the whole call when the caregiver who added the number is gone",async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential);
  f.livekit.leave(room,family.state.me.id);
  const ended=await f.json('endCall',{callID},bedside.credential);
  assert.equal(ended.state.call.state,'ended');
  assert.deepEqual(f.livekit.deleted,[room]);
});

test("once Mom has left, only the caregiver's phone has to stay online",async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential);
  f.livekit.leave(room,bedside.state.me.id);
  await f.json('endCall',{callID},bedside.credential);
  // Mom's iPad goes offline, while Ethan keeps talking to the bank.
  for (let n=0;n<4;n++) { f.advance(20); assert.equal((await f.json('poll',{available:true},family.credential)).state.call.state,'accepted'); }
  assert.deepEqual(f.livekit.deleted,[]);
  f.advance(36); // Then Ethan's phone stops checking in too.
  await f.json('poll',{available:true},bedside.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
});

test("Mom's hang-up ends the whole call when the phone has already hung up",async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  const guest=(await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).phoneGuest;
  f.livekit.leave(room,`phone-guest-${guest.id}`); // Before Ethan's app reports it.
  const ended=await f.json('endCall',{callID},bedside.credential);
  assert.equal(ended.state.call.state,'ended');
  assert.deepEqual(f.livekit.deleted,[room]);
});

test('without a phone guest, the bedside hanging up still ends the call',async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  await f.json('endCall',{callID},bedside.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
  assert.equal((await f.json('poll',{available:true},family.credential)).state.call.state,'ended');
});

test('a call that expires with a phone guest has its room deleted, retried until it succeeds',async()=>{
  const f=fixture(),{bedside,family,callID,room}=await f.connected();
  await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential);
  const endRoom=f.livekit.endRoom; let failures=1;
  f.livekit.endRoom=async r=>{ if(failures-->0) throw new Error('LiveKit unavailable'); await endRoom(r); };
  f.advance(36); // Ethan's phone stops checking in.
  assert.equal((await f.send('poll',{available:true},bedside.credential)).status,502);
  assert.deepEqual(f.livekit.deleted,[]);
  await f.json('poll',{available:true},bedside.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
  await f.json('poll',{available:true},bedside.credential);
  assert.deepEqual(f.livekit.deleted,[room]);
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,409);
});

test('a refused dial frees the call for another try',async()=>{
  const f=fixture(),{family,callID}=await f.connected();
  f.livekit.state.dialError=Object.assign(new Error('bad number'),{code:'invalid_argument'});
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,502);
  assert.equal((await f.json('poll',{available:true},family.credential)).state.call.phoneGuest,undefined);
  delete f.livekit.state.dialError;
  await f.json('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential);
});

test('a timed-out dial stays tracked, so a leg that arrives late is still hung up',async()=>{
  const f=fixture(),{family,callID,room}=await f.connected();
  f.livekit.state.dialError=Object.assign(new Error('timeout'),{code:'deadline_exceeded'});
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,502);
  assert.equal(f.livekit.removed.length,1,'a leg the timeout may have left is removed right away');
  const tracked=(await f.json('poll',{available:true},family.credential)).state.call.phoneGuest;
  assert.equal(tracked.label,'Bank');
  // The leg shows up after all; ending the call still deletes its room.
  f.livekit.join(room,`phone-guest-${tracked.id}`,{'sip.callStatus':'active'});
  await f.json('endCall',{callID},family.credential);
  assert.deepEqual(f.livekit.deleted,[room]);

  // If it never shows up, another number can be added once the room is checked.
  const g=fixture(),other=await g.connected();
  g.livekit.state.dialError=Object.assign(new Error('timeout'),{code:'deadline_exceeded'});
  assert.equal((await g.send('addPhoneGuest',{callID:other.callID,phoneNumber:bank,label:'Bank'},other.family.credential)).status,502);
  delete g.livekit.state.dialError;
  await g.json('addPhoneGuest',{callID:other.callID,phoneNumber:bank,label:'Bank'},other.family.credential);
});

test('a call that ends while the number is dialing does not keep its telephone leg',async()=>{
  const f=fixture(),{family,callID,room}=await f.connected();
  f.livekit.state.onDial=async()=>{ await f.json('endCall',{callID},family.credential); };
  assert.equal((await f.send('addPhoneGuest',{callID,phoneNumber:bank,label:'Bank'},family.credential)).status,409);
  assert.equal(f.livekit.rooms.has(room),false);
  assert.equal(f.livekit.deleted.at(-1),room);
});

test('rooms make space for one phone guest, and only caregivers can send its keypad tones',async()=>{
  const f=fixture(),{bedside,family,callID}=await f.connected();
  const verify=async credential=>new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify((await f.json('joinCall',{callID},credential)).token);
  const ethan=await verify(family.credential), mom=await verify(bedside.credential);
  assert.equal(ethan.video.canPublishData,true); assert.equal(mom.video.canPublishData,false);
  assert.equal(ethan.roomConfig.maxParticipants,3);
});
