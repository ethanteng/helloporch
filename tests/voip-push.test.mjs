import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { createServer, connect } from 'node:http2';
import { test } from 'node:test';
import { apnsAuthorization, sendVoIPPush, voipConfigured } from '../lib/family/push.ts';

test('APNs provider JWT uses ES256/P1363 and refreshes before one hour without exposing the key',()=>{
 const keys=['APNS_KEY_ID','APNS_TEAM_ID','APNS_PRIVATE_KEY','APNS_BUNDLE_ID'];
 const previous=keys.map(key=>process.env[key]);
 try {
  const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  Object.assign(process.env,{APNS_KEY_ID:'test-key',APNS_TEAM_ID:'test-team',APNS_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString().replace(/\n/g,'\\n'),APNS_BUNDLE_ID:'com.example.porch'});
  assert.equal(voipConfigured(),true);
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
  assert.equal(voipConfigured(),false);
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
