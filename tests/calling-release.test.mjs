import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { test } from 'node:test';
import { callingHealth } from '../lib/calls/health.ts';
import { verifyCallingDeployment, vercelHealthFetcher } from '../scripts/verify-calling-deployment.mjs';

const commit = 'a'.repeat(40);
const healthy = { ok: true, commit, callingConfigured: true, storageReachable: true, pushConfigured: true };

test('release health verifies configuration and a read-only storage operation without exposing credentials', async () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'private-livekit-secret', APNS_KEY_ID: 'test-key', APNS_TEAM_ID: 'test-team', APNS_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(), APNS_BUNDLE_ID: 'com.example.porch', PORCH_DEPLOYMENT_COMMIT: commit };
  const previous = Object.fromEntries(Object.keys(env).map(key => [key, process.env[key]]));
  const reads = [];
  try {
    Object.assign(process.env, env);
    const store = { get: async key => { reads.push(key); return null; } };
    const response = await callingHealth(store);
    assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), healthy); assert.deepEqual(reads, ['release-health']);
    assert.equal((await callingHealth({ get: async () => { throw new Error('private-storage-secret'); } })).status, 503);
    delete process.env.APNS_PRIVATE_KEY;
    const failed = await callingHealth(store);
    assert.equal(failed.status, 503); assert.equal((await failed.text()).includes('private-'), false);
    process.env.APNS_PRIVATE_KEY = env.APNS_PRIVATE_KEY;
    process.env.PORCH_DEPLOYMENT_COMMIT = 'not-a-commit';
    assert.equal((await callingHealth(store)).status, 503);
  } finally {
    for (const [key, value] of Object.entries(previous)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});

test('release verification waits for the expected commit and fully ready configuration', async () => {
  const responses = [new Response('', { status: 503 }), Response.json({ ...healthy, commit: 'b'.repeat(40) }), Response.json({ ...healthy, pushConfigured: false }), Response.json(healthy)];
  let calls = 0, pauses = 0;
  await verifyCallingDeployment({ origin: 'https://calling.example', commit, attempts: 4, pause: async () => pauses++, fetcher: async (url, options) => {
    assert.equal(url.href, 'https://calling.example/api/calls/health'); assert.equal(options.redirect, 'error');
    return responses[calls++];
  } });
  assert.equal(calls, 4); assert.equal(pauses, 3);
});

test('a stale deployment, a login page, and a redirect cannot pass the release gate', async () => {
  for (const fetcher of [async () => Response.json({ ...healthy, commit: 'b'.repeat(40) }), async () => new Response('<html>Log in</html>'), async () => { throw Error('redirect'); }]) {
    await assert.rejects(verifyCallingDeployment({ origin: 'https://calling.example', commit, attempts: 1, fetcher }), /verification failed/);
  }
});

test('authenticated CLI checks use only the Vercel health endpoint without token arguments or redirects', async () => {
  const calls = [];
  const fetcher = vercelHealthFetcher(async (...args) => { calls.push(args); return { stdout: JSON.stringify(healthy) }; });
  await assert.rejects(fetcher(new URL('https://unrelated.example/api/calls/health')), /restricted/);
  await assert.rejects(fetcher(new URL('https://calling.vercel.app/api/other')), /restricted/);
  assert.equal(calls.length, 0);
  await verifyCallingDeployment({ origin: 'https://calling.vercel.app', commit, fetcher });
  assert.deepEqual(calls[0][0], 'vercel');
  assert.deepEqual(calls[0][1], ['curl', 'https://calling.vercel.app/api/calls/health', '--silent', '--show-error', '--fail', '--max-time', '15']);
  await assert.rejects(verifyCallingDeployment({ origin: 'http://calling.vercel.app', commit, fetcher }), /HTTPS/);
});
