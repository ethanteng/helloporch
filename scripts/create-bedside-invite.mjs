// Run with node --env-file=.env.local scripts/create-bedside-invite.mjs [origin] [private-output-file].
import { writeFile } from 'node:fs/promises';
const origin = new URL(process.argv[2] ?? 'https://porch-calling-prototype.vercel.app');
if (origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password || !(origin.protocol === 'https:' || (origin.protocol === 'http:' && origin.hostname === 'localhost'))) throw new Error('Use your Porch server origin.');
const secret = process.env.PORCH_CONTACT_SETUP_CODE;
if (!secret || secret.length < 16) throw new Error('Load the private server recovery secret with --env-file. Never pass it as a command-line argument.');
const response = await fetch(new URL('/api/family', origin), { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Porch-Setup-Code': secret }, body: JSON.stringify({ action: 'createBedsideInvite' }) });
const data = await response.json();
if (!response.ok || !/^[a-f0-9]{64}$/.test(data.code ?? '')) throw new Error(data.error ?? 'Could not create an activation invitation.');
const link = new URL('porch://activate'); link.searchParams.set('server', origin.origin); link.searchParams.set('code', data.code);
const output = process.argv[3] ?? '.env.bedside-activation.local';
await writeFile(output, `# Private, one-use bedside activation. Expires ${new Date(data.expiresAt * 1000).toISOString()}.\nPORCH_BEDSIDE_ACTIVATION_URL=${link}\n`, { mode: 0o600, flag: 'wx' });
console.log(`Bedside activation saved privately to ${output}. The caregiver chooses the PIN in Porch. No calls placed.`);
