import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { createServer, connect } from 'node:http2';
import { test } from 'node:test';
import { apnsAuthorization, apnsConfigured, fcmAssertion, fcmConfigured, forgetRegistration, pushConfigured, sameRegistration, sendAlertPush, sendVoIPPush } from '../lib/family/push.ts';

test('APNs provider JWT uses ES256/P1363 and refreshes before one hour without exposing the key',()=>{
 const keys=['APNS_KEY_ID','APNS_TEAM_ID','APNS_PRIVATE_KEY','APNS_BUNDLE_ID'];
 const previous=keys.map(key=>process.env[key]);
 try {
  const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  Object.assign(process.env,{APNS_KEY_ID:'test-key',APNS_TEAM_ID:'test-team',APNS_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString().replace(/\n/g,'\\n'),APNS_BUNDLE_ID:'com.example.porch'});
  assert.equal(apnsConfigured(),true);
  const jwt=apnsAuthorization(1800000000),[header,payload,signature]=jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header,'base64url')),{alg:'ES256',kid:'test-key'});
  assert.deepEqual(JSON.parse(Buffer.from(payload,'base64url')),{iss:'test-team',iat:1800000000});
  assert.equal(Buffer.from(signature,'base64url').length,64);
  assert.ok(verify('sha256',Buffer.from(`${header}.${payload}`),{key:publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(signature,'base64url')));
  assert.equal(apnsAuthorization(1800000200),jwt);
  assert.notEqual(apnsAuthorization(1800003001),jwt);
  process.env.APNS_KEY_ID='rotated-key';assert.notEqual(apnsAuthorization(1800003002),jwt);
 } finally {keys.forEach((key,i)=>previous[i]===undefined?delete process.env[key]:process.env[key]=previous[i]);}
});

test('an unconfigured APNs sender fails closed without making an outgoing request',async()=>{
 const previous=process.env.APNS_PRIVATE_KEY;
 try {
  delete process.env.APNS_PRIVATE_KEY;
  assert.equal(apnsConfigured(),false);
  assert.deepEqual(await sendVoIPPush({token:'ab'.repeat(32),environment:'production'},{callID:'test',recipientID:'test',callerName:'Test',mode:'voice',expiresAt:0}),{delivered:false});
 } finally {if(previous!==undefined)process.env.APNS_PRIVATE_KEY=previous;}
});


test('VoIP sender uses APNs call headers and handles success and invalid registrations',async()=>{
 const keys=['APNS_KEY_ID','APNS_TEAM_ID','APNS_PRIVATE_KEY','APNS_BUNDLE_ID'];
 const previous=keys.map(key=>process.env[key]);
 const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 const server=createServer(),received=[];
 let status=200, reason='';
 server.on('stream',(stream,headers)=>{
  let body=''; stream.on('data',chunk=>body+=chunk);
  stream.on('end',()=>{
   received.push({headers,body:JSON.parse(body)});
   stream.respond({':status':status});stream.end(status===200?'':JSON.stringify({reason}));
  });
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 try {
  Object.assign(process.env,{APNS_KEY_ID:'test',APNS_TEAM_ID:'team',APNS_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString(),APNS_BUNDLE_ID:'com.example.porch'});
  const session=()=>connect(`http://127.0.0.1:${server.address().port}`);
  const device={token:'ab'.repeat(32),environment:'production'},call={callID:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',recipientID:'family',callerName:'Mom',mode:'voice',expiresAt:1800000000};
  assert.equal((await sendVoIPPush(device,call,session)).delivered,true);
  const {headers,body}=received[0];
  assert.equal(headers[':path'],`/3/device/${device.token}`);
  assert.equal(headers['apns-topic'],'com.example.porch.voip');
  assert.equal(headers['apns-push-type'],'voip');assert.equal(headers['apns-priority'],'10');assert.equal(headers['apns-expiration'],'0');
  assert.equal(headers['apns-id'],call.callID);assert.match(headers.authorization,/^bearer /);
  assert.deepEqual(body,{aps:{},...call});
  status=410;reason='Unregistered';assert.equal((await sendVoIPPush(device,call,session)).invalidToken,true);
  status=400;reason='BadDeviceToken';assert.equal((await sendVoIPPush(device,call,session)).invalidToken,true);
  status=403;reason='InvalidProviderToken';const failed=await sendVoIPPush(device,call,session);assert.equal(failed.delivered,false);assert.equal(failed.invalidToken,false);
 } finally {
  server.closeAllConnections?.(); await new Promise(resolve=>server.close(resolve));
  keys.forEach((key,i)=>previous[i]===undefined?delete process.env[key]:process.env[key]=previous[i]);
 }
});

test('message alerts are ordinary notifications for the app, kept by APNs for a week',async()=>{
 const keys=['APNS_KEY_ID','APNS_TEAM_ID','APNS_PRIVATE_KEY','APNS_BUNDLE_ID'];
 const previous=keys.map(key=>process.env[key]);
 const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
 const server=createServer(),received=[];
 server.on('stream',(stream,headers)=>{
  let body=''; stream.on('data',chunk=>body+=chunk);
  stream.on('end',()=>{ received.push({headers,body:JSON.parse(body)}); stream.respond({':status':200}); stream.end(); });
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 try {
  assert.deepEqual(await sendAlertPush({token:'ab'.repeat(32),environment:'production'},{messageID:'x',recipientID:'r',title:'t',body:'b',badge:1}),{delivered:false},'unconfigured');
  Object.assign(process.env,{APNS_KEY_ID:'test',APNS_TEAM_ID:'team',APNS_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString(),APNS_BUNDLE_ID:'com.example.porch'});
  const session=()=>connect(`http://127.0.0.1:${server.address().port}`);
  const alert={messageID:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',recipientID:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',title:'Mom left you a message',body:'Audio message · 0:12',badge:2};
  assert.equal((await sendAlertPush({token:'cd'.repeat(32),environment:'sandbox'},alert,session,1800000000)).delivered,true);
  const {headers,body}=received[0];
  assert.equal(headers['apns-topic'],'com.example.porch');
  assert.equal(headers['apns-push-type'],'alert'); assert.equal(headers['apns-priority'],'10');
  assert.equal(headers['apns-expiration'],String(1800000000+7*86400)); assert.equal(headers['apns-id'],alert.messageID);
  // A phone in several families opens the right family's thread, and groups each family's messages apart.
  assert.deepEqual(body,{aps:{alert:{title:alert.title,body:alert.body},sound:'default',badge:2,'thread-id':`porch-messages-${alert.recipientID}`},messageID:alert.messageID,recipientID:alert.recipientID});
 } finally {
  server.closeAllConnections?.(); await new Promise(resolve=>server.close(resolve));
  keys.forEach((key,i)=>previous[i]===undefined?delete process.env[key]:process.env[key]=previous[i]);
 }
});

// Firebase Cloud Messaging for Android. A fake fetch stands in for Google: tests never contact it.
const fcmKeys=['FCM_PROJECT_ID','FCM_CLIENT_EMAIL','FCM_PRIVATE_KEY'];
const apnsKeys=['APNS_KEY_ID','APNS_TEAM_ID','APNS_PRIVATE_KEY','APNS_BUNDLE_ID'];
async function withFCM(run){
 const keys=[...fcmKeys,...apnsKeys],previous=keys.map(key=>process.env[key]);
 const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
 try {
  for (const key of apnsKeys) delete process.env[key];
  Object.assign(process.env,{FCM_PROJECT_ID:'porch-test',FCM_CLIENT_EMAIL:'push@porch-test.iam.gserviceaccount.com',FCM_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString().replace(/\n/g,'\\n')});
  await run(publicKey);
 } finally {keys.forEach((key,i)=>previous[i]===undefined?delete process.env[key]:process.env[key]=previous[i]);}
}
function fakeGoogle(){
 const requests=[];let reply=()=>Response.json({name:'projects/porch-test/messages/1'});
 const request=async(url,options)=>{
  requests.push({url:String(url),options});
  if (String(url)==='https://oauth2.googleapis.com/token') return Response.json({access_token:'test-access-token',expires_in:3599,token_type:'Bearer'});
  return reply();
 };
 return {requests,request,sends:()=>requests.filter(r=>r.url.startsWith('https://fcm.googleapis.com/')),reply:next=>{reply=next;}};
}
const android={token:'fcm-token:'+'a1_-'.repeat(30),platform:'android'};
const call={callID:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',recipientID:'family',callerName:'Mom',mode:'video',expiresAt:1800000045};

test('the FCM service-account assertion is RS256 for the messaging scope and signs with the configured key',()=>withFCM(publicKey=>{
 assert.equal(fcmConfigured(),true);
 const [header,payload,signature]=fcmAssertion(1800000000).split('.');
 assert.deepEqual(JSON.parse(Buffer.from(header,'base64url')),{alg:'RS256',typ:'JWT'});
 assert.deepEqual(JSON.parse(Buffer.from(payload,'base64url')),{iss:'push@porch-test.iam.gserviceaccount.com',scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:1800000000,exp:1800003600});
 assert.ok(verify('sha256',Buffer.from(`${header}.${payload}`),publicKey,Buffer.from(signature,'base64url')));
}));

test('Android call pushes are high-priority data messages that stop with the ringing, and reuse one access token',()=>withFCM(async()=>{
 const google=fakeGoogle();
 assert.deepEqual(await sendVoIPPush(android,call,undefined,1800000000,google.request),{delivered:true,invalidToken:false});
 assert.equal((await sendVoIPPush(android,call,undefined,1800000010,google.request)).delivered,true);
 assert.equal(google.requests.filter(r=>r.url.includes('oauth2')).length,1,'the access token is cached');
 const exchange=new URLSearchParams(String(google.requests[0].options.body));
 assert.equal(exchange.get('grant_type'),'urn:ietf:params:oauth:grant-type:jwt-bearer');
 const [send]=google.sends();
 assert.equal(send.url,'https://fcm.googleapis.com/v1/projects/porch-test/messages:send');
 assert.equal(send.options.headers.authorization,'Bearer test-access-token');
 // Every value is a string, as FCM requires, and there's no notification: the app shows the call itself.
 assert.deepEqual(JSON.parse(send.options.body),{message:{token:android.token,
  data:{type:'call',callID:call.callID,recipientID:'family',callerName:'Mom',mode:'video',expiresAt:'1800000045'},
  android:{priority:'HIGH',ttl:'45s'}}});
 await sendVoIPPush(android,{...call,expiresAt:1799999990},undefined,1800000000,google.request);
 assert.equal(JSON.parse(google.sends().at(-1).options.body).message.android.ttl,'0s','a call that already stopped ringing is now or never');
}));

test('FCM reports unregistered and invalid tokens, but not its own failures, as invalid registrations',()=>withFCM(async()=>{
 const google=fakeGoogle();
 const fcmError=(status,code,details=[],message='test')=>()=>Response.json({error:{code:status,status:code,message,details}},{status});
 const unregistered=[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:'UNREGISTERED'}];
 const badToken=[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:'INVALID_ARGUMENT'},{'@type':'type.googleapis.com/google.rpc.BadRequest',fieldViolations:[{field:'message.token',description:'The registration token is not a valid FCM registration token'}]}];
 const documentedBadToken=[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:'INVALID_ARGUMENT'}];
 for (const [reply,invalidToken] of [[fcmError(404,'NOT_FOUND',unregistered),true],[fcmError(400,'INVALID_ARGUMENT',badToken),true],
  [fcmError(400,'INVALID_ARGUMENT',documentedBadToken,'The registration token is not a valid FCM registration token'),true],
  [fcmError(403,'PERMISSION_DENIED',[{errorCode:'SENDER_ID_MISMATCH'}]),true],[fcmError(400,'INVALID_ARGUMENT',[{errorCode:'INVALID_ARGUMENT'}]),false],[fcmError(404,'NOT_FOUND'),false],
  [fcmError(429,'RESOURCE_EXHAUSTED',[{errorCode:'QUOTA_EXCEEDED'}]),false],[fcmError(503,'UNAVAILABLE'),false],[()=>new Response('not json',{status:500}),false]]) {
  google.reply(reply);
  assert.deepEqual(await sendVoIPPush(android,call,undefined,1800000000,google.request),{delivered:false,invalidToken});
 }
 google.reply(()=>{throw new TypeError('fetch failed');});
 assert.deepEqual(await sendVoIPPush(android,call,undefined,1800000000,google.request),{delivered:false},'a network error never throws');
}));

test('a rejected access token is fetched again once before the push fails',()=>withFCM(async()=>{
 const google=fakeGoogle();let rejections=1;
 google.reply(()=>rejections-->0?Response.json({error:{code:401,status:'UNAUTHENTICATED',message:'Request had invalid authentication credentials.'}},{status:401}):Response.json({name:'projects/porch-test/messages/2'}));
 assert.deepEqual(await sendVoIPPush(android,call,undefined,1800000000,google.request),{delivered:true,invalidToken:false});
 assert.equal(google.requests.filter(r=>r.url.includes('oauth2')).length,2,'signed in again');
 assert.equal(google.sends().length,2);
 rejections=Infinity;
 assert.deepEqual(await sendVoIPPush(android,call,undefined,1800000000,google.request),{delivered:false,invalidToken:false},'a token rejected twice fails closed, keeping the device');
 assert.equal(google.sends().length,4,'never more than one retry');
}));

test('a failed Google sign-in fails the push closed without sending it',()=>withFCM(async()=>{
 const requests=[];
 const request=async url=>{requests.push(String(url));return Response.json({error:'invalid_grant'},{status:400});};
 assert.deepEqual(await sendAlertPush(android,{messageID:'m',recipientID:'r',title:'t',body:'b',badge:1},undefined,1900000000,request),{delivered:false});
 assert.deepEqual(requests,['https://oauth2.googleapis.com/token']);
}));

test('Android message alerts are notifications on the messages channel, one per family, kept for a week',()=>withFCM(async()=>{
 const google=fakeGoogle();
 const alert={messageID:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',recipientID:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',title:'Mom left you a message',body:'Audio message · 0:12',badge:2};
 assert.equal((await sendAlertPush(android,alert,undefined,1800000000,google.request)).delivered,true);
 assert.deepEqual(JSON.parse(google.sends()[0].options.body),{message:{token:android.token,
  data:{type:'message',messageID:alert.messageID,recipientID:alert.recipientID,badge:'2'},
  android:{priority:'HIGH',ttl:'604800s',notification:{title:alert.title,body:alert.body,channel_id:'messages',sound:'default',tag:`porch-messages-${alert.recipientID}`,notification_count:2}}}});
}));

test('each platform pushes only when its own sender is set up',()=>withFCM(async()=>{
 const google=fakeGoogle(),ios={token:'ab'.repeat(32),environment:'production'};
 assert.equal(pushConfigured(android),true);assert.equal(pushConfigured(ios),false);assert.equal(pushConfigured(undefined),false);
 assert.deepEqual(await sendVoIPPush(ios,call,()=>{throw new Error('APNs must not be contacted');},1800000000,google.request),{delivered:false});
 delete process.env.FCM_PRIVATE_KEY;
 assert.equal(pushConfigured(android),false);
 assert.deepEqual(await sendVoIPPush(android,call,undefined,1800000000,google.request),{delivered:false});
 assert.deepEqual(google.requests,[],'an unconfigured sender makes no request');
}));

test("a rejected token is forgotten for calls and alerts alike, but an iPhone's other token stays",()=>{
 const phone={voip:{...android},alerts:{...android}};
 forgetRegistration(phone,android);
 assert.deepEqual(phone,{},'one FCM token serves both');
 const iphone={voip:{token:'ab'.repeat(32),environment:'production'},alerts:{token:'cd'.repeat(32),environment:'production'}};
 forgetRegistration(iphone,{token:'ab'.repeat(32),environment:'production'});
 assert.deepEqual(iphone,{alerts:{token:'cd'.repeat(32),environment:'production'}});
});

test('cleanups compare the push service as well as the token',()=>{
 const ios={token:'ab'.repeat(32),environment:'production'};
 assert.equal(sameRegistration(ios,{...ios}),true);
 assert.equal(sameRegistration(ios,{...ios,environment:'sandbox'}),false);
 assert.equal(sameRegistration({token:ios.token,platform:'android'},ios),false);
 assert.equal(sameRegistration(android,{...android}),true);
 assert.equal(sameRegistration(undefined,android),false);
});
