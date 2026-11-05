import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';
import { POST } from '../app/api/pilot/route.ts';

const realFetch = globalThis.fetch;
const realLog = console.log;
const realWarn = console.warn;
const realError = console.error;
let sent;

function signUp(body) {
  return POST(new Request('https://helloporch.store/api/pilot', { method: 'POST', body: JSON.stringify(body) }));
}

beforeEach(() => {
  sent = [];
  process.env.MAILERLITE_API_KEY = 'test-key';
  process.env.MAILERLITE_PILOT_GROUP_ID = 'pilot-group';
  globalThis.fetch = async (url, init) => {
    sent.push({ url, init, body: JSON.parse(init.body) });
    return new Response('{}', { status: 200 });
  };
  console.log = () => {};
  // BotID warns that it calls everyone human outside Vercel (tests/signup-guard.test.mjs checks it).
  console.warn = () => {};
  console.error = () => {};
});

afterEach(() => {
  globalThis.fetch = realFetch;
  console.log = realLog;
  console.warn = realWarn;
  console.error = realError;
  delete process.env.MAILERLITE_API_KEY;
  delete process.env.MAILERLITE_PILOT_GROUP_ID;
});

test('a pilot family goes into the pilot group with just their email', async () => {
  const response = await signUp({ email: ' Ann@Example.com ' });
  assert.equal(response.status, 200);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, 'https://connect.mailerlite.com/api/subscribers');
  assert.equal(sent[0].init.headers.Authorization, 'Bearer test-key');
  assert.deepEqual(sent[0].body, {
    email: 'ann@example.com',
    fields: { porch_pilot_interface: 'big-button phone' },
    groups: ['pilot-group'],
  });
});

test('without a pilot group, the family is still saved', async () => {
  delete process.env.MAILERLITE_PILOT_GROUP_ID;
  await signUp({ email: 'ann@example.com' });
  assert.deepEqual(sent[0].body, { email: 'ann@example.com', fields: { porch_pilot_interface: 'big-button phone' } });
});

test('a sign-up without a real email is refused before MailerLite', async () => {
  for (const body of [{ email: 'not an email' }, {}, { email: 42 }, { email: `${'a'.repeat(250)}@example.com` }]) {
    assert.equal((await signUp(body)).status, 400, JSON.stringify(body));
  }
  assert.equal(sent.length, 0);
});

test('a MailerLite failure tells the family to try again', async () => {
  globalThis.fetch = async () => new Response('nope', { status: 500 });
  const response = await signUp({ email: 'ann@example.com' });
  assert.equal(response.status, 502);
  assert.match((await response.json()).error, /try again/);
});
