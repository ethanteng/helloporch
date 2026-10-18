import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
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
  upload(target, size = 1000) { const pathname = new URL(target.url).searchParams.get('pathname'); this.blobs.set(pathname, { size, contentType: target.headers['x-content-type'] }); return pathname; }
}
const env = { LIVEKIT_URL:'wss://test.livekit.cloud', LIVEKIT_API_KEY:'test-key', LIVEKIT_API_SECRET:'test-secret-not-real', PORCH_CONTACT_SETUP_CODE:'private-test-caregiver-secret', PORCH_CALL_ACCESS_CODE:'private-test-calling-code' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k,process.env[k]])); Object.assign(process.env,env); });
afterEach(() => { for (const [k,v] of Object.entries(previous)) { if(v===undefined) delete process.env[k]; else process.env[k]=v; } });
const day = 86400;
async function fixture() {
  const store = new MemoryStore(), media = new FakeMedia();
  let now = 1_800_000_000;
  const alerts = [], alertResult = { delivered: true };
  const sendAlert = async (device, alert) => { alerts.push({ device, alert }); return alertResult; };
  const send = (action, values={}, credential, pin) => handleFamily(new Request('https://porch.example/api/family',{method:'POST',headers:{...(credential?{Authorization:`Bearer ${credential}`}:{}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...(["claimInvite","createHousehold"].includes(action)?{deviceID:randomUUID(),deviceSecret:randomBytes(32).toString("hex")}:{}),...values})}),{store,media,now:()=>now,endRoom:async()=>{},sendAlert});
  const json = async (...args) => { const response=await send(...args); assert.equal(response.status,200,await response.clone().text()); return response.json(); };
  const bedside = await json('createHousehold',{name:'Mom'},undefined,env.PORCH_CONTACT_SETUP_CODE);
  await json('initializeCaregiverPIN',{pin:'123456'},bedside.credential);
  const join = async (name, caregiver=false) => json('claimInvite',{code:(await json('createInvite',{name,permissions:{audio:false,video:false},caregiver},bedside.credential,'123456')).code});
  const ethan = await join('Ethan'), sam = await join('Sam', true);
  // Records an upload: create, upload to the signed URL, complete.
  const sendMessage = async (who, values={}) => {
    const created = await json('createMessage',{mode:'audio',contentType:'audio/mp4',sizeBytes:1000,durationSeconds:30,...values},who.credential);
    media.upload(created.upload, values.sizeBytes ?? 1000);
    return (await json('completeMessage',{messageID:created.message.id},who.credential)).message;
  };
  const queue = async () => (await json('poll',{available:true},bedside.credential)).state.messages;
  const sent = async who => (await json('listMessages',{},who.credential)).messages;
  // The bedside leaves a message for a family member who missed its call.
  const leaveMessage = async (who, values={}) => sendMessage(bedside, { kind:'voicemail', to: who.state.me.id, ...values });
  const received = async who => (await json('listMessages',{},who.credential)).received;
  const unheard = async who => (await json('poll',{available:true},who.credential)).state.newMessages;
  return { store, media, send, json, bedside, ethan, sam, sendMessage, queue, sent, leaveMessage, received, unheard, alerts, alertResult, advance: s => now += s };
}

test('a family message is uploaded, queued, delivered and played, then kept as a record',async()=>{
  const f=await fixture();
  const created=await f.json('createMessage',{mode:'video',kind:'message',contentType:'video/quicktime',sizeBytes:5_000_000,durationSeconds:61.4},f.ethan.credential);
  assert.equal(created.upload.method,'PUT'); assert.equal(created.message.state,'uploading'); assert.equal(created.message.durationSeconds,61);
  assert.ok(!('pathname' in created.message));
  assert.deepEqual(f.media.signed.at(-1),{pathname:`messages/${f.bedside.state.householdID}/${created.message.id}.mov`,contentType:'video/quicktime',maximumSizeInBytes:5_000_000});
  assert.equal((await f.send('completeMessage',{messageID:created.message.id},f.ethan.credential)).status,409,'nothing was uploaded yet');
  assert.deepEqual(await f.queue(),[]);
  f.media.upload(created.upload,4_900_000);
  assert.equal((await f.json('completeMessage',{messageID:created.message.id},f.ethan.credential)).message.state,'queued');
  await f.json('completeMessage',{messageID:created.message.id},f.ethan.credential);
  const [queued]=await f.queue();
  assert.deepEqual({...queued,sentAt:undefined},{id:created.message.id,from:f.ethan.state.me.id,fromName:'Ethan',kind:'message',mode:'video',contentType:'video/quicktime',durationSeconds:61,sentAt:undefined,delivered:false,held:false});
  assert.ok(!JSON.stringify(await f.json('poll',{available:true},f.ethan.credential)).includes(created.message.id),'family snapshots carry no queue');
  assert.equal((await f.send('messageMedia',{messageID:queued.id},f.ethan.credential)).status,403);
  assert.match((await f.json('messageMedia',{messageID:queued.id},f.bedside.credential)).media.url,/^https:\/\/blob\.test\/get\//);
  await f.json('messageDelivered',{messageID:queued.id},f.bedside.credential);
  assert.equal((await f.queue())[0].delivered,true);
  assert.ok((await f.sent(f.ethan))[0].deliveredAt);
  await f.json('messagePlayed',{messageID:queued.id},f.bedside.credential);
  await f.json('messagePlayed',{messageID:queued.id},f.bedside.credential);
  assert.deepEqual(await f.queue(),[]);
  const [record]=await f.sent(f.ethan);
  assert.equal(record.state,'played'); assert.ok(record.playedAt);
  assert.equal((await f.send('unsendMessage',{messageID:queued.id},f.ethan.credential)).status,409);
  assert.deepEqual(await f.sent(f.sam),[],'senders only see their own messages');
  // Played media is purged after 90 days; the record stays.
  f.advance(89*day); await f.queue(); assert.deepEqual(f.media.removed,[]);
  f.advance(2*day); await f.queue();
  assert.deepEqual(f.media.removed,[`messages/${f.bedside.state.householdID}/${queued.id}.mov`]);
  assert.equal((await f.sent(f.ethan))[0].state,'played');
});

test('recordings are validated and each sender can only have ten waiting',async()=>{
  const f=await fixture();
  const create=(values,who=f.ethan)=>f.send('createMessage',{mode:'audio',contentType:'audio/mp4',sizeBytes:1000,durationSeconds:30,...values},who.credential);
  assert.equal((await create({contentType:'video/mp4'})).status,400);
  assert.equal((await create({mode:'video',contentType:'audio/mp4'})).status,400);
  assert.equal((await create({durationSeconds:126})).status,400);
  assert.equal((await create({sizeBytes:11*1024*1024})).status,413);
  assert.equal((await create({mode:'video',contentType:'video/mp4',sizeBytes:101*1024*1024})).status,413);
  assert.equal((await create({kind:'letter'})).status,400);
  assert.equal((await create({kind:'voicemail'},f.bedside)).status,404,'the bedside only leaves messages for a family member');
  for(let n=0;n<10;n++) await f.sendMessage(f.ethan);
  assert.equal((await create({})).status,409);
  assert.equal((await create({},f.sam)).status,200,'the limit is per sender');
  // A completed upload must match what was declared.
  const created=await f.json('createMessage',{mode:'video',contentType:'video/mp4',sizeBytes:1000,durationSeconds:10},f.sam.credential);
  f.media.blobs.set(`messages/${f.bedside.state.householdID}/${created.message.id}.mp4`,{size:1000,contentType:'audio/mp4'});
  assert.equal((await f.send('completeMessage',{messageID:created.message.id},f.sam.credential)).status,400);
  assert.equal((await f.send('completeMessage',{messageID:created.message.id},f.ethan.credential)).status,404,'only the sender completes');
});

test('senders can unsend before playback; abandoned uploads are shown as not sent',async()=>{
  const f=await fixture();
  const message=await f.sendMessage(f.ethan,{kind:'voicemail'});
  assert.equal((await f.queue())[0].kind,'voicemail');
  assert.equal((await f.json('unsendMessage',{messageID:message.id},f.ethan.credential)).message.state,'unsent');
  assert.deepEqual(await f.queue(),[]);
  assert.equal(f.media.removed.length,1);
  assert.equal((await f.sent(f.ethan))[0].state,'unsent');
  const abandoned=await f.json('createMessage',{mode:'audio',contentType:'audio/mp4',sizeBytes:1000,durationSeconds:5},f.ethan.credential);
  f.advance(3601);
  assert.equal((await f.sent(f.ethan))[0].state,'failed');
  assert.equal((await f.send('completeMessage',{messageID:abandoned.message.id},f.ethan.credential)).status,409);
});

test('unplayed messages expire after a week and their media is deleted',async()=>{
  const f=await fixture();
  const message=await f.sendMessage(f.ethan);
  f.advance(7*day-1); assert.equal((await f.queue()).length,1);
  f.advance(2);
  assert.deepEqual(await f.queue(),[]);
  assert.equal((await f.sent(f.ethan))[0].state,'expired');
  assert.deepEqual(f.media.removed,[`messages/${f.bedside.state.householdID}/${message.id}.m4a`]);
  assert.equal((await f.send('messageMedia',{messageID:message.id},f.bedside.credential)).status,404);
});

test('caregivers review and remove queued messages with the PIN, and can turn messages off',async()=>{
  const f=await fixture();
  const message=await f.sendMessage(f.ethan,{mode:'video',contentType:'video/mp4'});
  assert.equal((await f.send('removeMessage',{messageID:message.id},f.ethan.credential,'123456')).status,403,'not an approved caregiver');
  assert.equal((await f.send('caregiverMessageMedia',{messageID:message.id},f.sam.credential)).status,403,'PIN required');
  const unlocked=await f.json('verifyPIN',{},f.sam.credential,'123456');
  assert.deepEqual(unlocked.admin.messages.map(m=>[m.id,m.fromName]),[[message.id,'Ethan']]);
  assert.equal(unlocked.admin.messagesEnabled,true);
  assert.ok((await f.json('caregiverMessageMedia',{messageID:message.id},f.sam.credential,'123456')).media.url);
  assert.deepEqual((await f.json('removeMessage',{messageID:message.id},f.sam.credential,'123456')).admin.messages,[]);
  assert.deepEqual(await f.queue(),[]);
  assert.equal((await f.sent(f.ethan))[0].state,'removed');
  const off=await f.json('setMessages',{enabled:false},f.sam.credential,'123456');
  assert.equal(off.admin.messagesEnabled,false); assert.equal(off.state.messagesEnabled,false);
  assert.equal((await f.send('createMessage',{mode:'audio',contentType:'audio/mp4',sizeBytes:1000,durationSeconds:5},f.ethan.credential)).status,403);
  assert.equal((await f.json('poll',{available:true},f.ethan.credential)).state.messagesEnabled,false);
  await f.json('setMessages',{enabled:true},f.bedside.credential,'123456');
  await f.sendMessage(f.ethan);
});

test('removing a family member removes their unplayed messages',async()=>{
  const f=await fixture();
  await f.sendMessage(f.ethan); await f.sendMessage(f.sam);
  await f.json('revoke',{memberID:f.ethan.state.me.id},f.bedside.credential,'123456');
  assert.deepEqual((await f.queue()).map(m=>m.fromName),['Sam']);
});

test('the bedside leaves a message for one family member, who plays it and can play it again',async()=>{
  const f=await fixture();
  const token='ab'.repeat(32);
  assert.equal((await f.json('registerAlerts',{token,environment:'sandbox'},f.ethan.credential)).alertsReady,false,'APNs is not configured in tests');
  assert.equal(await f.unheard(f.ethan),0);
  const created=await f.json('createMessage',{mode:'video',kind:'voicemail',to:f.ethan.state.me.id,contentType:'video/quicktime',sizeBytes:2_000_000,durationSeconds:42.4},f.bedside.credential);
  assert.equal(created.message.state,'uploading');
  assert.equal(f.alerts.length,0);
  f.media.upload(created.upload,1_900_000);
  const sent=(await f.json('completeMessage',{messageID:created.message.id},f.bedside.credential)).message;
  assert.equal(sent.state,'queued');
  await f.json('completeMessage',{messageID:created.message.id},f.bedside.credential);
  assert.equal(f.alerts.length,1,'a retried completion notifies once');
  assert.deepEqual(f.alerts[0],{device:{token,environment:'sandbox'},alert:{messageID:sent.id,title:'Mom left you a message',body:'Video message · 0:42',badge:1}});
  assert.deepEqual(await f.queue(),[],'it never joins the bedside queue');
  assert.equal(await f.unheard(f.ethan),1); assert.equal(await f.unheard(f.sam),0);
  assert.equal((await f.json('poll',{available:true},f.bedside.credential)).state.newMessages,undefined);
  const [message]=await f.received(f.ethan);
  assert.deepEqual({...message,sentAt:undefined},{id:sent.id,fromName:'Mom',kind:'voicemail',mode:'video',durationSeconds:42,sentAt:undefined,state:'queued',available:true});
  assert.deepEqual(await f.received(f.sam),[],'only the person it was left for sees it');
  assert.equal((await f.send('receivedMessageMedia',{messageID:sent.id},f.sam.credential)).status,404);
  assert.equal((await f.send('receivedMessageMedia',{messageID:sent.id},f.bedside.credential)).status,403);
  assert.equal((await f.send('messageMedia',{messageID:sent.id},f.bedside.credential)).status,404);
  assert.match((await f.json('receivedMessageMedia',{messageID:sent.id},f.ethan.credential)).media.url,new RegExp(`${sent.id}\\.mov`));
  await f.json('receivedMessagePlayed',{messageID:sent.id},f.ethan.credential);
  await f.json('receivedMessagePlayed',{messageID:sent.id},f.ethan.credential);
  assert.equal(await f.unheard(f.ethan),0);
  const [played]=await f.received(f.ethan);
  assert.equal(played.state,'played'); assert.ok(played.playedAt); assert.equal(played.available,true);
  assert.ok((await f.json('receivedMessageMedia',{messageID:sent.id},f.ethan.credential)).media.url,'played messages can be played again');
  // Kept 90 days from sending, then deleted; the record stays.
  f.advance(90*day-1); await f.queue(); assert.deepEqual(f.media.removed,[]);
  f.advance(2); await f.queue();
  assert.deepEqual(f.media.removed,[`messages/${f.bedside.state.householdID}/${sent.id}.mov`]);
  assert.equal((await f.received(f.ethan))[0].available,false);
  assert.equal((await f.send('receivedMessageMedia',{messageID:sent.id},f.ethan.credential)).status,404);
});

test('an unplayed message from the bedside waits 90 days, and the household switch for messages to the bedside does not block it',async()=>{
  const f=await fixture();
  await f.json('setMessages',{enabled:false},f.bedside.credential,'123456');
  const message=await f.leaveMessage(f.ethan);
  assert.equal(f.alerts.length,0,'no notifications without a registration');
  f.advance(30*day);
  assert.equal(await f.unheard(f.ethan),1,'unlike the bedside queue, it does not expire after a week');
  f.advance(60*day+1); await f.queue();
  assert.equal(await f.unheard(f.ethan),0);
  assert.deepEqual((await f.received(f.ethan)).map(m=>[m.state,m.available]),[['expired',false]]);
  assert.deepEqual(f.media.removed,[`messages/${f.bedside.state.householdID}/${message.id}.m4a`]);
});

test('bedside messages need a current family member, count per person, and notify with the waiting count',async()=>{
  const f=await fixture();
  const create=(values,who=f.bedside)=>f.send('createMessage',{mode:'audio',kind:'voicemail',contentType:'audio/mp4',sizeBytes:1000,durationSeconds:5,...values},who.credential);
  assert.equal((await create({to:f.bedside.state.me.id})).status,404,'not to itself');
  assert.equal((await create({to:randomUUID()})).status,404);
  assert.equal((await create({to:f.ethan.state.me.id,kind:'message'})).status,400,'only voicemail');
  assert.equal((await create({to:f.sam.state.me.id},f.ethan)).status,200,'family devices still send to the bedside, ignoring `to`');
  await f.json('registerAlerts',{token:'cd'.repeat(32),environment:'production'},f.ethan.credential);
  for(let n=0;n<10;n++) await f.leaveMessage(f.ethan);
  assert.deepEqual(f.alerts.map(a=>a.alert.badge),[1,2,3,4,5,6,7,8,9,10]);
  assert.equal((await create({to:f.ethan.state.me.id})).status,409);
  assert.equal((await create({to:f.sam.state.me.id})).status,200,'the limit is per family member');
  // An invalid registration is dropped after APNs rejects it.
  f.alertResult.delivered=false; f.alertResult.invalidToken=true;
  const [newest,next]=await f.received(f.ethan);
  await f.json('receivedMessagePlayed',{messageID:newest.id},f.ethan.credential);
  await f.leaveMessage(f.ethan);
  assert.equal(f.alerts.length,11);
  await f.json('receivedMessagePlayed',{messageID:next.id},f.ethan.credential);
  await f.leaveMessage(f.ethan);
  assert.equal(f.alerts.length,11,'no further alerts after the token was rejected');
  // A message whose recipient lost access can't be completed.
  const pending=await f.json('createMessage',{mode:'audio',kind:'voicemail',to:f.sam.state.me.id,contentType:'audio/mp4',sizeBytes:1000,durationSeconds:5},f.bedside.credential);
  f.media.upload(pending.upload);
  await f.json('revoke',{memberID:f.sam.state.me.id},f.bedside.credential,'123456');
  assert.equal((await f.send('completeMessage',{messageID:pending.message.id},f.bedside.credential)).status,404);
});

test('removing or leaving deletes the messages the bedside left for that device',async()=>{
  const f=await fixture();
  const unplayed=await f.leaveMessage(f.ethan), played=await f.leaveMessage(f.ethan), kept=await f.leaveMessage(f.sam);
  await f.json('receivedMessagePlayed',{messageID:played.id},f.ethan.credential);
  await f.json('revoke',{memberID:f.ethan.state.me.id},f.bedside.credential,'123456');
  const house=`messages/${f.bedside.state.householdID}`;
  assert.deepEqual(f.media.removed.sort(),[`${house}/${unplayed.id}.m4a`,`${house}/${played.id}.m4a`].sort());
  assert.equal(await f.unheard(f.sam),1);
  await f.json('leaveHousehold',{},f.sam.credential);
  assert.ok(f.media.removed.includes(`${house}/${kept.id}.m4a`));
});
