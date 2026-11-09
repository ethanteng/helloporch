import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GET } from '../app/.well-known/apple-app-site-association/route.ts';
import { GET as getAssetLinks } from '../app/.well-known/assetlinks.json/route.ts';
import { androidCertificates, androidDevice, appLink, codeFromHash, inviteCode, inviteLink, porchServerOrigin } from '../lib/invite-links.ts';

const code = 'a'.repeat(64);

test("Apple's link file lets only the invitation pages open Porch", async () => {
  const response = GET();
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^application\/json/);
  const { applinks } = await response.json();
  assert.deepEqual(applinks.details.map(d => d.appIDs), [['7U9T57JPF7.com.ethanteng.helloporch']]);
  assert.deepEqual(applinks.details[0].components.map(c => c['/']), ['/join', '/setup']);
});

test("Android's link file names Porch's package and signing keys, and nothing without a key", async () => {
  const response = getAssetLinks();
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^application\/json/);
  assert.ok(androidCertificates.length > 0);
  for (const fingerprint of androidCertificates) assert.match(fingerprint, /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
  assert.deepEqual(await response.json(), [{ relation: ['delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name: 'com.ethanteng.helloporch', sha256_cert_fingerprints: androidCertificates } }]);
  const saved = androidCertificates.splice(0);
  try {
    assert.deepEqual(await getAssetLinks().json(), []);
  } finally { androidCertificates.push(...saved); }
});

test("an Android tablet is not called a phone when Chrome's user agent says Mobile", () => {
  const chrome = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36";
  assert.equal(androidDevice(chrome, false), "tablet");
  assert.equal(androidDevice(chrome, true), "phone");
  assert.equal(androidDevice(chrome), "phone", "without the client hint, Mobile is the only signal");
  assert.equal(androidDevice("Mozilla/5.0 (Linux; Android 13; SM-X710) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"), "tablet");
  assert.equal(androidDevice("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"), undefined);
});

test("invitations for Porch's own server are web links with the code after the #", () => {
  assert.equal(inviteLink('family', code), `https://helloporch.store/join#code=${code}`);
  assert.equal(inviteLink('bedside', code, `${porchServerOrigin}/`), `https://helloporch.store/setup#code=${code}`);
  // Any other server keeps the app's own form, which names it.
  assert.equal(inviteLink('bedside', code, 'http://localhost:3000'), `porch://activate?server=http%3A%2F%2Flocalhost%3A3000&code=${code}`);
  assert.equal(appLink('family', code), `porch://pair?server=${encodeURIComponent(porchServerOrigin)}&code=${code}`);
});

test("a page reads only a well-formed code from its link's #", () => {
  assert.equal(codeFromHash(`#code=${code}`), code);
  assert.equal(codeFromHash(`code=${code}`), code);
  for (const hash of ['', '#', '#code=short', `#code=${code.toUpperCase()}`, `#other=${code}`, `#code=${code}x`]) assert.equal(codeFromHash(hash), undefined, hash);
  assert.equal(inviteCode(42), undefined);
});
