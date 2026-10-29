import { SipClient } from 'livekit-server-sdk';
import { familyStore } from '../lib/family/store.ts';
import { FamilyError, mutate } from '../lib/family/household.ts';
import { ensurePorchNumber, holdPlace, numberServices, numberSettings } from '../lib/family/numbers.ts';

// Gives a household that has no Porch number one, outside the bedside's own setup.
//   --adopt: the number configure-inbound.mjs already routes to this household (PORCH_INBOUND_NUMBER, saved in
//     .env.inbound-setup.local) becomes its Porch number, so its calls out show it. Nothing is bought and routing doesn't change.
//   --area-code=415: buys a new number for it, the way setup on the bedside does.
// No credentials or phone numbers in arguments or output. The default is a read-only plan; --apply saves it.
class SetupError extends Error {}
const args = process.argv.slice(2);
const householdID = args.find(arg => arg.startsWith('--household='))?.slice('--household='.length);
const areaCode = args.find(arg => arg.startsWith('--area-code='))?.slice('--area-code='.length);
const adopt = args.includes('--adopt'), apply = args.includes('--apply');
if (!householdID || !/^[a-f0-9-]{36}$/.test(householdID) || adopt === !!areaCode || (areaCode && !/^[2-9](?!11)[0-9]{2}$/.test(areaCode)) ||
    args.some(arg => !['--adopt', '--apply'].includes(arg) && !arg.startsWith('--household=') && !arg.startsWith('--area-code='))) {
  console.error('Usage: node --env-file=.env.inbound-production.local --env-file=.env.local [--env-file=.env.inbound-setup.local] scripts/provision-number.mjs --household=HOUSEHOLD_UUID (--adopt | --area-code=AREA_CODE) [--apply]');
  process.exit(1);
}

try {
  const store = familyStore();
  const raw = await store.get(`house:${householdID}`);
  if (!raw) throw new SetupError('The requested household does not exist in this storage namespace.');
  const house = JSON.parse(raw);
  const bedsides = house.members.filter(member => member.role === 'bedside' && !member.revoked);
  if (bedsides.length !== 1) throw new SetupError('This needs exactly one active bedside device in the household.');
  // Bedside names, not IDs, so the operator can tell households apart before saving.
  const bedsideName = `“${bedsides[0].name}”`;
  if (house.porchNumber) throw new SetupError(`The bedside ${bedsideName} already has a Porch number.`);
  const now = Math.floor(Date.now() / 1000);

  if (adopt) {
    const number = process.env.PORCH_INBOUND_NUMBER;
    if (!number || !/^\+[1-9][0-9]{6,14}$/.test(number)) throw new SetupError('Load PORCH_INBOUND_NUMBER privately, for example with --env-file=.env.inbound-setup.local.');
    const route = JSON.parse(await store.get(`phone-number:${number}`) ?? 'null');
    if (route?.householdID !== house.id || route.bedsideID !== bedsides[0].id) throw new SetupError(`That number doesn't ring the bedside ${bedsideName}. Check it with configure-inbound.mjs first.`);
    // Its calls out will name this number, so the outbound trunk has to carry it.
    const { LIVEKIT_URL: url, LIVEKIT_API_KEY: key, LIVEKIT_API_SECRET: secret, LIVEKIT_SIP_OUTBOUND_TRUNK_ID: outboundID } = process.env;
    if (!url?.startsWith('wss://') || !key || !secret || !outboundID) throw new SetupError('LiveKit calling configuration is missing.');
    const sip = new SipClient(url.replace('wss:', 'https:'), key, secret, { requestTimeout: 10, failover: false });
    const [outbound] = await sip.listSipOutboundTrunk({ trunkIds: [outboundID] });
    if (!outbound?.numbers.includes(number)) throw new SetupError("That number isn't on the outbound trunk, so calls out couldn't show it.");
    console.log(`Plan: the number that already rings the bedside ${bedsideName} becomes its Porch number, used as caller ID for its calls out.`);
    console.log('Routing and the trunks stay as they are. Nothing is bought and no calls are placed.');
    if (!apply) { console.log('Read-only plan complete. Use --apply to save it.'); process.exit(0); }
    await holdPlace(store, house.id, Infinity);
    await mutate(store, house.id, latest => { latest.porchNumber ??= { number, assignedAt: now }; delete latest.phoneSetup; });
    console.log(`Saved. The bedside ${bedsideName}'s calls out now use its Porch number as caller ID.`);
  } else {
    const settings = numberSettings();
    if (!settings) throw new SetupError('Load TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, PORCH_SERVER_ORIGIN, LIVEKIT_SIP_URI, LIVEKIT_SIP_OUTBOUND_TRUNK_ID and PORCH_MAX_PHONE_NUMBERS privately with --env-file.');
    console.log(`Plan: buy a local number in area code ${areaCode} for the bedside ${bedsideName}, ring the bedside when it's called, and use it for its calls out.`);
    console.log('Twilio charges for the number every month until it is released. No calls are placed.');
    if (!apply) { console.log('Read-only plan complete. Use --apply to buy it.'); process.exit(0); }
    await mutate(store, house.id, latest => { if (!latest.porchNumber) latest.phoneSetup = { areaCode, attempts: 0, retryAt: now }; });
    const saved = await ensurePorchNumber(store, house.id, now, settings, numberServices(settings));
    if (!saved.porchNumber) throw new SetupError('Another request is setting up this number right now. Run this again in two minutes.');
    console.log(`Bought and routed a number for the bedside ${bedsideName}. It's in the Twilio console under Phone Numbers, named “Porch ${house.id}”.`);
    console.log("Porch sends it to the family's apps, which will show it once the setup screens are built.");
  }
} catch (error) {
  // Provider exceptions may contain phone numbers or credentials; keep those out. Porch's own messages don't.
  console.error(error instanceof SetupError || error instanceof FamilyError ? error.message : 'Provider setup failed. Check account access and retry the same command.');
  process.exitCode = 1;
}
