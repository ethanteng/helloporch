import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { test, beforeEach, afterEach } from 'node:test';
import { handleFamily } from '../lib/family/service.ts';
import { readActivity } from '../lib/admin/activity.ts';
import { currentSession, failureLimits, sessionSeconds, signIn, signOut, signOutEverywhere } from '../lib/admin/auth.ts';
import { cancelInvitation, createInvitation, invitationSeconds, listInvitations, sendAgain, settingUpSeconds } from '../lib/admin/invitations.ts';
import { keptInvitations } from '../lib/family/activations.ts';
import { checkPassword, hashPassword, validPasswordHash } from '../lib/admin/password.ts';
import { listPorches } from '../lib/admin/porches.ts';
import { adminHeaders, adminRoute, isAdminHost } from '../lib/admin/routing.ts';
import { AdminError } from '../lib/admin/session.ts';
import { systemStatus } from '../lib/admin/system.ts';

// Fake storage with lifetimes, so expired keys go away as in Redis. Nothing here reaches Redis, Twilio or LiveKit.
class MemoryStore {
  values = new Map(); expires = new Map(); now = () => 0;
  live(key) { const until = this.expires.get(key); if (until !== undefined && until <= this.now()) { this.values.delete(key); this.expires.delete(key); } return this.values.get(key) ?? null; }
  async get(key) { return this.live(key); }
  async create(key, value, seconds) { if (this.live(key) !== null) return false; this.set(key, value, seconds); return true; }
  async compareAndSet(key, before, after, seconds) { if (this.live(key) !== before) return false; this.set(key, after, seconds); return true; }
  set(key, value, seconds) { this.values.set(key, value); if (seconds) this.expires.set(key, this.now() + seconds); else this.expires.delete(key); }
}
const env = { LIVEKIT_URL: 'wss://test.livekit.cloud', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-not-real', PORCH_CONTACT_SETUP_CODE: 'private-test-caregiver-secret' };
let previous;
beforeEach(() => { previous = Object.fromEntries(Object.keys(env).map(k => [k, process.env[k]])); Object.assign(process.env, env); });
afterEach(() => { for (const [k, v] of Object.entries(previous)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });

// A cheap hash keeps the tests quick; production hashes cost 32 times as much.
const password = 'correct horse battery staple';
const cheap = { N: 1024, r: 8, p: 1 };
async function fixture() {
  const store = new MemoryStore();
  let now = 1_800_000_000;
  store.now = () => now;
  const settings = { passwordHash: await hashPassword(password, cheap) };
  const session = async (address = '203.0.113.5') => {
    const { token } = await signIn(store, settings, { password, address }, now);
    return { token, session: await currentSession(store, settings, token, now) };
  };
  const enroll = (code, device = { deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') }) =>
    handleFamily(new Request('https://porch.example/api/family', { method: 'POST', body: JSON.stringify({ action: 'enrollBedside', ...device, pin: '098765', name: 'Mom', activation: code }) }), { store, now: () => now });
  return { store, settings, session, enroll, now: () => now, advance: seconds => { now += seconds; } };
}
const codeOf = link => new URL(link).hash.replace('#code=', '');
const refused = async (work, status) => { await assert.rejects(work, error => error instanceof AdminError && (status === undefined || error.status === status)); };

test('the password is kept only as a hash, and a malformed or oversized one never matches', async () => {
  const stored = await hashPassword(password, cheap);
  assert.match(stored, /^scrypt:1024:8:1:[A-Za-z0-9_-]{22}:[A-Za-z0-9_-]{43}$/);
  assert.ok(!stored.includes(password) && validPasswordHash(stored));
  assert.equal(await checkPassword(password, stored), true);
  assert.equal(await checkPassword(`${password}!`, stored), false);
  assert.notEqual(await hashPassword(password, cheap), stored, 'each hash has its own salt');
  for (const bad of ['', 'scrypt:1024:8:1:short:key', stored.replace('scrypt:', 'bcrypt:'), stored.replace(':1024:', ':1000:'), stored.replace(':1024:', ':4194304:')]) {
    assert.equal(validPasswordHash(bad), false, bad);
    assert.equal(await checkPassword(password, bad), false, bad);
  }
  assert.equal(await checkPassword('x'.repeat(1025), stored), false);
});

test('the admin page answers only on its host, only where it is turned on, and /admin answers 404 elsewhere', () => {
  assert.deepEqual(adminRoute('admin.helloporch.store', '/', true, false), { rewrite: '/admin' });
  assert.deepEqual(adminRoute('ADMIN.helloporch.store', '/porches', true, false), { rewrite: '/admin/porches' });
  // The admin host serves nothing else, such as the family API or the website's pages.
  assert.deepEqual(adminRoute('admin.helloporch.store', '/api/family', true, false), { rewrite: '/admin/api/family' });
  assert.deepEqual(adminRoute('admin.helloporch.store', '/admin/porches', true, false), { rewrite: '/admin/admin/porches' });
  // The website project, and any deployment without PORCH_ADMIN_ENABLED.
  assert.deepEqual(adminRoute('admin.helloporch.store', '/', false, false), { notFound: true });
  for (const host of ['helloporch.store', 'porch-calling-prototype.vercel.app', 'admin.helloporch.store.evil.example', 'evil.example']) {
    assert.deepEqual(adminRoute(host, '/admin', true, false), { notFound: true }, host);
    assert.deepEqual(adminRoute(host, '/admin/porches', true, false), { notFound: true }, host);
    assert.equal(adminRoute(host, '/pricing', true, false), undefined, host);
  }
  assert.equal(adminRoute('helloporch.store', '/administration', true, false), undefined);
  assert.equal(isAdminHost('admin.localhost:3000', true), true);
  assert.equal(isAdminHost('admin.localhost:3000', false), false, 'only development stands in a local host');
  assert.equal(isAdminHost(null), false);
});

test('admin responses allow no other sites\' scripts or frames and are never kept or indexed', () => {
  const headers = adminHeaders('bm9uY2U=', false);
  const policy = headers['Content-Security-Policy'];
  for (const part of ["default-src 'self'", "script-src 'self' 'nonce-bm9uY2U=' 'strict-dynamic'", "frame-ancestors 'none'", "form-action 'self'", "object-src 'none'"]) assert.ok(policy.includes(part), part);
  assert.ok(!policy.includes('unsafe-eval') && !policy.includes('unsafe-inline'));
  assert.equal(headers['Cache-Control'], 'no-store');
  assert.equal(headers['X-Robots-Tag'], 'noindex, nofollow');
  assert.equal(headers['Referrer-Policy'], 'no-referrer');
});

test('a session lasts 12 hours and ends on sign-out, sign-out everywhere or a new password', async () => {
  const f = await fixture();
  const first = await f.session(), second = await f.session();
  assert.ok(first.session && second.session);
  assert.equal(first.session.expiresAt, f.now() + sessionSeconds);
  assert.equal(await currentSession(f.store, f.settings, 'not-a-token', f.now()), undefined);
  assert.equal(await currentSession(f.store, f.settings, undefined, f.now()), undefined);
  assert.equal(await currentSession(f.store, f.settings, randomBytes(32).toString('base64url'), f.now()), undefined);
  // The store keeps a hash of the cookie, never the cookie itself.
  assert.ok(![...f.store.values.keys(), ...f.store.values.values()].some(v => v.includes(first.token)));

  await signOut(first.session, f.store, f.now());
  assert.equal(await currentSession(f.store, f.settings, first.token, f.now()), undefined);
  assert.ok(await currentSession(f.store, f.settings, second.token, f.now()), 'signing out ends only that session');

  await signOutEverywhere(second.session, f.store, f.now());
  assert.equal(await currentSession(f.store, f.settings, second.token, f.now()), undefined);
  const third = await f.session();
  assert.ok(third.session, 'signing in again works after signing out everywhere');

  const changed = { passwordHash: await hashPassword('a different long password', cheap) };
  assert.equal(await currentSession(f.store, changed, third.token, f.now()), undefined, 'a new password signs everyone out');

  const fourth = await f.session();
  f.advance(sessionSeconds);
  assert.equal(await currentSession(f.store, f.settings, fourth.token, f.now()), undefined, 'sessions expire');
});

test('wrong passwords pause sign-in from that address, even for the right password, then from everywhere', async () => {
  const f = await fixture();
  await refused(() => signIn(f.store, f.settings, { password: '', address: 'a' }, f.now()), 400);
  await refused(() => signIn(f.store, f.settings, { password: 42, address: 'a' }, f.now()), 400);
  for (let n = 0; n < failureLimits.address.attempts; n++) await refused(() => signIn(f.store, f.settings, { password: 'wrong', address: 'a' }, f.now()), 401);
  await refused(() => signIn(f.store, f.settings, { password, address: 'a' }, f.now()), 429);
  assert.ok((await f.session('b')).session, 'another address can still sign in');
  f.advance(failureLimits.address.seconds);
  assert.ok((await f.session('a')).session, 'the pause ends');

  const g = await fixture();
  for (let n = 0; n < failureLimits.everywhere.attempts; n++) await refused(() => signIn(g.store, g.settings, { password: 'wrong', address: `address-${n}` }, g.now()), 401);
  await refused(() => signIn(g.store, g.settings, { password, address: 'new-address' }, g.now()), 429);
  const { session } = await (async () => { g.advance(failureLimits.everywhere.seconds); return g.session('new-address'); })();
  const log = await readActivity(session, g.store);
  assert.ok(log.some(e => e.action === 'Sign-in paused after too many wrong passwords' && e.detail === 'From everywhere'));
});

test('wrong passwords tried all at once are each counted, and right ones count against nothing', async () => {
  const f = await fixture();
  const tries = await Promise.allSettled(Array.from({ length: 30 }, () => signIn(f.store, f.settings, { password: 'wrong', address: 'a' }, f.now())));
  const statuses = tries.map(t => t.reason?.status);
  assert.equal(statuses.filter(s => s === 401).length, failureLimits.address.attempts, 'only the limit had their password checked');
  assert.equal(statuses.filter(s => s === 429).length, 30 - failureLimits.address.attempts);

  const g = await fixture();
  for (let n = 1; n < failureLimits.address.attempts; n++) await refused(() => signIn(g.store, g.settings, { password: 'wrong', address: 'a' }, g.now()), 401);
  for (let n = 0; n < 3; n++) assert.ok((await g.session('a')).session, 'a right password gives its try back');
  await refused(() => signIn(g.store, g.settings, { password: 'wrong', address: 'a' }, g.now()), 401);
  await refused(() => signIn(g.store, g.settings, { password, address: 'a' }, g.now()), 429);
});

test('signed out, every admin read and change refuses', async () => {
  const f = await fixture();
  const forged = Object.create((await f.session()).session.constructor.prototype);
  for (const work of [() => createInvitation(forged, f.store, f.now(), 'Lee family'), () => listInvitations(forged, f.store, f.now()),
    () => cancelInvitation(forged, f.store, f.now(), 'x'), () => sendAgain(forged, f.store, f.now(), 'x'), () => listPorches(forged, f.store),
    () => systemStatus(forged, f.store), () => readActivity(forged, f.store), () => signOut(forged, f.store, f.now()), () => signOutEverywhere(forged, f.store, f.now()),
    () => listPorches({}, f.store)]) await refused(work, 401);
});

test('every admin page and Server Action checks the session itself, not just Proxy', () => {
  const pages = [];
  const walk = folder => { for (const name of readdirSync(folder)) { const path = join(folder, name); if (statSync(path).isDirectory()) walk(path); else if (name === 'page.tsx' || name === 'layout.tsx') pages.push(path); } };
  walk('app/(admin)/admin/(signed-in)');
  assert.ok(pages.length >= 5);
  for (const path of pages) assert.match(readFileSync(path, 'utf8'), /await requireAdmin\(\)/, path);
  assert.match(readFileSync('app/(admin)/admin/sign-in/page.tsx', 'utf8'), /await adminRequest\(\)/);
  const actions = readFileSync('app/(admin)/admin/actions.ts', 'utf8').split(/\nexport async function /).slice(1);
  assert.ok(actions.length >= 6);
  for (const action of actions) {
    const [name] = action.split('(');
    assert.match(action, name === 'signInAction' ? /^[^\n]*\n\s+const \{[^}]+\} = await adminRequest\(\);/ : /^[^\n]*\n\s+const session = await requireAdmin\(\);/, name);
  }
});

test('an invitation sets up one bedside with its link, then shows the household', async () => {
  const f = await fixture();
  const { session } = await f.session();
  await refused(() => createInvitation(session, f.store, f.now(), '  '), 400);
  await refused(() => createInvitation(session, f.store, f.now(), 'x'.repeat(81)), 400);
  const made = await createInvitation(session, f.store, f.now(), ' Lee family ');
  assert.equal(made.label, 'Lee family');
  assert.match(made.link, /^https:\/\/helloporch\.store\/setup#code=[a-f0-9]{64}$/);
  assert.equal(made.message, `Here's your private link to set up Porch. Open it on the iPad that will stay with your loved one: ${made.link}`);
  assert.equal(made.expiresAt, f.now() + invitationSeconds);
  // Only a hash of the code is kept.
  assert.ok(![...f.store.values.values()].some(v => v.includes(codeOf(made.link))));
  assert.deepEqual((await listInvitations(session, f.store, f.now())).map(i => [i.label, i.state]), [['Lee family', 'waiting']]);

  f.advance(13 * 86400);
  const device = { deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') };
  const setUp = await f.enroll(codeOf(made.link), device);
  assert.equal(setUp.status, 200, await setUp.clone().text());
  const householdID = device.deviceID;
  const [row] = await listInvitations(session, f.store, f.now());
  assert.deepEqual([row.state, row.householdID, row.setUpAt], ['set up', householdID, f.now()]);
  // The same iPad may retry after a lost response; another can't use the link.
  assert.equal((await f.enroll(codeOf(made.link), device)).status, 200);
  assert.equal((await f.enroll(codeOf(made.link))).status, 410);
  // Cancelling a used link changes nothing.
  await cancelInvitation(session, f.store, f.now(), made.id);
  assert.equal((await listInvitations(session, f.store, f.now()))[0].state, 'set up');

  const [porch] = await listPorches(session, f.store);
  assert.deepEqual(porch, { id: householdID, bedsideName: 'Mom', invitationLabel: 'Lee family', numberPending: false, setUpAt: f.now(), lastSeenAt: f.now(), familyPhones: 0, setupFinished: false });
});

test('a cancelled or expired link no longer sets anything up, and can be sent again', async () => {
  const f = await fixture();
  const { session } = await f.session();
  const cancelled = await createInvitation(session, f.store, f.now(), 'Park family');
  await cancelInvitation(session, f.store, f.now(), cancelled.id);
  const refusedSetup = await f.enroll(codeOf(cancelled.link));
  assert.equal(refusedSetup.status, 410);
  assert.match((await refusedSetup.json()).error, /cancelled/);
  await refused(() => cancelInvitation(session, f.store, f.now(), 'missing'), 404);

  const expired = await createInvitation(session, f.store, f.now(), 'Diaz family');
  await refused(() => sendAgain(session, f.store, f.now(), expired.id), 409);
  f.advance(invitationSeconds);
  assert.equal((await f.enroll(codeOf(expired.link))).status, 410);
  const states = Object.fromEntries((await listInvitations(session, f.store, f.now())).map(i => [i.label, i.state]));
  assert.deepEqual(states, { 'Diaz family': 'expired', 'Park family': 'cancelled' });

  const again = await sendAgain(session, f.store, f.now(), expired.id);
  assert.equal(again.label, 'Diaz family');
  assert.notEqual(codeOf(again.link), codeOf(expired.link));
  assert.equal((await f.enroll(codeOf(again.link))).status, 200);
  assert.ok(await sendAgain(session, f.store, f.now(), cancelled.id));
});

test('a link used while it was being cancelled stays set up, and one whose setup stopped can be cancelled later', async () => {
  const f = await fixture();
  const { session } = await f.session();
  const made = await createInvitation(session, f.store, f.now(), 'Kim family');
  // The iPad claims the link before its household is made.
  const key = JSON.parse(await f.store.get('admin-invitations'))[0].activation;
  const raw = await f.store.get(key);
  const device = { deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') };
  await f.store.compareAndSet(key, raw, JSON.stringify({ ...JSON.parse(raw), claimedBy: device.deviceID, claimHash: 'x', claimedAt: f.now() }));
  await refused(() => cancelInvitation(session, f.store, f.now(), made.id), 409);
  assert.equal((await listInvitations(session, f.store, f.now()))[0].state, 'waiting');

  // That setup never finished: a while later, Cancel stops the link, and sending it again works.
  f.advance(settingUpSeconds);
  await cancelInvitation(session, f.store, f.now(), made.id);
  assert.equal((await listInvitations(session, f.store, f.now()))[0].state, 'cancelled');
  assert.match((await (await f.enroll(codeOf(made.link), device)).json()).error, /cancelled/);
  assert.ok(await sendAgain(session, f.store, f.now(), made.id));

  // A setup that finished but wasn't listed against its invitation shows as set up instead of being cancelled.
  const lost = await createInvitation(session, f.store, f.now(), 'Cho family');
  const other = { deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') };
  assert.equal((await f.enroll(codeOf(lost.link), other)).status, 200);
  const list = JSON.parse(await f.store.get('admin-invitations'));
  delete list[0].householdID; delete list[0].setUpAt;
  f.store.set('admin-invitations', JSON.stringify(list));
  await cancelInvitation(session, f.store, f.now(), lost.id);
  const [row] = await listInvitations(session, f.store, f.now());
  assert.deepEqual([row.label, row.state, row.householdID], ['Cho family', 'set up', other.deviceID]);
});

test('waiting invitations stay on the list, however many finished ones come after', async () => {
  const f = await fixture();
  const { session } = await f.session();
  const waiting = await createInvitation(session, f.store, f.now(), 'Waiting family');
  const finished = [];
  for (let n = 0; n <= keptInvitations; n++) {
    finished.push(await createInvitation(session, f.store, f.now(), `Family ${n}`));
    await cancelInvitation(session, f.store, f.now(), finished.at(-1).id);
  }
  await createInvitation(session, f.store, f.now(), 'Newest family');
  const ids = (await listInvitations(session, f.store, f.now())).map(i => i.id);
  assert.equal(ids.length, keptInvitations + 2);
  assert.ok(ids.includes(waiting.id) && !ids.includes(finished[0].id), 'the oldest finished one drops off');
  await cancelInvitation(session, f.store, f.now(), waiting.id);
  assert.equal((await listInvitations(session, f.store, f.now())).find(i => i.id === waiting.id).state, 'cancelled');
});

test('the Porches list covers older households and holds no private details', async () => {
  const f = await fixture();
  const { session } = await f.session();
  // A household from before the list, which holds a Porch number, as ours do.
  const mom = await handleFamily(new Request('https://porch.example/api/family', { method: 'POST', headers: { 'X-Porch-Setup-Code': env.PORCH_CONTACT_SETUP_CODE },
    body: JSON.stringify({ action: 'createHousehold', name: 'Mom', deviceID: randomUUID(), deviceSecret: randomBytes(32).toString('hex') }) }), { store: f.store, now: f.now }).then(r => r.json());
  const raw = await f.store.get(`house:${mom.state.householdID}`);
  const house = JSON.parse(raw);
  delete house.createdAt;
  house.porchNumber = { number: '+14155550101', assignedAt: f.now() };
  house.members.push({ id: randomUUID(), name: 'Private cousin name', role: 'family', secretHash: 'x', permissions: { audio: true, video: true }, revoked: false, seenAt: f.now(), available: false });
  house.inbox = [{ id: 'm', text: 'Private message text' }];
  house.keypadNumbers = ['+14155559999'];
  await f.store.compareAndSet(`house:${house.id}`, raw, JSON.stringify(house));
  f.store.values.delete('households');
  await f.store.create('numbers:households', JSON.stringify([house.id]));
  f.advance(3 * 86400);

  const rows = await listPorches(session, f.store);
  assert.deepEqual(rows, [{ id: house.id, bedsideName: 'Mom', porchNumber: '+14155550101', numberPending: false, lastSeenAt: f.now() - 3 * 86400, familyPhones: 1, setupFinished: true }]);
  const text = JSON.stringify(rows);
  for (const secret of ['Private cousin name', 'Private message text', '+14155559999', 'secretHash']) assert.ok(!text.includes(secret), secret);
});

test('System counts Porch numbers against the limit', async () => {
  const f = await fixture();
  const { session } = await f.session();
  await f.store.create('numbers:households', JSON.stringify(['a', 'b']));
  delete process.env.PORCH_MAX_PHONE_NUMBERS;
  assert.deepEqual(await systemStatus(session, f.store), { numbersInUse: 2, ready: false });
  process.env.PORCH_MAX_PHONE_NUMBERS = '5';
  try { assert.equal((await systemStatus(session, f.store)).numberLimit, 5); } finally { delete process.env.PORCH_MAX_PHONE_NUMBERS; }
});

test('each admin action leaves an activity entry, and the log keeps the last 500', async () => {
  const f = await fixture();
  const { session } = await f.session();
  const made = await createInvitation(session, f.store, f.now(), 'Lee family');
  await cancelInvitation(session, f.store, f.now(), made.id);
  await sendAgain(session, f.store, f.now(), made.id);
  await signOut(session, f.store, f.now());
  const { session: next } = await f.session();
  await signOutEverywhere(next, f.store, f.now());
  const { session: last } = await f.session();
  const log = await readActivity(last, f.store);
  assert.deepEqual(log.map(e => [e.action, e.detail]).reverse(), [['Signed in', undefined], ['Invited a new family', 'Lee family'], ['Cancelled an invitation', 'Lee family'],
    ['Invited a new family', 'Lee family'], ['Signed out', undefined], ['Signed in', undefined], ['Signed out everywhere', undefined], ['Signed in', undefined]]);
  assert.ok(!JSON.stringify(log).includes(codeOf(made.link)));
  for (let n = 0; n < 510; n++) await createInvitation(last, f.store, f.now(), `Family ${n}`);
  assert.equal((await readActivity(last, f.store)).length, 500);
});

test('bedsides set up by the operator script are listed too', async () => {
  const f = await fixture();
  const { session } = await f.session();
  const invite = await handleFamily(new Request('https://porch.example/api/family', { method: 'POST', headers: { 'X-Porch-Setup-Code': env.PORCH_CONTACT_SETUP_CODE },
    body: JSON.stringify({ action: 'createBedsideInvite' }) }), { store: f.store, now: f.now }).then(r => r.json());
  assert.equal((await f.enroll(invite.code)).status, 200);
  const [row] = await listPorches(session, f.store);
  assert.equal(row.setUpAt, f.now());
  assert.equal(row.invitationLabel, undefined);
  assert.deepEqual(await listInvitations(session, f.store, f.now()), []);
});
