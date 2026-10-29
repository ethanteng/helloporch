import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GET } from '../app/.well-known/apple-app-site-association/route.ts';
import { appLink, codeFromHash, inviteCode, inviteLink, porchServerOrigin } from '../lib/invite-links.ts';

const code = 'a'.repeat(64);

test("Apple's link file lets only the invitation pages open Porch", async () => {
  const response = GET();
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^application\/json/);
  const { applinks } = await response.json();
  assert.deepEqual(applinks.details.map(d => d.appIDs), [['7U9T57JPF7.com.ethanteng.helloporch']]);
  assert.deepEqual(applinks.details[0].components.map(c => c['/']), ['/join', '/setup']);
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
