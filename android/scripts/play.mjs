#!/usr/bin/env node
// Google Play's internal testing track, through the Google Play Developer API, for release.sh and the Android release
// workflow (android/README.md, "Release to Google Play"). No dependencies: it signs the service account's token itself.
//
//   node scripts/play.mjs next-version-code
//   node scripts/play.mjs upload app/build/outputs/bundle/release/app-release.aab --notes "What changed" [--verify-only]
//
// PLAY_SERVICE_ACCOUNT_JSON is a Google Cloud service account's key (its JSON), which the Play Console lets release to
// testing tracks. Nothing it holds is printed.
import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const packageName = 'com.ethanteng.helloporch';
const api = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`;
const uploads = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${packageName}`;
const track = 'internal';

function serviceAccount() {
  const raw = process.env.PLAY_SERVICE_ACCOUNT_JSON;
  if (!raw) throw new Error('PLAY_SERVICE_ACCOUNT_JSON is missing: a Google Cloud service account key with access in the Play Console.');
  let key;
  try { key = JSON.parse(raw); } catch { throw new Error("PLAY_SERVICE_ACCOUNT_JSON isn't JSON."); }
  if (key.type !== 'service_account' || !key.client_email || !key.private_key) throw new Error("PLAY_SERVICE_ACCOUNT_JSON isn't a service account key.");
  return key;
}

/** An access token for the Play Developer API, from a signed service account assertion. */
async function accessToken() {
  const key = serviceAccount();
  const audience = key.token_uri || 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({ iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher', aud: audience, iat: now, exp: now + 3600 })}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(key.private_key).toString('base64url');
  const response = await fetch(audience, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }) });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || !result.access_token) throw new Error(`Google didn't accept the service account (${response.status}${result.error ? `: ${result.error}` : ''}).`);
  return result.access_token;
}

/** One API call. Google's own message comes back on failure, such as a missing permission in the Play Console. */
async function call(token, method, url, { json, body, contentType } = {}) {
  const response = await fetch(url, { method, headers: { Authorization: `Bearer ${token}`,
    ...(json ? { 'Content-Type': 'application/json' } : contentType ? { 'Content-Type': contentType } : {}) },
    body: json ? JSON.stringify(json) : body });
  const text = await response.text();
  let result = {};
  try { result = text ? JSON.parse(text) : {}; } catch { /* not JSON */ }
  if (!response.ok) {
    const error = new Error(`${method} ${url.replace(/^https:\/\/[^/]+/, '')} -> ${response.status}: ${result.error?.message ?? text.slice(0, 300)}`);
    error.status = response.status;
    throw error;
  }
  return result;
}

/** Runs `work` in a Play Console edit, which changes nothing until it's committed. Without `commit`, the edit is thrown
 * away, after Play checks it when `validate`. */
async function inEdit(token, work, { commit, validate = true }) {
  const edit = await call(token, 'POST', `${api}/edits`, { json: {} });
  let done = false;
  try {
    const result = await work(edit.id);
    if (commit) {
      await commit(edit.id, result);
      done = true;
    } else if (validate) {
      await call(token, 'POST', `${api}/edits/${edit.id}:validate`);
    }
    return result;
  } finally {
    if (!done) await call(token, 'DELETE', `${api}/edits/${edit.id}`).catch(() => {});
  }
}

/** One more than the highest versionCode Play has for Porch, on any track: what the next bundle needs. */
async function nextVersionCode() {
  const token = await accessToken();
  return inEdit(token, async id => {
    const { bundles = [] } = await call(token, 'GET', `${api}/edits/${id}/bundles`);
    return Math.max(0, ...bundles.map(bundle => Number(bundle.versionCode) || 0)) + 1;
  }, { commit: undefined, validate: false });
}

/** Uploads `file` and releases it to internal testers, or with `verifyOnly` checks that Play would take it. */
async function upload(file, notes, verifyOnly) {
  const token = await accessToken();
  const bundle = readFileSync(file);
  const release = (versionCode, status) => ({ track, releases: [{ versionCodes: [String(versionCode)], status,
    ...(notes ? { releaseNotes: [{ language: 'en-US', text: notes.slice(0, 500) }] } : {}) }] });
  const commit = async (id, versionCode) => {
    try {
      await call(token, 'POST', `${api}/edits/${id}:commit`);
    } catch (error) {
      // An app that isn't published anywhere yet takes only draft releases, which are rolled out in the Play Console.
      if (!/draft/i.test(error.message)) throw error;
      await call(token, 'PUT', `${api}/edits/${id}/tracks/${track}`, { json: release(versionCode, 'draft') });
      await call(token, 'POST', `${api}/edits/${id}:commit`);
      console.log('Play took it as a draft. Roll it out from Internal testing in the Play Console.');
    }
  };
  const versionCode = await inEdit(token, async id => {
    const uploaded = await call(token, 'POST', `${uploads}/edits/${id}/bundles?uploadType=media`, { body: bundle, contentType: 'application/octet-stream' });
    await call(token, 'PUT', `${api}/edits/${id}/tracks/${track}`, { json: release(uploaded.versionCode, 'completed') });
    return uploaded.versionCode;
  }, { commit: verifyOnly ? undefined : commit });
  console.log(verifyOnly ? `Play would take versionCode ${versionCode} for internal testing. Nothing was uploaded.`
    : `Uploaded versionCode ${versionCode} to internal testing.`);
}

const [command, ...rest] = process.argv.slice(2);
const option = name => { const at = rest.indexOf(name); return at < 0 ? undefined : rest[at + 1]; };
try {
  if (command === 'next-version-code') console.log(await nextVersionCode());
  else if (command === 'upload' && rest[0] && !rest[0].startsWith('--')) await upload(rest[0], option('--notes'), rest.includes('--verify-only'));
  else throw new Error('Usage: play.mjs next-version-code | upload <bundle.aab> [--notes "What changed"] [--verify-only]');
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
