import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { TokenVerifier } from 'livekit-server-sdk';
import { handleFamily } from '../lib/family/service.ts';

class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', PORCH_CALL_ACCESS_CODE:'private-test-calling-code' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });
function fixture(dependencies = {}) {
 const store = new MemoryStore(), ended=[];
 let now=1_800_000_000;
 const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`} : {}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")} : {}),...values})}),{store,now:()=>now,endRoom:async room=>ended.push(room),...dependencies});
 const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
 const setup = async (permissions={audio:true,video:true}) => {
  const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
  const invitation = await json('createInvite',{name:'Ethan',permissions},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
  const family = await json('claimInvite',{code:invitation.code,name:'Untrusted caller name'});
  await json('poll',{available:true},bedside.credential); await json('poll',{available:true},family.credential);
  return { bedside, family, invitation };
 };
 return {store,ended,send,json,setup,advance:seconds=>now+=seconds};
}
test('household bootstrap needs caregiver authority and never returns secrets in state',async()=>{
 const f=fixture();
 assert.equal((await f.send('createHousehold',{name:'Mom'})).status,403);
 const owner=await f.json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal(owner.role,'bedside'); assert.ok(owner.credential.includes('.'));
 assert.ok(!JSON.stringify(owner.state).includes('secretHash'));
 assert.ok(!JSON.stringify(owner).includes(env.PORCH_CONTACT_SETUP_CODE));
 assert.equal((await f.send('poll',{available:true},env.PORCH_CALL_ACCESS_CODE)).status,401);
});
test('invitations are single use, caller names come from caregiver, family cannot elevate access',async()=>{
 const f=fixture(),{bedside,family,invitation}=await f.setup({audio:false,video:false});
 assert.equal(family.state.me.name,'Ethan');
 assert.equal((await f.send('claimInvite',{code:invitation.code,name:'Other'})).status,410);
 assert.equal((await f.send('createInvite',{name:'Other',permissions:{audio:true,video:true}},family.credential,env.PORCH_CONTACT_SETUP_CODE)).status,403);
 assert.equal((await f.send('setDropIn',{enabled:true},family.credential,env.PORCH_CONTACT_SETUP_CODE)).status,403);
 assert.equal((await f.send('createInvite',{name:'Other',permissions:{audio:true,video:true}},bedside.credential)).status,403);
});
test('invitations last a day',async()=>{
 const f=fixture(); const bedside=await f.json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const invite=await f.json('createInvite',{name:'Ethan',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal(invite.expiresAt-invite.state.serverTime,86400);
 f.advance(86399); await f.json('claimInvite',{code:invite.code,name:'Ethan'});
});
test('expired and cancelled invitations cannot pair',async()=>{
 const f=fixture(); const bedside=await f.json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const invite=await f.json('createInvite',{name:'Ethan',permissions:{audio:true,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 f.advance(86401); assert.equal((await f.send('claimInvite',{code:invite.code})).status,410);
 const next=await f.json('createInvite',{name:'Ethan',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 await f.json('cancelInvites',{},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('claimInvite',{code:next.code})).status,410);
});
test('caregivers see pending invitations by name and can cancel one without the others',async()=>{
 const f=fixture(),{bedside,family}=await f.setup({audio:false,video:false});
 await f.json('setCaregiver',{memberID:family.state.me.id,enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const first=await f.json('createInvite',{name:'Ana',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const second=await f.json('createInvite',{name:'Ben',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const admin=await f.json('verifyPIN',{},family.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.deepEqual(admin.admin.invitations.map(i=>i.name),['Ana','Ben']);
 assert.ok(!JSON.stringify(admin.admin.invitations).includes(first.code));
 assert.equal((await f.send('cancelInvite',{inviteID:first.invitationID},family.credential)).status,403,'cancelling needs the PIN');
 const cancelled=await f.json('cancelInvite',{inviteID:first.invitationID},family.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.deepEqual(cancelled.admin.invitations.map(i=>i.id),[second.invitationID]);
 assert.equal((await f.send('claimInvite',{code:first.code})).status,410);
 await f.json('cancelInvite',{inviteID:first.invitationID},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('cancelInvite',{},bedside.credential,env.PORCH_CONTACT_SETUP_CODE)).status,400);
 f.advance(86401);
 assert.deepEqual((await f.json('poll',{available:true},bedside.credential)).state.invitations,[]);
});
test('drop-in is opt-in by mode and requires a bedside device that is ready',async()=>{
 const f=fixture(),{bedside,family}=await f.setup({audio:true,video:false});
 const start=(mode='voice')=>f.send('startCall',{targetID:bedside.state.me.id,mode,kind:'dropIn'},family.credential);
 assert.equal((await start()).status,403);
 await f.json('setDropIn',{enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await start('video')).status,403);
 await f.json('poll',{available:false},bedside.credential);
 assert.equal((await start()).status,409);
 await f.json('poll',{available:true},bedside.credential); f.advance(31);
 assert.equal((await start()).status,409);
});
test('a caregiver can have a family member\'s ordinary calls drop in, for the drop-in types they\'re approved for',async()=>{
 const pushes=[],f=fixture({sendPush:async(device,call)=>{pushes.push(call);return {delivered:true};}}),{bedside,family}=await f.setup({audio:true,video:false});
 const memberID=family.state.me.id,pin=env.PORCH_CONTACT_SETUP_CODE;
 assert.equal(family.state.me.autoDropIn,false);
 assert.equal((await f.send('setAutoDropIn',{memberID,enabled:true},bedside.credential)).status,403,'needs the PIN');
 assert.equal((await f.send('setAutoDropIn',{memberID,enabled:true},family.credential,pin)).status,403,'family devices need caregiver approval');
 assert.equal((await f.send('setAutoDropIn',{memberID,enabled:'yes'},bedside.credential,pin)).status,400);
 assert.equal((await f.json('setAutoDropIn',{memberID,enabled:true},bedside.credential,pin)).admin.people[0].autoDropIn,true);
 assert.equal((await f.json('poll',{available:true},family.credential)).state.me.autoDropIn,true);
 const call=async(mode,from=family,targetID=bedside.state.me.id)=>{
  const created=await f.json('startCall',{targetID,mode,kind:'call'},from.credential);
  await f.json('endCall',{callID:created.state.call.id},from.credential);
  return created.state.call;
 };
 // Drop-ins paused for everyone: it rings.
 assert.equal((await call('voice')).kind,'call');
 await f.json('setDropIn',{enabled:true},bedside.credential,pin);
 await f.json('setRingSeconds',{seconds:15},bedside.credential,pin);
 const dropIn=await call('voice');
 assert.equal(dropIn.kind,'dropIn'); assert.equal(dropIn.expiresAt-dropIn.createdAt,75,'drop-ins keep their standard time');
 // Not approved for video drop-in, so a video call rings.
 assert.equal((await call('video')).kind,'call');
 // The bedside's own calls never drop in.
 assert.equal((await call('voice',bedside,memberID)).kind,'call');
 assert.equal(pushes.length,0);
 // A closed bedside Porch can't take a drop-in, so the call rings it by push instead.
 await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},bedside.credential);
 await f.json('poll',{available:false},bedside.credential);
 assert.equal((await call('voice')).kind,'call'); assert.equal(pushes.length,1);
 await f.json('poll',{available:true},bedside.credential);
 // A converted drop-in is held to its approval like any other.
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'call'},family.credential);
 assert.equal(created.state.call.kind,'dropIn'); assert.equal(pushes.length,1);
 await f.json('setPermissions',{memberID,permissions:{audio:false,video:false}},bedside.credential,pin);
 assert.equal((await f.json('poll',{available:true},family.credential)).state.call.reason,'Drop-in access was changed.');
 await f.json('setPermissions',{memberID,permissions:{audio:true,video:false}},bedside.credential,pin);
 assert.equal((await f.json('setAutoDropIn',{memberID,enabled:false},bedside.credential,pin)).admin.people[0].autoDropIn,false);
 assert.equal((await call('voice')).kind,'call');
});
test('announcement precedes automatic answer; voice tokens cannot publish a camera',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 await f.json('setDropIn',{enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'dropIn'},family.credential);
 const callID=created.state.call.id;
 assert.equal((await f.send('joinCall',{callID},bedside.credential)).status,403);
 f.advance(8); await f.json('poll',{available:true},bedside.credential);
 assert.equal((await f.send('acceptCall',{callID,available:true},bedside.credential)).status,409);
 f.advance(5); await f.json('acceptCall',{callID,available:true},bedside.credential);
 const join=await f.json('joinCall',{callID},bedside.credential);
 const token=await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(join.token);
 assert.equal(token.video.room,`porch-paired-${callID}`); assert.deepEqual(token.video.canPublishSources,['microphone']);
 assert.equal(token.video.canUpdateOwnMetadata,false);
 assert.ok(token.exp-token.nbf<=60);
});
test('ordinary calls work in both directions and only the recipient can answer',async()=>{
 for(const mode of ['voice','video']) {
  const f=fixture(),{bedside,family}=await f.setup();
  const created=await f.json('startCall',{targetID:family.state.me.id,mode,kind:'call'},bedside.credential);
  const callID=created.state.call.id;
  assert.equal((await f.send('acceptCall',{callID,available:true},bedside.credential)).status,409);
  await f.json('acceptCall',{callID,available:true},family.credential);
  const join=await f.json('joinCall',{callID},family.credential);
  const token=await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(join.token);
  assert.deepEqual(token.video.canPublishSources,mode==='voice'?['microphone']:['microphone','camera']);
 }
});
test('simultaneous callers cannot reserve two calls and cancellation prevents late joins',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 const requests=await Promise.all([f.send('startCall',{targetID:bedside.state.me.id,mode:'video',kind:'call'},family.credential),f.send('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'call'},family.credential)]);
 assert.deepEqual(requests.map(r=>r.status).sort(),[200,409]);
 const callID=(await requests.find(r=>r.status===200).json()).state.call.id;
 await f.json('endCall',{callID},family.credential);
 assert.equal((await f.send('joinCall',{callID},bedside.credential)).status,410);
 assert.equal(f.ended.length,1);
});
test('permissions revoked during a drop-in end its room and block further joins',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 await f.json('setDropIn',{enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'video',kind:'dropIn'},family.credential);
 const callID=created.state.call.id;
 await f.json('poll',{available:true},bedside.credential); f.advance(5);
 await f.json('acceptCall',{callID,available:true},bedside.credential);
 await f.json('setPermissions',{memberID:family.state.me.id,permissions:{audio:true,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('joinCall',{callID},family.credential)).status,410); assert.equal(f.ended.length,1);
 await f.json('revoke',{memberID:family.state.me.id},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('poll',{available:true},family.credential)).status,401);
});
test('six-digit PIN migrates without changing grant signing secret and locks out repeated guesses',async()=>{
 const f=fixture();
 await f.json('setCaregiverPIN',{pin:'012345'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal(process.env.PORCH_CONTACT_SETUP_CODE,env.PORCH_CONTACT_SETUP_CODE);
 assert.ok(![...f.store.values.values()].some(v=>v.includes('012345')));
 const owner=await f.json('createHousehold',{name:'Mom'},undefined,'012345');
 await f.json('verifyPIN',{},owner.credential,'012345');
 for(let n=0;n<5;n++) assert.equal((await f.send('verifyPIN',{},owner.credential,'999999')).status,403);
 assert.equal((await f.send('verifyPIN',{},owner.credential,'012345')).status,429);
 f.advance(901); assert.equal((await f.send('verifyPIN',{},owner.credential,'012345')).status,200);
});
test('expired invitations and calls do not connect, and accepted calls expire on lost devices',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'call'},family.credential);
 const callID=created.state.call.id; f.advance(76);
 assert.equal((await f.send('acceptCall',{callID,available:true},bedside.credential)).status,410);
 await f.json('poll',{available:true},bedside.credential);
 const second=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'call'},family.credential);
 await f.json('acceptCall',{callID:second.state.call.id,available:true},bedside.credential); f.advance(36);
 assert.equal((await f.send('joinCall',{callID:second.state.call.id},family.credential)).status,410);
});

test('pairing retries recover after a lost response without consuming a second invitation',async()=>{
 const f=fixture(); const deviceID=randomUUID(),deviceSecret=randomBytes(32).toString('hex');
 const first=await f.json('createHousehold',{name:'Mom',deviceID,deviceSecret},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const retry=await f.json('createHousehold',{name:'Mom',deviceID,deviceSecret},undefined,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal(first.credential,retry.credential);
 const invite=await f.json('createInvite',{name:'Ethan',permissions:{audio:true,video:false}},first.credential,env.PORCH_CONTACT_SETUP_CODE);
 const registration={code:invite.code,deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')};
 const family=await f.json('claimInvite',registration),again=await f.json('claimInvite',registration);
 assert.equal(family.credential,again.credential);
 assert.equal((await f.send('claimInvite',{...registration,deviceSecret:randomBytes(32).toString('hex')})).status,409);
});

test('a new invitation cannot reuse an existing bedside identity or inherit access to its calls',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 const invite=await f.json('createInvite',{name:'Other',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const [deviceID,deviceSecret]=bedside.credential.split('.');
 assert.equal((await f.send('claimInvite',{code:invite.code,deviceID,deviceSecret})).status,409);
 assert.equal((await f.send('claimInvite',{code:invite.code,deviceID,deviceSecret:randomBytes(32).toString('hex')})).status,409);
 assert.equal((await f.send('setCaregiverPIN',{pin:'654321'},family.credential,'123456')).status,403);
 assert.equal((await f.send('setCaregiverPIN',{pin:'654321'},undefined,'123456')).status,401);
});

test('caregivers choose how long calls to the bedside ring before voicemail',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 assert.equal(bedside.state.ringSeconds,45); assert.equal(family.state.ringSeconds,45);
 assert.equal((await f.send('setRingSeconds',{seconds:30},bedside.credential)).status,403,'needs the PIN');
 assert.equal((await f.send('setRingSeconds',{seconds:30},family.credential,env.PORCH_CONTACT_SETUP_CODE)).status,403,'family devices need caregiver approval');
 for (const seconds of [14,121,30.5,'30',null]) assert.equal((await f.send('setRingSeconds',{seconds},bedside.credential,env.PORCH_CONTACT_SETUP_CODE)).status,400,String(seconds));
 assert.equal((await f.json('setRingSeconds',{seconds:30},bedside.credential,env.PORCH_CONTACT_SETUP_CODE)).state.ringSeconds,30);
 assert.equal((await f.json('poll',{available:true},family.credential)).state.ringSeconds,30);
 // A family phone's call rings for that long; a waiting time it sends is ignored.
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'video',kind:'call',waitSeconds:120},family.credential);
 assert.equal(created.state.call.expiresAt-created.state.call.createdAt,60);
 // A call that's already ringing keeps its deadline.
 await f.json('setRingSeconds',{seconds:120},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call.expiresAt,created.state.call.expiresAt);
 await f.json('endCall',{callID:created.state.call.id},family.credential);
 // Drop-ins keep the standard time for their announcement and countdown, even with a short ring time.
 await f.json('setRingSeconds',{seconds:15},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 await f.json('setDropIn',{enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const dropIn=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'dropIn'},family.credential);
 assert.equal(dropIn.state.call.expiresAt-dropIn.state.call.createdAt,75);
 await f.json('endCall',{callID:dropIn.state.call.id},family.credential);
 // The bedside's own calls still use the waiting time it sends.
 const outgoing=await f.json('startCall',{targetID:family.state.me.id,mode:'video',kind:'call',waitSeconds:20},bedside.credential);
 assert.equal(outgoing.state.call.expiresAt-outgoing.state.call.createdAt,50);
});

test('answer and phone fallback race atomically: an answered Porch call never starts fallback',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 const created=await f.json('startCall',{targetID:family.state.me.id,mode:'video',kind:'call',waitSeconds:120},bedside.credential);
 const callID=created.state.call.id;
 assert.equal(created.state.call.expiresAt-created.state.call.createdAt,150);
 const [answer,fallback]=await Promise.all([f.send('acceptCall',{callID,available:true},family.credential),f.send('fallback',{callID},bedside.credential)]);
 assert.ok((answer.status===200 && fallback.status===409) || (answer.status===410 && fallback.status===200));
 if(answer.status===200) { assert.equal((await f.send('fallback',{callID},bedside.credential)).status,409); assert.equal(f.ended.length,0); }
 else { assert.equal((await f.send('joinCall',{callID},family.credential)).status,410); assert.equal(f.ended.length,1); }
});

test('paired bedside devices choose their own PIN once without a preset PIN', async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 assert.equal((await f.json('caregiverStatus',{},bedside.credential)).pinConfigured,false);
 assert.equal((await f.send('initializeCaregiverPIN',{pin:'012345'})).status,401);
 assert.equal((await f.send('initializeCaregiverPIN',{pin:'012345'},family.credential)).status,403);
 await f.json('initializeCaregiverPIN',{pin:'012345'},bedside.credential);
 assert.equal((await f.json('caregiverStatus',{},bedside.credential)).pinConfigured,true);
 await f.json('verifyPIN',{},bedside.credential,'012345');
 assert.equal((await f.send('initializeCaregiverPIN',{pin:'654321'},bedside.credential)).status,409);
 assert.equal((await f.send('setCaregiverPIN',{pin:'654321'},bedside.credential,'999999')).status,403);
 await f.json('setCaregiverPIN',{pin:'654321'},bedside.credential,'012345');
 await f.json('verifyPIN',{},bedside.credential,'654321');
 assert.equal((await f.send('verifyPIN',{},bedside.credential,'012345')).status,403);
});

test('caregiver PINs and lockouts are isolated by household and supersede the old shared PIN',async()=>{
 const f=fixture();
 await f.json('setCaregiverPIN',{pin:'111111'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const a=await f.json('createHousehold',{name:'First'},undefined,'111111');
 const b=await f.json('createHousehold',{name:'Second'},undefined,'111111');
 await f.json('initializeCaregiverPIN',{pin:'222222'},a.credential);
 await f.json('initializeCaregiverPIN',{pin:'333333'},b.credential);
 for(let n=0;n<5;n++)assert.equal((await f.send('verifyPIN',{},a.credential,'111111')).status,403);
 assert.equal((await f.send('verifyPIN',{},a.credential,'222222')).status,429);
 await f.json('verifyPIN',{},b.credential,'333333');
 assert.equal((await f.send('verifyPIN',{},b.credential,'222222')).status,403);
});

test('new bedside enrollment uses a one-use activation and a caregiver-chosen PIN',async()=>{
 const f=fixture();
 assert.equal((await f.send('createBedsideInvite',{},undefined,'123456')).status,403);
 const invite=await f.json('createBedsideInvite',{},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const registration={deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex'),pin:'098765',activation:invite.code};
 const owner=await f.json('enrollBedside',registration);
 assert.equal(owner.state.householdName,'Your loved one');
 assert.equal(owner.state.me.name,'Your loved one');
 await f.json('verifyPIN',{},owner.credential,'098765');
 const retry=await f.json('enrollBedside',registration);
 assert.equal(retry.credential,owner.credential);
 assert.equal((await f.send('enrollBedside',{...registration,pin:'999999'})).status,403);
 assert.equal((await f.send('enrollBedside',{...registration,deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')})).status,410);
});

test('expired or missing activation cannot enroll; malformed details do not consume a valid link',async()=>{
 const f=fixture(),register=()=>({deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex'),pin:'012345'});
 assert.equal((await f.send('enrollBedside',register())).status,403);
 const first=await f.json('createBedsideInvite',{},undefined,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('enrollBedside',{...register(),activation:first.code,pin:'123'})).status,400);
 await f.json('enrollBedside',{...register(),activation:first.code});
 const expired=await f.json('createBedsideInvite',{},undefined,env.PORCH_CONTACT_SETUP_CODE);
 f.advance(86401);
 assert.equal((await f.send('enrollBedside',{...register(),activation:expired.code})).status,410);
});

test('review activations last 90 days, remain operator-only, and enroll isolated households once',async()=>{
 const f=fixture();
 const {bedside,family}=await f.setup();
 for(const credential of [undefined,bedside.credential,family.credential]) {
  assert.equal((await f.send('createBedsideInvite',{purpose:'appReview'},credential,'123456')).status,403);
  assert.equal((await f.send('createBedsideInvite',{purpose:'appReview'},credential,env.PORCH_CALL_ACCESS_CODE)).status,403);
 }
 const ordinary=await f.json('createBedsideInvite',{},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const invite=await f.json('createBedsideInvite',{purpose:'appReview'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal(invite.expiresAt-ordinary.expiresAt,89*86400);
 assert.equal((await f.send('createBedsideInvite',{purpose:'unknown'},undefined,env.PORCH_CONTACT_SETUP_CODE)).status,400);
 f.advance(30*86400);
 const registration={deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex'),pin:'098765',name:'Review bedside',activation:invite.code};
 const owner=await f.json('enrollBedside',registration);
 assert.notEqual(owner.state.householdID,bedside.state.householdID);
 assert.deepEqual(owner.state.people,[]);
 assert.equal(owner.state.dropInEnabled,false);
 assert.equal((await f.json('enrollBedside',registration)).credential,owner.credential);
 assert.equal((await f.send('enrollBedside',{...registration,deviceID:randomUUID()})).status,410);
 await f.json('verifyPIN',{},owner.credential,'098765');
 assert.equal((await f.send('verifyPIN',{},bedside.credential,'098765')).status,403);
 const expired=await f.json('createBedsideInvite',{purpose:'appReview'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 f.advance(90*86400+1);
 assert.equal((await f.send('enrollBedside',{...registration,deviceID:randomUUID(),activation:expired.code})).status,410);
});

test('activation issuance preserves the matching storage lifetime and reports a failed write',async()=>{
 const f=fixture(); const create=f.store.create.bind(f.store); const lifetimes=[];
 f.store.create=async(key,value,seconds)=>{lifetimes.push(seconds);return create(key,value);};
 await f.json('createBedsideInvite',{},undefined,env.PORCH_CONTACT_SETUP_CODE);
 await f.json('createBedsideInvite',{purpose:'appReview'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 assert.deepEqual(lifetimes,[86400,90*86400]);
 f.store.create=async()=>false;
 assert.equal((await f.send('createBedsideInvite',{purpose:'appReview'},undefined,env.PORCH_CONTACT_SETUP_CODE)).status,409);
});

test('a saved legacy credential can migrate directly to a chosen household PIN',async()=>{
 const f=fixture();
 const owner=await f.json('enrollBedside',{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex'),pin:'123456',name:'Pat'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 await f.json('verifyPIN',{},owner.credential,'123456');
 assert.equal(owner.state.me.name,'Pat');
});

test('caregiver display-name edits propagate to family callers and reject unauthorized edits',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 await f.json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
 assert.equal((await f.send('setHouseholdName',{name:'Pat'},family.credential,'123456')).status,403);
 assert.equal((await f.send('setHouseholdName',{name:'Pat'},bedside.credential)).status,403);
 assert.equal((await f.send('setHouseholdName',{name:' '},bedside.credential,'123456')).status,400);
 const saved=await f.json('setHouseholdName',{name:' Pat '},bedside.credential,'123456');
 assert.equal(saved.state.householdName,'Pat');
 assert.equal((await f.json('poll',{available:true},family.credential)).state.people[0].name,'Pat');
});

test('contacts without a paired app get a confirmed offline result before phone fallback',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 const result=await f.send('startCall',{unlinked:true,kind:'call',mode:'voice'},bedside.credential);
 assert.equal(result.status,409);assert.equal((await result.json()).errorCode,'offline');
 assert.equal((await f.send('startCall',{unlinked:true,kind:'call',mode:'voice'},family.credential)).status,403);
 assert.equal((await f.json('poll',{available:true},bedside.credential)).state.call,null);
 await f.json('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential);
 const busy=await f.send('startCall',{unlinked:true,kind:'call',mode:'voice'},bedside.credential);
 assert.equal(busy.status,409);assert.equal((await busy.json()).errorCode,undefined);
});

test('contact invitations expose pending status and a durable accepted identity only to bedside',async()=>{
 const f=fixture(); const bedside=await f.json('createHousehold',{},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const invite=await f.json('createInvite',{name:'Same name',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.match(invite.invitationID,/^[a-f0-9-]{36}$/);
 assert.deepEqual(invite.state.invitations,[{id:invite.invitationID,name:'Same name',expiresAt:invite.expiresAt}]);
 assert.ok(!JSON.stringify(invite.state).includes(invite.code));
 const family=await f.json('claimInvite',{code:invite.code});
 assert.deepEqual(family.state.invitations,[]); assert.equal(family.state.me.invitationID,undefined);
 const next=await f.json('createInvite',{name:'Same name',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const poll=await f.json('poll',{available:true},bedside.credential);
 assert.equal(poll.state.people[0].invitationID,invite.invitationID);
 assert.notEqual(poll.state.invitations[0].id,invite.invitationID);
 await f.json('cancelInvites',{},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const after=await f.json('poll',{available:true},bedside.credential);
 assert.deepEqual(after.state.invitations,[]);
 assert.equal(after.state.people[0].invitationID,invite.invitationID,'creating/cancelling other invites must not lose an accepted association');
 assert.equal((await f.send('claimInvite',{code:next.code})).status,410);
 await f.json('revoke',{memberID:family.state.me.id},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.deepEqual((await f.json('poll',{available:true},bedside.credential)).state.people,[]);
});


test('VoIP registration is authenticated, device scoped, validated and never exposed in snapshots', async()=>{
 const f=fixture({sendPush:async()=>({delivered:true})}),{bedside,family}=await f.setup();
 const token='ab'.repeat(32);
 assert.equal((await f.send('registerVoIP',{token,environment:'production'})).status,401);
 assert.equal((await f.send('registerVoIP',{token,environment:'production'},bedside.credential)).status,200);
 for (const value of [{token:'bad',environment:'production'},{token,environment:'arbitrary-host'},{token:'a'.repeat(65),environment:'sandbox'}]) {
  assert.equal((await f.send('registerVoIP',value,family.credential)).status,400);
 }
 const registered=await f.json('registerVoIP',{token,environment:'production'},family.credential);
 assert.equal(registered.pushReady,true);
 assert.ok(!JSON.stringify(registered.state).includes(token));
 assert.equal(registered.state.me.canReceiveCalls,true);
 assert.ok(!JSON.stringify((await f.json('poll',{available:true},bedside.credential)).state).includes(token));
 await f.json('registerVoIP',{token:null},family.credential);
 await f.json('poll',{available:false},family.credential);
 assert.equal((await f.send('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential)).status,409);
});

test('offline family devices receive ordinary-call pushes once after the winning reservation',async()=>{
 const pushes=[],f=fixture({sendPush:async(device,call)=>{pushes.push({device,call});return {delivered:true};}});
 const {bedside,family}=await f.setup();
 const registration={token:'ab'.repeat(32),environment:'sandbox'};
 await f.json('registerVoIP',registration,family.credential);
 await f.json('poll',{available:false},family.credential); f.advance(31);
 const presence=(await f.json('poll',{available:true},bedside.credential)).state.people[0];
 assert.equal(presence.online,false);assert.equal(presence.canReceiveCalls,true);
 const values={targetID:family.state.me.id,mode:'video',kind:'call',waitSeconds:20};
 const responses=await Promise.all([f.send('startCall',values,bedside.credential),f.send('startCall',values,bedside.credential)]);
 assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);
 assert.equal(pushes.length,1);assert.deepEqual(pushes[0].device,registration);
 const call=(await responses.find(r=>r.status===200).json()).state.call;
 assert.deepEqual(pushes[0].call,{callID:call.id,recipientID:family.state.me.id,callerName:'Mom',mode:'video',expiresAt:call.expiresAt});
 assert.ok(!JSON.stringify(pushes).includes(family.credential));
 await f.json('endCall',{callID:call.id},bedside.credential);
 assert.equal(pushes.length,1,'cancellation never sends another VoIP push');
 assert.equal((await f.send('acceptCall',{callID:call.id,available:true},family.credential)).status,410);
});

test('CallKit answer retains the atomic phone fallback race and heartbeats keep locked calls alive',async()=>{
 const f=fixture({sendPush:async()=>({delivered:true})}),{bedside,family}=await f.setup();
 await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
 await f.json('poll',{available:false},family.credential);
 const created=await f.json('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential),callID=created.state.call.id;
 await f.json('acceptCall',{callID,available:true},family.credential);
 for(let n=0;n<10;n++) {
  f.advance(10);
  const state=await f.json('poll',{available:false},family.credential);
  assert.equal(state.state.call.state,'accepted');
  await f.json('poll',{available:false},bedside.credential);
 }
 assert.equal((await f.send('fallback',{callID},bedside.credential)).status,409);
 await f.json('joinCall',{callID},family.credential);
});

test('push failures release unreachable calls for existing phone fallback and clear invalid tokens',async()=>{
 const f=fixture({sendPush:async()=>({delivered:false,invalidToken:true})}),{bedside,family}=await f.setup();
 await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
 await f.json('poll',{available:false},family.credential);
 const failed=await f.send('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential);
 assert.equal(failed.status,409);assert.equal((await failed.json()).errorCode,'offline');
 const state=await f.json('poll',{available:true},bedside.credential);
 assert.equal(state.state.call.state,'ended');assert.equal(f.ended.length,1);
 assert.ok(![...f.store.values.values()].some(value=>value.includes('abababab')));
});

test('failed pushes do not cancel a foreground delivery, and drop-in never wakes a background bedside',async()=>{
 const pushes=[],f=fixture({sendPush:async(...args)=>{pushes.push(args);return {delivered:false};}}),{bedside,family}=await f.setup();
 await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
 const created=await f.json('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential);
 await f.json('acceptCall',{callID:created.state.call.id,available:true},family.credential);
 await f.json('endCall',{callID:created.state.call.id},family.credential);
 await f.json('setDropIn',{enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 await f.json('poll',{available:false},bedside.credential);
 assert.equal((await f.send('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'dropIn'},family.credential)).status,409);
 assert.equal(pushes.length,1);
 await f.json('revoke',{memberID:family.state.me.id},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('registerVoIP',{token:'cd'.repeat(32),environment:'production'},family.credential)).status,401);
});

test('token rotation during delivery is preserved, and an answer wins over a push failure',async()=>{
 let deliver, sent;
 const arrived=new Promise(resolve=>sent=resolve);
 const f=fixture({sendPush:async()=>{sent();return new Promise(resolve=>deliver=resolve);}}),{bedside,family}=await f.setup();
 await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
 await f.json('poll',{available:false},family.credential);
 const request=f.send('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential);
 await arrived;
 const poll=await f.json('poll',{available:false},family.credential),callID=poll.state.call.id;
 await f.json('registerVoIP',{token:'cd'.repeat(32),environment:'production'},family.credential);
 await f.json('acceptCall',{callID,available:true},family.credential);
 deliver({delivered:false,invalidToken:true});
 const response=await request;assert.equal(response.status,200);assert.equal((await response.json()).state.call.state,'accepted');
 assert.ok([...f.store.values.values()].some(value=>value.includes('cd'.repeat(32))));
 assert.equal(f.ended.length,0);
});


test('a decline during a failed push is preserved instead of being reclassified for phone fallback',async()=>{
 let deliver,sent;const arrived=new Promise(resolve=>sent=resolve);
 const f=fixture({sendPush:async()=>{sent();return new Promise(resolve=>deliver=resolve);}}),{bedside,family}=await f.setup();
 await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
 const pending=f.send('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential);
 await arrived;
 const state=await f.json('poll',{available:false},family.credential);
 await f.json('endCall',{callID:state.state.call.id},family.credential);
 deliver({delivered:false});
 const result=await pending;assert.equal(result.status,200);assert.equal((await result.json()).state.call.reason,'Call ended.');
});

test('background receipt preserves ringing when the APNs acknowledgment is lost',async()=>{
 for (const failure of ['response','error']) {
  for (const outcome of ['answer','fallback']) {
   let deliver,sent; const arrived=new Promise(resolve=>sent=resolve);
   const f=fixture({sendPush:async()=>{sent();await new Promise(resolve=>deliver=resolve);if(failure==='error')throw new Error('APNs acknowledgment lost');return {delivered:false};}});
   const {bedside,family}=await f.setup();
   await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
   await f.json('poll',{available:false},family.credential);
   const pending=f.send('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call',waitSeconds:20},bedside.credential);
   await arrived;
   const current=(await f.json('poll',{available:false},family.credential)).state.call;
   const receipt=await f.json('poll',{available:false,receivedCallID:current.id},family.credential);
   deliver();
   const response=await pending;
   assert.equal(response.status,200,'authenticated receipt must preserve the pending call');
   const call=(await response.json()).state.call;
   assert.equal(call.state,'pending');assert.equal(call.expiresAt,current.expiresAt);
   assert.equal(receipt.state.me.online,false,'receipt must not advertise foreground availability');
   assert.equal(call.announcedAt,undefined,'ordinary receipt is separate from drop-in consent');
   assert.equal(f.ended.length,0);
   assert.equal((await f.send('joinCall',{callID:call.id},family.credential)).status,403);
   if(outcome==='answer') {
    await f.json('acceptCall',{callID:call.id,available:true},family.credential);
    assert.equal((await f.send('fallback',{callID:call.id},bedside.credential)).status,409);
   } else {
    await f.json('fallback',{callID:call.id},bedside.credential);
    assert.equal((await f.send('acceptCall',{callID:call.id,available:true},family.credential)).status,410);
   }
  }
 }
});

test('caller, stale-call and unscoped background polls cannot acknowledge delivery',async()=>{
 for (const source of ['caller','stale','unscoped']) {
  let deliver,sent; const arrived=new Promise(resolve=>sent=resolve);
  const f=fixture({sendPush:async()=>{sent();return new Promise(resolve=>deliver=resolve);}}),{bedside,family}=await f.setup();
  await f.json('registerVoIP',{token:'ab'.repeat(32),environment:'production'},family.credential);
  await f.json('poll',{available:false},family.credential);
  const pending=f.send('startCall',{targetID:family.state.me.id,mode:'voice',kind:'call'},bedside.credential);
  await arrived;
  const current=(await f.json('poll',{available:false},family.credential)).state.call;
  const values={available:false,...(source==='unscoped'?{}:{receivedCallID:source==='stale'?randomUUID():current.id})};
  await f.json('poll',values,source==='caller'?bedside.credential:family.credential);
  deliver({delivered:false});
  const response=await pending; assert.equal(response.status,409);assert.equal((await response.json()).errorCode,'offline');
 }
});

test('a delivery receipt cannot skip the bedside drop-in announcement',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 await f.json('setDropIn',{enabled:true},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'dropIn'},family.credential),callID=created.state.call.id;
 await f.json('poll',{available:false,receivedCallID:callID},bedside.credential);
 f.advance(5);
 assert.equal((await f.send('acceptCall',{callID,available:true},bedside.credential)).status,409);
 await f.json('poll',{available:true},bedside.credential);f.advance(5);
 await f.json('acceptCall',{callID,available:true},bedside.credential);
});

test('ordinary Porch calls wake the bedside, while drop-in still requires foreground consent', async () => {
 const pushes = [], f = fixture({ sendPush: async (device, call) => { pushes.push({ device, call }); return { delivered: true }; } });
 const { bedside, family } = await f.setup();
 await f.json('registerVoIP', { token: 'ab'.repeat(32), environment: 'production' }, bedside.credential);
 await f.json('setDropIn', { enabled: true }, bedside.credential, env.PORCH_CONTACT_SETUP_CODE);
 await f.json('poll', { available: false }, bedside.credential); f.advance(90);
 const state = (await f.json('poll', { available: true }, family.credential)).state;
 assert.equal(state.people[0].online, false); assert.equal(state.people[0].canReceiveCalls, true);
 assert.equal((await f.send('startCall', { targetID: bedside.state.me.id, mode: 'video', kind: 'dropIn' }, family.credential)).status, 409);
 assert.equal(pushes.length, 0);
 const started = await f.json('startCall', { targetID: bedside.state.me.id, mode: 'voice', kind: 'call' }, family.credential);
 assert.equal(pushes.length, 1); assert.equal(pushes[0].call.recipientID, bedside.state.me.id);
 await f.json('acceptCall', { callID: started.state.call.id, available: true }, bedside.credential);
 assert.equal((await f.json('poll', { available: false }, bedside.credential)).state.call.state, 'accepted');
});
test('approved family caregivers manage server-held access with the PIN; the PIN itself stays on the bedside',async()=>{
 const f=fixture(),{bedside,family}=await f.setup({audio:false,video:false});
 await f.json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
 assert.equal(family.state.me.caregiver,false);
 assert.equal((await f.send('verifyPIN',{},family.credential,'123456')).status,403);
 assert.equal((await f.send('createInvite',{name:'Sam',permissions:{audio:false,video:false},caregiver:'yes'},bedside.credential,'123456')).status,400);
 const invite=await f.json('createInvite',{name:'Sam',permissions:{audio:false,video:false},caregiver:true},bedside.credential,'123456');
 const sam=await f.json('claimInvite',{code:invite.code});
 assert.equal(sam.state.me.caregiver,true);
 assert.equal((await f.send('verifyPIN',{},sam.credential)).status,403);
 const unlocked=await f.json('verifyPIN',{},sam.credential,'123456');
 assert.deepEqual(unlocked.admin.people.map(p=>p.name).sort(),['Ethan','Sam']);
 assert.equal(unlocked.admin.householdName,'Mom');
 // Without the PIN, a caregiver phone still only sees the bedside.
 assert.deepEqual((await f.json('poll',{available:true},sam.credential)).state.people.map(p=>p.role),['bedside']);
 assert.equal((await f.json('setDropIn',{enabled:true},sam.credential,'123456')).admin.dropInEnabled,true);
 await f.json('setPermissions',{memberID:family.state.me.id,permissions:{audio:true,video:false}},sam.credential,'123456');
 await f.json('setCaregiver',{memberID:family.state.me.id,enabled:true},sam.credential,'123456');
 const ethan=(await f.json('poll',{available:true},family.credential)).state.me;
 assert.equal(ethan.caregiver,true); assert.deepEqual(ethan.permissions,{audio:true,video:false});
 assert.equal((await f.send('setCaregiver',{memberID:sam.state.me.id,enabled:false},sam.credential,'123456')).status,403);
 assert.equal((await f.send('revoke',{memberID:sam.state.me.id},sam.credential,'123456')).status,403);
 assert.equal((await f.send('revoke',{memberID:bedside.state.me.id},sam.credential,'123456')).status,404);
 assert.ok((await f.json('createInvite',{name:'Lee',permissions:{audio:false,video:false},caregiver:true},sam.credential,'123456')).code);
 const renamed=await f.json('setHouseholdName',{name:'Grandma'},sam.credential,'123456');
 assert.equal(renamed.state.me.name,'Sam');
 const home=(await f.json('poll',{available:true},bedside.credential)).state;
 assert.equal(home.householdName,'Grandma'); assert.equal(home.me.name,'Grandma');
 assert.equal((await f.send('setCaregiverPIN',{pin:'654321'},sam.credential,'123456')).status,403);
 assert.equal((await f.send('caregiverStatus',{},sam.credential)).status,403);
 await f.json('setCaregiver',{memberID:sam.state.me.id,enabled:false},bedside.credential,'123456');
 assert.equal((await f.send('verifyPIN',{},sam.credential,'123456')).status,403);
 await f.json('revoke',{memberID:family.state.me.id},bedside.credential,'123456');
 assert.equal((await f.send('verifyPIN',{},family.credential,'123456')).status,401);
});
test('wrong PINs from a caregiver phone lock out only that phone',async()=>{
 const f=fixture(),{bedside}=await f.setup();
 await f.json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
 const invite=await f.json('createInvite',{name:'Sam',permissions:{audio:false,video:false},caregiver:true},bedside.credential,'123456');
 const sam=await f.json('claimInvite',{code:invite.code});
 for(let n=0;n<5;n++) assert.equal((await f.send('verifyPIN',{},sam.credential,'999999')).status,403);
 assert.equal((await f.send('verifyPIN',{},sam.credential,'123456')).status,429);
 await f.json('verifyPIN',{},bedside.credential,'123456');
 f.advance(901); await f.json('verifyPIN',{},sam.credential,'123456');
});
test('leaving a family revokes only this device and ends its call',async()=>{
 const f=fixture(),{bedside,family}=await f.setup();
 const created=await f.json('startCall',{targetID:bedside.state.me.id,mode:'voice',kind:'call'},family.credential);
 assert.equal((await f.send('leaveHousehold',{},bedside.credential)).status,403);
 assert.deepEqual(await f.json('leaveHousehold',{},family.credential),{left:true});
 assert.deepEqual(f.ended,[`porch-paired-${created.state.call.id}`]);
 const home=(await f.json('poll',{available:true},bedside.credential)).state;
 assert.deepEqual(home.people,[]); assert.equal(home.call.state,'ended');
 assert.equal((await f.send('poll',{available:true},family.credential)).status,401);
 assert.equal((await f.send('leaveHousehold',{},family.credential)).status,401);
});
