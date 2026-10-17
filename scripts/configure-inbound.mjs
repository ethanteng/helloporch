import { writeFileSync } from 'node:fs';
import { RoomConfiguration, SIPInboundTrunkInfo, SipClient } from 'livekit-server-sdk';
import { familyStore } from '../lib/family/store.ts';
import { callerVerificationAttribute, callerVerificationHeader, forwardedVerificationHeader, inboundRingSeconds, inboundRoomPrefix, sipInboundCredentials } from '../lib/family/inbound.ts';

// No credentials or phone numbers in arguments/output. Load private env files
// with Node's --env-file flags. The default is a read-only plan; --apply saves it.
class SetupError extends Error {}
const args = process.argv.slice(2);
const householdID = args.find(arg => arg.startsWith('--household='))?.slice('--household='.length);
const apply = args.includes('--apply');
// --voicemail: Twilio's voice webhook dials LiveKit with a digest login, so callers who
// aren't answered can leave a message. Once a trunk has the login, it stays in this mode.
let voicemail = args.includes('--voicemail');
// --reassign: move a number that already rings another household (or a replaced bedside) to this one.
const reassign = args.includes('--reassign');
if (!householdID || !/^[a-f0-9-]{36}$/.test(householdID) || args.some(arg => !['--apply', '--voicemail', '--reassign'].includes(arg) && !arg.startsWith('--household='))) {
  console.error('Usage: node --env-file=.env.inbound-production.local --env-file=.env.local scripts/configure-inbound.mjs --household=HOUSEHOLD_UUID [--voicemail] [--reassign] [--apply]');
  process.exit(1);
}
// Twilio's published SIP signaling gateways, verified 2026-10-16:
// https://www.twilio.com/docs/sip-trunking/ip-addresses
// These are SIP signaling ranges, not the separate RTP media ranges.
const twilioGateways = ['54.172.60.0/30', '54.244.51.0/30', '54.171.127.192/30', '35.156.191.128/30',
  '54.65.63.192/30', '54.169.127.128/30', '54.252.254.64/30', '177.71.206.192/30'];

try {
  const { LIVEKIT_URL: url, LIVEKIT_API_KEY: key, LIVEKIT_API_SECRET: secret, LIVEKIT_SIP_OUTBOUND_TRUNK_ID: outboundID } = process.env;
  if (!url?.startsWith('wss://') || !key || !secret || !outboundID) throw new SetupError('LiveKit calling configuration is missing.');
  const store = familyStore();
  const raw = await store.get(`house:${householdID}`);
  if (!raw) throw new SetupError('The requested household does not exist in this storage namespace.');
  const house = JSON.parse(raw);
  const bedsides = house.members.filter(member => member.role === 'bedside' && !member.revoked);
  if (bedsides.length !== 1) throw new SetupError('This setup requires exactly one active bedside device in the household.');
  const sip = new SipClient(url.replace('wss:', 'https:'), key, secret, { requestTimeout: 10, failover: false });
  const [outbound] = await sip.listSipOutboundTrunk({ trunkIds: [outboundID] });
  const number = process.env.PORCH_INBOUND_NUMBER || (outbound?.numbers.length === 1 ? outbound.numbers[0] : undefined);
  if (!number || !/^\+[1-9][0-9]{6,14}$/.test(number) || !outbound?.numbers.includes(number) || !outbound.address.endsWith('.pstn.twilio.com')) {
    throw new SetupError('Set PORCH_INBOUND_NUMBER privately to a number on the existing Twilio outbound trunk.');
  }
  const routeKey = `phone-number:${number}`;
  const previous = await store.get(routeKey);
  const route = previous ? JSON.parse(previous) : undefined;
  // Bedside names, not IDs, so the operator can tell households apart before saving.
  const bedsideName = `“${bedsides[0].name}”`;
  const moving = !!route && (route.householdID !== house.id || route.bedsideID !== bedsides[0].id);
  let movingFrom = 'another household';
  if (moving) {
    const old = JSON.parse(await store.get(`house:${route.householdID}`) ?? 'null');
    const oldBedside = old?.members.find(member => member.id === route.bedsideID);
    if (oldBedside) movingFrom = `“${oldBedside.name}”${old.id === house.id ? ' (a replaced bedside)' : ''}`;
    if (!reassign) throw new SetupError(`This number rings ${movingFrom}. To move it to ${bedsideName}, run again with --reassign.`);
  }
  const name = `Porch inbound ${house.id}`;
  const existing = (await sip.listSipInboundTrunk()).filter(trunk => trunk.numbers.includes(number));
  // The saved route says which Porch trunk serves the number, even while a reassignment
  // (or an interrupted one) still has it named for the previous household.
  const ours = trunk => trunk.name === name || (trunk.sipTrunkId === route?.trunkID && trunk.name.startsWith('Porch inbound '));
  if (existing.length > 1 || existing.some(trunk => !ours(trunk))) throw new SetupError('This number already has a different inbound trunk; review it before changing routing.');
  let trunk = existing[0];
  if (route && (!trunk || route.trunkID !== trunk.sipTrunkId)) throw new SetupError('The saved number route and inbound trunk disagree; review them before continuing.');
  const rules = await sip.listSipDispatchRule();
  if (rules.some(rule => rule.trunkIds.length === 0)) throw new SetupError('A wildcard SIP dispatch rule already exists; scope it to its own trunks first.');
  let dispatch = trunk ? rules.find(rule => rule.trunkIds.includes(trunk.sipTrunkId)) : undefined;
  if (dispatch && (dispatch.trunkIds.length !== 1 || dispatch.rule?.rule.case !== 'dispatchRuleIndividual' || dispatch.rule.rule.value.roomPrefix !== inboundRoomPrefix)) {
    throw new SetupError('An incompatible dispatch rule already uses this trunk.');
  }
  voicemail ||= !!trunk?.authUsername;
  console.log('Existing Twilio number and destination household verified.');
  console.log(moving
    ? `Reassign: calls to this number will ring the bedside ${bedsideName} instead of ${movingFrom}. Messages already left stay where they are.`
    : `Calls to this number will ring the bedside ${bedsideName}.`);
  console.log('Plan: one number → this household; isolated two-person audio rooms; manual answer except approved drop-ins; 45-second ringing; 30-minute call limit.');
  console.log('Carrier caller-ID verification is passed to Porch, so caregiver-approved numbers can drop in with audio while drop-in is on.');
  console.log(voicemail
    ? 'Voicemail routing: inbound SIP requires the Porch digest login, which only the calling server sends from its Twilio voice webhook.'
    : 'Inbound SIP restricted to Twilio signaling gateways.');
  console.log('No phone numbers will be purchased and no calls will be placed.');
  if (!apply) { console.log('Read-only plan complete. Use --apply to save the LiveKit and household configuration.'); process.exit(0); }
  // A reassignment claims the number before changing LiveKit, so a concurrent run
  // that loses the compare-and-set stops without touching the shared trunk or rule.
  const claim = moving ? JSON.stringify({ householdID: house.id, bedsideID: bedsides[0].id, trunkID: route.trunkID }) : undefined;
  if (claim && !await store.compareAndSet(routeKey, previous, claim)) throw new SetupError('Number assignment changed concurrently; refusing to overwrite it.');
  if (!trunk) trunk = await sip.createSipInboundTrunk(name, [number], { allowedAddresses: twilioGateways, ringingTimeout: inboundRingSeconds });
  // The current SDK exposes maxCallDuration on the protobuf but not its create
  // options. Update the full returned trunk, retaining its other fields.
  if (voicemail) {
    // Twilio doesn't publish the voice webhook's SIP source addresses; the login protects the trunk instead.
    const login = sipInboundCredentials(secret);
    trunk.authUsername = login.username; trunk.authPassword = login.password; trunk.allowedAddresses = [];
  } else trunk.allowedAddresses = twilioGateways;
  trunk.ringingTimeout = new SIPInboundTrunkInfo({ ringingTimeout: { seconds: BigInt(inboundRingSeconds) } }).ringingTimeout;
  trunk.maxCallDuration = new SIPInboundTrunkInfo({ maxCallDuration: { seconds: 1800n } }).maxCallDuration;
  // Twilio's STIR/SHAKEN result; phone drop-in requires it. Keep other mappings.
  // Voicemail routing reads the result from the server's forwarded header, never a header a SIP source chose.
  const { [callerVerificationHeader]: _twilio, [forwardedVerificationHeader]: _forwarded, ...otherHeaders } = trunk.headersToAttributes ?? {};
  trunk.headersToAttributes = { ...otherHeaders, [voicemail ? forwardedVerificationHeader : callerVerificationHeader]: callerVerificationAttribute };
  // A reassigned trunk and rule take the new household's name, so later runs recognize them.
  trunk.name = name;
  trunk = await sip.updateSipInboundTrunk(trunk.sipTrunkId, trunk);
  if (!dispatch) dispatch = await sip.createSipDispatchRule({ type: 'individual', roomPrefix: inboundRoomPrefix }, {
    name, trunkIds: [trunk.sipTrunkId], hidePhoneNumber: false,
    roomConfig: new RoomConfiguration({ maxParticipants: 2, emptyTimeout: 60, departureTimeout: 5 }),
  });
  else if (dispatch.name !== name) dispatch = await sip.updateSipDispatchRuleFields(dispatch.sipDispatchRuleId, { name });
  const saved = JSON.stringify({ householdID: house.id, bedsideID: bedsides[0].id, trunkID: trunk.sipTrunkId });
  if (!previous) await store.create(routeKey, saved);
  // Revalidate: another reassignment may have taken the number while LiveKit was updating.
  if (await store.get(routeKey) !== saved) throw new SetupError('Number assignment changed concurrently. Run the setup again for the household that should get the calls.');
  writeFileSync('.env.inbound-setup.local', [
    `PORCH_INBOUND_NUMBER=${number}`, `PORCH_INBOUND_HOUSEHOLD_ID=${house.id}`, `LIVEKIT_SIP_INBOUND_TRUNK_ID=${trunk.sipTrunkId}`,
    `LIVEKIT_SIP_DISPATCH_RULE_ID=${dispatch.sipDispatchRuleId}`, '',
  ].join('\n'), { mode: 0o600 });
  console.log(`LiveKit inbound trunk, dispatch rule, and household number assignment saved. Calls now ring ${bedsideName}.`);
  console.log(voicemail
    ? 'Private configuration saved to .env.inbound-setup.local. Point the Twilio number\'s voice webhook at /api/calls/inbound/voice to finish activation.'
    : 'Private configuration saved to .env.inbound-setup.local. Configure Twilio Origination and the LiveKit webhook to finish activation.');
} catch (error) {
  // Provider exceptions may contain phone numbers or credentials; keep those out.
  console.error(error instanceof SetupError ? error.message : 'Provider setup failed. Check account access and retry the same command.');
  process.exitCode = 1;
}
