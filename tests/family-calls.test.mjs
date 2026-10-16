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
function fixture() {
 const store = new MemoryStore(), ended=[];
 let now=1_800_000_000;
 const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`} : {}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")} : {}),...values})}),{store,now:()=>now,endRoom:async room=>ended.push(room)});
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
test('expired and cancelled invitations cannot pair',async()=>{
 const f=fixture(); const bedside=await f.json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
 const invite=await f.json('createInvite',{name:'Ethan',permissions:{audio:true,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 f.advance(901); assert.equal((await f.send('claimInvite',{code:invite.code})).status,410);
 const next=await f.json('createInvite',{name:'Ethan',permissions:{audio:false,video:false}},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 await f.json('cancelInvites',{},bedside.credential,env.PORCH_CONTACT_SETUP_CODE);
 assert.equal((await f.send('claimInvite',{code:next.code})).status,410);
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
