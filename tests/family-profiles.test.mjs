import assert from 'node:assert/strict';
import { createHash, randomUUID, randomBytes } from 'node:crypto';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';

class MemoryStore {
  values = new Map();
  async get(key) { return this.values.get(key) ?? null; }
  async create(key, value) { if (this.values.has(key)) return false; this.values.set(key,value); return true; }
  async compareAndSet(key, before, after) { if (this.values.get(key) !== before) return false; this.values.set(key,after); return true; }
}
class FakeMedia {
  blobs = new Map(); removed = []; signed = [];
  async uploadTarget(pathname, contentType, maximumSizeInBytes, validUntil) {
    this.signed.push({ pathname, contentType, maximumSizeInBytes });
    return { url: `https://blob.test/put?pathname=${pathname}`, method: 'PUT', headers: { 'x-content-type': contentType }, expiresAt: validUntil };
  }
  async downloadURL(pathname, validUntil) { return `https://blob.test/get/${pathname}?until=${validUntil}`; }
  async stat(pathname) { return this.blobs.get(pathname) ?? null; }
  async remove(pathnames) { for (const p of pathnames) { this.blobs.delete(p); this.removed.push(p); } }
  upload(target, size = 1000, contentType = target.headers['x-content-type']) { const pathname = new URL(target.url).searchParams.get('pathname'); this.blobs.set(pathname, { size, contentType }); return pathname; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', PORCH_CALL_ACCESS_CODE:'private-test-calling-code' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });
const photoID = seed => createHash('sha256').update(String(seed)).digest('hex');

async function fixture() {
  const store = new MemoryStore(), media = new FakeMedia();
  let now = 1_800_000_000;
  const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")}:{}),...values})}),{store,media,now:()=>now,endRoom:async()=>{}});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const status = async (...args) => (await send(...args)).status;
  const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
  await json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
  const join = async (name, caregiver=false) => json('claimInvite',{code:(await json('createInvite',{name,permissions:{audio:false,video:false},caregiver},bedside.credential,'123456')).code});
  const ethan = await join('Ethan'), sam = await join('Sam', true);
  const id = who => who.state.me.id;
  // How the bedside sees a family member.
  const seen = async who => (await json('poll',{available:true},bedside.credential)).state.people.find(p => p.id === id(who));
  // Uploads a photo the way the apps do: ask for a signed URL, upload, then save it.
  const uploadPhoto = async (credential, seed, values = {}, pin) => {
    const action = values.memberID ? 'overridePhotoUpload' : 'profilePhotoUpload';
    const created = await json(action,{sizeBytes:50_000,...values},credential,pin);
    media.upload(created.upload, 50_000);
    return { id: photoID(seed), pathname: created.pathname };
  };
  return { store, media, send, json, status, bedside, ethan, sam, id, seen, uploadPhoto, advance: s => now += s };
}

test('a family member chooses the name and photo the bedside shows',async()=>{
  const f=await fixture();
  const { name, invitedName, profile, override, photoID: none } = await f.seen(f.ethan);
  assert.deepEqual({ name, invitedName, profile, override, none },{ name:'Ethan', invitedName:'Ethan', profile:{}, override:{}, none:undefined });
  const photo=await f.uploadPhoto(f.ethan.credential,'ethan-1');
  assert.match(photo.pathname,new RegExp(`^profiles/${f.bedside.state.householdID}/${f.id(f.ethan)}/self/[a-f0-9-]{36}\\.jpg$`));
  assert.deepEqual(f.media.signed.at(-1),{pathname:photo.pathname,contentType:'image/jpeg',maximumSizeInBytes:50_000});
  const saved=await f.json('setProfile',{name:'  Ethan T.  ',photo},f.ethan.credential);
  assert.deepEqual(saved.state.me.profile,{name:'Ethan T.',photoID:photo.id});
  assert.equal(saved.state.me.name,'Ethan T.');
  assert.ok(!JSON.stringify(saved).includes(photo.pathname),'devices never see where photos are stored');
  const person=await f.seen(f.ethan);
  assert.equal(person.name,'Ethan T.'); assert.equal(person.photoID,photo.id); assert.equal(person.invitedName,'Ethan');
  // The bedside downloads it; the member can see their own, but not someone else's.
  const download=await f.json('profilePhoto',{memberID:f.id(f.ethan)},f.bedside.credential);
  assert.equal(download.photo.id,photo.id); assert.match(download.photo.url,/^https:\/\/blob\.test\/get\/profiles\//);
  assert.equal((await f.json('profilePhoto',{},f.ethan.credential)).photo.id,photo.id);
  assert.equal(await f.status('profilePhoto',{memberID:f.id(f.ethan)},f.sam.credential),403);
  // Only changed fields change; an empty name returns to the invitation's name.
  await f.json('setProfile',{name:''},f.ethan.credential);
  assert.equal((await f.seen(f.ethan)).name,'Ethan'); assert.equal((await f.seen(f.ethan)).photoID,photo.id);
  await f.json('setProfile',{photo:null},f.ethan.credential);
  assert.ok(!('photoID' in await f.seen(f.ethan)));
  assert.deepEqual(f.media.removed,[photo.pathname],'a removed photo is deleted');
  assert.equal(await f.status('setProfile',{name:'x'.repeat(81)},f.ethan.credential),400);
  assert.equal(await f.status('setProfile',{name:'Mom'},f.bedside.credential),403,'the bedside has no profile');
});

test('the chosen name labels calls and messages',async()=>{
  const f=await fixture();
  await f.json('setProfile',{name:'Ethan T.'},f.ethan.credential);
  await f.json('poll',{available:true},f.bedside.credential);
  const call=(await f.json('startCall',{targetID:f.bedside.state.me.id,mode:'voice',kind:'call'},f.ethan.credential)).state.call;
  assert.equal((await f.json('poll',{available:true},f.bedside.credential)).state.call.callerName,'Ethan T.');
  await f.json('endCall',{callID:call.id},f.ethan.credential);
  const created=await f.json('createMessage',{mode:'audio',contentType:'audio/mp4',sizeBytes:1000,durationSeconds:3},f.ethan.credential);
  f.media.upload(created.upload);
  await f.json('completeMessage',{messageID:created.message.id},f.ethan.credential);
  await f.json('setProfile',{name:'E'},f.ethan.credential);
  assert.equal((await f.json('poll',{available:true},f.bedside.credential)).state.messages[0].fromName,'E','a waiting message follows a later rename');
});

test('photos must be the member\'s own finished upload',async()=>{
  const f=await fixture();
  const theirs=await f.uploadPhoto(f.sam.credential,'sam');
  assert.equal(await f.status('setProfile',{photo:theirs},f.ethan.credential),400,'another member\'s upload');
  const created=await f.json('profilePhotoUpload',{sizeBytes:50_000},f.ethan.credential);
  const pending={id:photoID('x'),pathname:created.pathname};
  assert.equal(await f.status('setProfile',{photo:pending},f.ethan.credential),409,'not uploaded yet');
  f.media.upload(created.upload,50_000,'image/png');
  assert.equal(await f.status('setProfile',{photo:pending},f.ethan.credential),400,'not a JPEG');
  f.media.upload(created.upload,2_000_000);
  assert.equal(await f.status('setProfile',{photo:pending},f.ethan.credential),400,'too large');
  f.media.upload(created.upload,50_000);
  assert.equal(await f.status('setProfile',{photo:{...pending,id:'not-a-hash'}},f.ethan.credential),400);
  assert.equal(await f.status('setProfile',{photo:{...pending,pathname:pending.pathname.replace('/self/','/caregiver/')}},f.ethan.credential),400,'a caregiver\'s folder');
  assert.equal(await f.status('profilePhotoUpload',{sizeBytes:1_000_001},f.ethan.credential),413);
  assert.equal((await f.json('setProfile',{photo:pending},f.ethan.credential)).state.me.profile.photoID,pending.id);
});

test('a caregiver\'s name and photo come first, and clearing them restores the member\'s own',async()=>{
  const f=await fixture();
  const own=await f.uploadPhoto(f.ethan.credential,'own');
  await f.json('setProfile',{name:'Ethan T.',photo:own},f.ethan.credential);
  const member={memberID:f.id(f.ethan)};
  assert.equal(await f.status('setMemberOverride',{...member,name:'Grandson'},f.bedside.credential),403,'needs the PIN');
  assert.equal(await f.status('setMemberOverride',{...member,name:'Grandson'},f.ethan.credential,'123456'),403,'not a caregiver');
  // From the bedside, then from an approved caregiver's phone.
  const result=await f.json('setMemberOverride',{...member,name:'Grandson'},f.bedside.credential,'123456');
  assert.deepEqual(result.admin.people.find(p=>p.id===member.memberID).override,{name:'Grandson'});
  const chosen=await f.uploadPhoto(f.sam.credential,'chosen',member,'123456');
  assert.match(chosen.pathname,/\/caregiver\/[a-f0-9-]{36}\.jpg$/);
  await f.json('setMemberOverride',{...member,photo:chosen},f.sam.credential,'123456');
  let person=await f.seen(f.ethan);
  assert.deepEqual({name:person.name,photoID:person.photoID,profile:person.profile,override:person.override},{name:'Grandson',photoID:chosen.id,profile:{name:'Ethan T.',photoID:own.id},override:{name:'Grandson',photoID:chosen.id}});
  // The member sees how they appear and still edits their own.
  const mine=(await f.json('poll',{available:true},f.ethan.credential)).state.me;
  assert.equal(mine.name,'Grandson'); assert.deepEqual(mine.profile,{name:'Ethan T.',photoID:own.id});
  assert.equal((await f.json('profilePhoto',{source:'self'},f.ethan.credential)).photo.id,own.id);
  assert.equal((await f.json('caregiverProfilePhoto',member,f.sam.credential,'123456')).photo.id,chosen.id);
  await f.json('setMemberOverride',{...member,name:null,photo:null},f.sam.credential,'123456');
  person=await f.seen(f.ethan);
  assert.deepEqual({name:person.name,photoID:person.photoID,override:person.override},{name:'Ethan T.',photoID:own.id,override:{}});
  assert.deepEqual(f.media.removed,[chosen.pathname],'only the caregiver\'s photo was deleted');
  assert.equal(await f.status('setMemberOverride',{memberID:f.bedside.state.me.id,name:'X'},f.bedside.credential,'123456'),404,'only family members');
});

test('losing access deletes a member\'s photos',async()=>{
  const f=await fixture();
  const own=await f.uploadPhoto(f.ethan.credential,'own');
  await f.json('setProfile',{photo:own},f.ethan.credential);
  const chosen=await f.uploadPhoto(f.bedside.credential,'chosen',{memberID:f.id(f.ethan)},'123456');
  await f.json('setMemberOverride',{memberID:f.id(f.ethan),photo:chosen},f.bedside.credential,'123456');
  await f.json('revoke',{memberID:f.id(f.ethan)},f.bedside.credential,'123456');
  assert.deepEqual(f.media.removed.sort(),[own.pathname,chosen.pathname].sort());
  const samPhoto=await f.uploadPhoto(f.sam.credential,'sam');
  await f.json('setProfile',{photo:samPhoto},f.sam.credential);
  await f.json('leaveHousehold',{},f.sam.credential);
  assert.ok(f.media.removed.includes(samPhoto.pathname));
  const house=JSON.parse(await f.store.get(`house:${f.bedside.state.householdID}`));
  assert.ok(house.members.every(m => !m.profile && !m.override));
});
