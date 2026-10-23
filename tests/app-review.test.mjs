import assert from 'node:assert/strict';
import { test } from 'node:test';
import { prepareReviewAccess, reviewNotes, reviewOrigin } from '../scripts/prepare-app-review.mjs';

const origin = 'https://porch-calling-prototype.vercel.app';
const operatorSecret = 'private-operator-test-secret';
const now = 1_800_000_000;
const health = { ok: true, commit: 'a'.repeat(40), storageReachable: true, callingConfigured: true, pushConfigured: true };

function server({ healthBody = health, lifetime = 90 * 86400, duplicate = false } = {}) {
  const requests = [];
  const fetcher = async (url, options) => {
    requests.push({ url, options });
    assert.equal(options.redirect, 'error', 'operator credentials must never follow redirects');
    if (url.pathname === '/api/calls/health') return Response.json(healthBody);
    assert.equal(url.origin, origin);
    assert.equal(options.headers['X-Porch-Setup-Code'], operatorSecret);
    assert.deepEqual(JSON.parse(options.body), { action: 'createBedsideInvite', purpose: 'appReview' });
    return Response.json({ code: String(duplicate ? 1 : requests.length).padStart(64, '0'), expiresAt: now + lifetime });
  };
  return { requests, fetcher };
}

test('review pack contains distinct compatible activation links and private metadata under Apple limits', async () => {
  const f = server();
  const pack = await prepareReviewAccess({ origin, operatorSecret, fetcher: f.fetcher, now: () => now });
  assert.equal(f.requests.length, 4);
  assert.equal(pack.expiresAt, now + 90 * 86400);
  assert.equal(new Set(pack.activationLinks).size, 3);
  for (const text of pack.activationLinks) {
    const link = new URL(text);
    assert.equal(link.protocol, 'porch:'); assert.equal(link.hostname, 'activate');
    assert.equal(link.searchParams.get('server'), origin);
    assert.match(link.searchParams.get('code'), /^[a-f0-9]{64}$/);
    assert.ok(pack.reviewNotes.includes(text));
  }
  assert.ok(pack.reviewNotes.length <= 4000);
  assert.ok(pack.betaDescription.length <= 4000);
  assert.ok(!JSON.stringify(pack).includes(operatorSecret));
  assert.match(pack.status, /DRAFT/);
});

test('review pack fails closed on an older server, broken readiness or duplicated links', async () => {
  for (const options of [{ lifetime: 86400 }, { lifetime: 91 * 86400 }, { duplicate: true }, { healthBody: { ...health, pushConfigured: false } }, { healthBody: { ...health, commit: undefined } }]) {
    const f = server(options);
    await assert.rejects(prepareReviewAccess({ origin, operatorSecret, fetcher: f.fetcher, now: () => now }));
    if (options.healthBody) assert.equal(f.requests.length, 1, 'unready servers must not issue activations');
  }
});

test('review provisioning rejects credential-bearing URLs and missing operator credentials before network access', async () => {
  let calls = 0;
  const fetcher = async () => { calls++; throw new Error('unexpected request'); };
  for (const invalid of ['http://example.com', 'https://operator:secret@example.com', origin + '/api', origin + '?secret=x', origin + '#code']) {
    assert.throws(() => reviewOrigin(invalid));
    await assert.rejects(prepareReviewAccess({ origin: invalid, operatorSecret, fetcher }));
  }
  await assert.rejects(prepareReviewAccess({ origin, operatorSecret: '123456', fetcher }));
  assert.equal(calls, 0);
  assert.throws(() => reviewNotes(['x'.repeat(4001)], now));
});

test('review provisioning does not echo remote response bodies containing credentials', async () => {
  let calls = 0;
  const fetcher = async () => ++calls === 1 ? Response.json(health) : Response.json({ error: operatorSecret }, { status: 403 });
  await assert.rejects(prepareReviewAccess({ origin, operatorSecret, fetcher }), error => !error.message.includes(operatorSecret));
});
