import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';
import { POST as pilot } from '../app/api/pilot/route.ts';
import { POST as waitlist } from '../app/api/waitlist/route.ts';

const realFetch = globalThis.fetch;
const realLog = console.log;
const realWarn = console.warn;
const realError = console.error;
// How Vercel hands checkBotId the request it's checking.
const requestContext = Symbol.for('@vercel/request-context');
let saved;
let logs;
let botVerdict;

const routes = [
  { name: 'pilot', POST: pilot, body: { email: 'ann@example.com', interface: 'keypad', ipad: true } },
  { name: 'waitlist', POST: waitlist, body: { email: 'ann@example.com' } },
];

function send(route, body) {
  return route.POST(new Request(`https://helloporch.store/api/${route.name}`, { method: 'POST', body: JSON.stringify(body) }));
}

// Runs checkBotId as it runs on Vercel, where it asks Vercel about the request.
function deployed(isBot) {
  process.env.NODE_ENV = 'production';
  process.env.VERCEL_OIDC_TOKEN = 'test-oidc';
  botVerdict = { isBot, isVerifiedBot: false };
  globalThis[requestContext] = {
    get: () => ({ headers: { host: 'helloporch.store', 'x-is-human': 'proof' }, url: 'https://helloporch.store/api/pilot', mutateResponseHeadersBeforeFlush() {} }),
  };
}

beforeEach(() => {
  saved = [];
  logs = [];
  botVerdict = null;
  process.env.MAILERLITE_API_KEY = 'test-key';
  globalThis.fetch = async (url, init) => {
    if (String(url).startsWith('https://api.vercel.com/bot-protection/')) return Response.json(botVerdict);
    saved.push(JSON.parse(init.body));
    return new Response('{}', { status: 200 });
  };
  console.log = (line) => logs.push(JSON.parse(line));
  console.warn = () => {};
  console.error = () => {};
});

afterEach(() => {
  globalThis.fetch = realFetch;
  console.log = realLog;
  console.warn = realWarn;
  console.error = realError;
  delete process.env.MAILERLITE_API_KEY;
  delete process.env.NODE_ENV;
  delete process.env.VERCEL_OIDC_TOKEN;
  delete globalThis[requestContext];
});

test('waitlist: answering who is saved when the hidden field was empty', async () => {
  const route = routes.find((item) => item.name === 'waitlist');
  assert.equal((await send(route, { email: 'ann@example.com', who: 'My mom' })).status, 200);
  assert.equal(saved.length, 1);
  assert.equal(saved[0].fields.porch_who, 'My mom');
});

test('waitlist: answering who is not saved when the hidden field was filled', async () => {
  const route = routes.find((item) => item.name === 'waitlist');
  const response = await send(route, { email: 'ann@example.com', who: 'My mom', website: 'https://spam.example' });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(saved.length, 0);
  assert.equal(logs[0].event, 'waitlist_blocked');
  assert.equal(logs[0].reason, 'honeypot');
});

for (const route of routes) {
  test(`${route.name}: a filled-in hidden field looks like it worked but isn't saved`, async () => {
    const response = await send(route, { ...route.body, website: 'https://spam.example' });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
    assert.equal(saved.length, 0);
    assert.equal(logs[0].event, `${route.name}_blocked`);
    assert.equal(logs[0].reason, 'honeypot');
  });

  test(`${route.name}: an empty hidden field is saved`, async () => {
    assert.equal((await send(route, { ...route.body, website: '' })).status, 200);
    assert.equal(saved.length, 1);
  });

  test(`${route.name}: a request BotID calls a bot is refused and not saved`, async () => {
    deployed(true);
    const response = await send(route, route.body);
    assert.equal(response.status, 403);
    assert.match((await response.json()).error, /try again/);
    assert.equal(saved.length, 0);
    assert.equal(logs[0].reason, 'bot');
  });

  test(`${route.name}: a request BotID calls human is saved`, async () => {
    deployed(false);
    assert.equal((await send(route, route.body)).status, 200);
    assert.equal(saved.length, 1);
  });

  test(`${route.name}: when BotID can't check, the sign-up is still saved`, async () => {
    process.env.NODE_ENV = 'production';
    assert.equal((await send(route, route.body)).status, 200);
    assert.equal(saved.length, 1);
  });
}
