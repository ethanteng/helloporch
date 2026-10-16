// Synthetic devices for local simulator verification. Credentials stay in private files.
import { randomUUID, randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
const base = process.argv[2];
const output = process.argv[3];
if (!base?.startsWith('http://localhost:') || !output) throw new Error('Usage: node --env-file=.env.local scripts/seed-family-preview.mjs http://localhost:PORT /private/output/folder');
if (!process.env.PORCH_FAMILY_STORE_PREFIX?.startsWith('porch:family:preview:')) throw new Error('Set an isolated porch:family:preview: store prefix before seeding.');
const admin=process.env.PORCH_CONTACT_SETUP_CODE;
const send=async(action,values={},credential,pin=admin)=>{
 const response=await fetch(base+'/api/family',{method:'POST',headers:{'Content-Type':'application/json',...(credential?{Authorization:`Bearer ${credential}`} :{}),...(pin?{'X-Porch-Setup-Code':pin}:{})},body:JSON.stringify({action,...values})});
 const body=await response.json(); if(!response.ok) throw new Error(body.error??`Request failed ${response.status}`); return body;
};
const registration=()=>({deviceID:randomUUID(),deviceSecret:randomBytes(32).toString('hex')});
await send('setCaregiverPIN',{pin:'246810'});
const bedside=await send('createHousehold',{name:'Mom',...registration()});
const invitation=await send('createInvite',{name:'Ethan',permissions:{audio:true,video:true}},bedside.credential);
const family=await send('claimInvite',{code:invitation.code,...registration()});
await send('setDropIn',{enabled:true},bedside.credential);
await mkdir(output,{recursive:true,mode:0o700});
for (const [role,profile] of [['bedside',bedside],['family',family]]) {
 await writeFile(`${output}/${role}.json`,JSON.stringify({profile:{origin:base,credential:profile.credential,role},pin:role==='bedside'?'246810':undefined}),{mode:0o600});
}
console.log('Synthetic family paired. Private simulator fixtures written. No calls placed.');
