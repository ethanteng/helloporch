// Operator-only: node --env-file=.env.local scripts/prepare-app-review.mjs [origin]
// Writes private drafts to .app-review/. Never prints links or the recovery secret.
import { mkdir, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const betaDescription = `Porch helps people who find smartphones difficult stay connected with their family through a simple bedside display and large call buttons.

One app has two modes: a bedside clock with configurable contact buttons, and a family mode for iPhone or iPad. A caregiver pairs devices using private invitations, chooses a six-digit PIN, and manages contacts, names, photos, calling preferences and separately approved audio/video drop-in. Touchscreen controls work without an accessory; standard USB/Bluetooth keypads are optional. This family build does not include the Cell2Jack driver.

Test voice/video calls in both directions, incoming calls while a family phone is locked, caregiver permissions, drop-in announcements and cancellation, and audio/video messages in both directions. Phone fallback can call a caregiver-configured regular phone number. An internet connection is required. Porch is not an emergency calling or monitoring service.`;

export function reviewNotes(links, expiresAt) {
  const notes = `ACCESS FOR GUIDELINE 2.1(a)
Porch uses device invitations and a caregiver PIN instead of a username/password. The private activation links below grant setup of fresh test families, separate from our users. Each link works for one bedside device; use a backup for another install. They expire ${new Date(expiresAt * 1000).toISOString().slice(0, 10)}. Pairing then stays saved. No email, SMS, developer account or operator assistance is needed.

Use TWO devices running this build, ideally an iPad (bedside) and an iPhone (family). Either device can use either mode. No physical keypad, Cell2Jack or special accessory is required.

1. On the bedside device, open Porch, tap the gear. On iPhone, first choose gear > Use as the bedside Porch. Paste activation link 1 into Bedside activation link. Name it Review bedside. Choose and confirm your own six-digit PIN; keep it for caregiver settings. Tap Save PIN and continue.
2. In Caregiver mode > People, tap key 1 and keep Person. Enter Review family and tap Invite them. Share/copy the NEW family invitation to the second device, then Done and Save. Tap Review family on the keypad and set Calls start as to Video. The family invitation lasts 24 hours from creation; make a new one here if needed. Do not paste a bedside activation link into Join family.
3. On the second device, use family mode (on a fresh iPad: gear > Use this device as a family member). Tap Join a family, paste the family invitation, and Join family. The bedside contact links automatically. Return the bedside to its clock.
4. With both apps open, tap the bedside's Call someone > Review family; answer on the family device. Test video, mute, camera and hangup. Call the bedside back with Voice and Video. For background ringing, lock the family phone and call it from the bedside; answer, then open Porch for video.
5. At bedside gear > Drop-in, turn on Allow drop-ins, then in People open the Review family member and turn on Audio drop-in and Video drop-in. Return to the clock. On the family device test Audio/Video drop-in; the bedside announces the caller and offers Don't connect before its countdown completes. Caregiver screens do not auto-answer. Turn permissions off to verify access is removed.
6. On the family device, send a short test audio/video message, then play it at the bedside. Leave a bedside call unanswered and record a short message for the family device, then open it there. Use fictional names and your own test media. Edit profiles/photos, keypad actions and Display & voice to inspect other settings.
7. Optional phone fallback: edit key 1, enable Phone fallback and save a number YOU control. Leave Porch unanswered to test the fallback. Only dial a consenting test phone. No real customer's number is preloaded. End the call in Porch.

Private bedside activation links:
${links.map((link, index) => `${index + 1}. ${link}`).join('\n')}

If a link was already used on a different device, use the next backup. Keep the bedside open/unlocked for outgoing calls and drop-in. Allow microphone for voice and camera for video; camera stays off for voice calls. Phone/SIP fallback is voice only. This build excludes the optional Cell2Jack driver.`;
  if (notes.length > 4000) throw new Error('Review notes exceed App Store Connect’s 4,000-character limit.');
  return notes;
}

export function reviewOrigin(value) {
  const url = new URL(value);
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && url.hostname === 'localhost')) || url.pathname !== '/' || url.search || url.hash || url.username || url.password) {
    throw new Error('Use the HTTPS Porch calling-server origin, without a path or credentials.');
  }
  return url.origin;
}

export async function prepareReviewAccess({ origin, operatorSecret, fetcher = fetch, now = () => Math.floor(Date.now() / 1000) }) {
  origin = reviewOrigin(origin);
  if (typeof operatorSecret !== 'string' || operatorSecret.length < 16) throw new Error('Load PORCH_CONTACT_SETUP_CODE privately using --env-file, never a command-line argument.');
  const healthResponse = await fetcher(new URL('/api/calls/health', origin), { redirect: 'error', cache: 'no-store', signal: AbortSignal.timeout(15000) });
  if (!healthResponse.ok) throw new Error('Calling server is not ready; do not submit for review.');
  const health = await healthResponse.json();
  if (health.ok !== true || health.storageReachable !== true || health.callingConfigured !== true || health.pushConfigured !== true || !/^[a-f0-9]{40}$/.test(health.commit ?? '')) {
    throw new Error('Calling server configuration, storage, push or release identity is not ready.');
  }
  const links = [], expirations = [];
  // One setup plus two backups. Keep another pack for QA so review links stay unused.
  for (let index = 0; index < 3; index++) {
    const issuedAt = now();
    const response = await fetcher(new URL('/api/family', origin), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { 'Content-Type': 'application/json', 'X-Porch-Setup-Code': operatorSecret },
      body: JSON.stringify({ action: 'createBedsideInvite', purpose: 'appReview' }),
    });
    if (!response.ok) throw new Error('Could not issue App Review access. Check operator authorization privately.');
    const data = await response.json();
    // Older servers ignore unknown fields and issue a 24-hour link. Never label
    // one of those as review-ready; deploy the server change before running this.
    if (!/^[a-f0-9]{64}$/.test(data.code ?? '') || !Number.isSafeInteger(data.expiresAt) || data.expiresAt < issuedAt + 89 * 86400 || data.expiresAt > now() + 90 * 86400 + 60) {
      throw new Error('Server did not issue a 90-day review activation. Deploy the review-access change first.');
    }
    const link = new URL('porch://activate');
    link.searchParams.set('server', origin); link.searchParams.set('code', data.code);
    if (links.includes(link.href)) throw new Error('Server returned a duplicate activation. Do not share this pack.');
    links.push(link.href); expirations.push(data.expiresAt);
  }
  const expiresAt = Math.min(...expirations);
  return { origin, commit: health.commit, expiresAt, activationLinks: links, reviewNotes: reviewNotes(links, expiresAt), betaDescription,
    status: 'DRAFT: complete two-device QA with a separate activation pack before sharing with Apple' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const origin = reviewOrigin(process.argv[2] ?? 'https://porch-calling-prototype.vercel.app');
    // Exclusive directory creation avoids overwriting or following a prior output symlink.
    // Move a QA pack somewhere private before generating the final review pack.
    await mkdir('.app-review', { mode: 0o700 });
    const pack = await prepareReviewAccess({ origin, operatorSecret: process.env.PORCH_CONTACT_SETUP_CODE });
    for (const [file, content] of [['access.json', JSON.stringify(pack, null, 2)], ['review-notes.txt', pack.reviewNotes], ['beta-description.txt', pack.betaDescription]]) {
      await writeFile(`.app-review/${file}`, content + '\n', { mode: 0o600, flag: 'wx' });
    }
    console.log('Private access pack and metadata drafts saved to .app-review/. Nothing sent to Apple; no calls placed. Complete two-device QA before submission.');
  } catch {
    // Network/library errors may include request details. Keep secrets out of logs.
    console.error('Review pack was not completed. Check the server release, operator environment and private .app-review/ output directory. Do not submit an incomplete pack.');
    process.exitCode = 1;
  }
}
