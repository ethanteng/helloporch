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

test('a pilot family goes into the pilot group with the tablet they will use', async () => {
  const response = await signUp({ email: ' Ann@Example.com ', tablet: 'ipad' });
  assert.equal(response.status, 200);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, 'https://connect.mailerlite.com/api/subscribers');
  assert.equal(sent[0].init.headers.Authorization, 'Bearer test-key');
  assert.deepEqual(sent[0].body, {
    email: 'ann@example.com',
    fields: { porch_pilot_interface: 'big-button phone', porch_pilot_ipad: 'ipad' },
    groups: ['pilot-group'],
  });
});

test('every family calls with the corded phone, whichever tablet they choose', async () => {
  await signUp({ email: 'ann@example.com', tablet: 'android' });
  await signUp({ email: 'ann@example.com', tablet: 'unsure' });
  assert.deepEqual(
    sent.map((s) => s.body.fields),
    [
      { porch_pilot_interface: 'big-button phone', porch_pilot_ipad: 'android' },
      { porch_pilot_interface: 'big-button phone', porch_pilot_ipad: 'not sure' },
    ],
  );
});

test('without a pilot group, the family is still saved with their answer', async () => {
  delete process.env.MAILERLITE_PILOT_GROUP_ID;
  await signUp({ email: 'ann@example.com', tablet: 'android' });
  assert.deepEqual(sent[0].body, {
    email: 'ann@example.com',
    fields: { porch_pilot_interface: 'big-button phone', porch_pilot_ipad: 'android' },
  });
});

test('a sign-up without a real email or a tablet is refused before MailerLite', async () => {
  const complete = { email: 'ann@example.com', tablet: 'ipad' };
  for (const body of [
    { ...complete, email: 'not an email' },
    { email: 'ann@example.com' },
    { ...complete, tablet: 'phone' },
    { ...complete, tablet: 'toString' },
    { ...complete, tablet: true },
  ]) {
    assert.equal((await signUp(body)).status, 400, JSON.stringify(body));
  }
  assert.equal(sent.length, 0);
});

test('a MailerLite failure tells the family to try again', async () => {
  globalThis.fetch = async () => new Response('nope', { status: 500 });
  const response = await signUp({ email: 'ann@example.com', tablet: 'ipad' });
  assert.equal(response.status, 502);
  assert.match((await response.json()).error, /try again/);
});
