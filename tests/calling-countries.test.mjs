import assert from 'node:assert/strict';
import { test } from 'node:test';
import { countryOf, twilioDialing, uncallable } from '../lib/calls/countries.ts';

// A fake Twilio, so nothing here reads or changes the real account's Geo Permissions.
const sid = `AC${'0'.repeat(32)}`;
const base = 'https://voice.twilio.com/v1/DialingPermissions';
function twilio(pages, updateCount = 1) {
  const requests = [];
  const fetcher = async (url, init) => {
    requests.push({ url, method: init.method, body: init.body?.toString(), headers: init.headers, redirect: init.redirect });
    if (url === `${base}/BulkCountryUpdates`) return Response.json({ update_count: updateCount }, { status: 201 });
    return pages[url] ? Response.json(pages[url]) : new Response('missing', { status: 404 });
  };
  return { requests, dialing: twilioDialing(sid, 'token', fetcher) };
}
const row = (iso, name, codes, on) => ({ iso_code: iso, name, country_codes: codes, low_risk_numbers_enabled: on, high_risk_special_numbers_enabled: false });
const updates = request => JSON.parse(new URLSearchParams(request.body).get('UpdateRequest'));

test("the list comes from every page of Twilio's Geo Permissions, and never from another host", async () => {
  const first = `${base}/Countries?PageSize=1000`, second = `${base}/Countries?PageSize=1000&Page=1&PageToken=next`;
  const t = twilio({
    [first]: { content: [row('US', 'United States/Canada', ['1'], true), row('JM', 'Jamaica', ['1876', '1658'], false), { iso_code: 'bad', name: 'Nowhere', country_codes: ['1'] }],
      meta: { next_page_url: second } },
    [second]: { content: [row('GB', 'United Kingdom', ['44'], true)], meta: { next_page_url: 'https://elsewhere.example/countries' } },
  });
  assert.deepEqual(await t.dialing.list(), [{ iso: 'US', name: 'United States/Canada', codes: ['1'], enabled: true },
    { iso: 'JM', name: 'Jamaica', codes: ['1876', '1658'], enabled: false }, { iso: 'GB', name: 'United Kingdom', codes: ['44'], enabled: true }]);
  assert.deepEqual(t.requests.map(r => r.url), [first, second]);
  assert.equal(t.requests[0].headers.authorization, `Basic ${Buffer.from(`${sid}:token`).toString('base64')}`);
  assert.equal(t.requests[0].redirect, 'error');
  await assert.rejects(twilio({}).dialing.list());
});

test('switching a country sends one update that keeps premium-rate and high-risk numbers off', async () => {
  const t = twilio({});
  await t.dialing.set('HK', true);
  await t.dialing.set('GB', false);
  assert.deepEqual(t.requests.map(r => [r.method, r.url]), [['POST', `${base}/BulkCountryUpdates`], ['POST', `${base}/BulkCountryUpdates`]]);
  assert.deepEqual(updates(t.requests[0]), [{ iso_code: 'HK', low_risk_numbers_enabled: true, high_risk_special_numbers_enabled: false, high_risk_tollfraud_numbers_enabled: false }]);
  assert.deepEqual(updates(t.requests[1]), [{ iso_code: 'GB', low_risk_numbers_enabled: false, high_risk_special_numbers_enabled: false, high_risk_tollfraud_numbers_enabled: false }]);
  await assert.rejects(twilio({}, 0).dialing.set('HK', true));
});

const countries = [{ iso: 'US', name: 'United States/Canada', codes: ['1'], enabled: true }, { iso: 'JM', name: 'Jamaica', codes: ['1876', '1658'], enabled: false },
  { iso: 'HK', name: 'Hong Kong', codes: ['852'], enabled: true }, { iso: 'MO', name: 'Macau', codes: ['853'], enabled: false }];

test('a number belongs to the country with the longest calling code it starts with', () => {
  assert.equal(countryOf('+14155550123', countries)?.iso, 'US');
  assert.equal(countryOf('+18765550123', countries)?.iso, 'JM');
  assert.equal(countryOf('+16585550123', countries)?.iso, 'JM');
  assert.equal(countryOf('+85221234567', countries)?.iso, 'HK');
  assert.equal(countryOf('+85328123456', countries)?.iso, 'MO');
  assert.equal(countryOf('+74951234567', countries), undefined);
});

test('a keypad number is turned away only when Twilio says its country is off', async () => {
  const permissions = list => ({ list, async set() { throw new Error('checking never changes Twilio'); } });
  assert.equal(await uncallable('+85221234567', permissions(async () => countries)), undefined);
  assert.equal(await uncallable('+18765550123', permissions(async () => countries)), "Porch can't call phone numbers in Jamaica yet.");
  assert.equal(await uncallable('+74951234567', permissions(async () => countries)), "Porch can't call this number.");
  // Twilio checks again when the call is dialed, so not knowing isn't a reason to refuse.
  for (const list of [async () => { throw new Error('down'); }, async () => []]) assert.equal(await uncallable('+74951234567', permissions(list)), undefined);
  assert.equal(await uncallable('+74951234567', undefined), undefined);
});
