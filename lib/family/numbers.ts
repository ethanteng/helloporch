import { randomUUID } from "node:crypto";
import { RoomConfiguration, SIPInboundTrunkInfo, SipClient, type SipInboundTrunkUpdateOptions } from "livekit-server-sdk";
import { config, FamilyError, mutate, requireValue, type Household, type Member } from "./household.ts";
import { callerVerificationAttribute, forwardedVerificationHeader, inboundRingLimitSeconds, inboundRoomPrefix, sipInboundCredentials, type InboundRoute } from "./inbound.ts";
import type { FamilyStore } from "./store.ts";

// Every household gets its own Porch phone number, set up from the bedside during setup. Porch buys a local US number
// from Twilio with its voice webhook pointing at Porch, so calls to it get voicemail (voicemail.ts) and ring the bedside
// through one LiveKit inbound trunk that all of these numbers share, and its messaging webhook too, so texts to it reach
// the bedside (texts.ts). The number also goes on the outbound trunk: the household's calls to regular phones show it,
// so calling back reaches the same Porch.
export const numberActions = new Set(["phoneNumberOptions", "assignPhoneNumber"]);

const usNumber = /^\+1[2-9][0-9]{2}[2-9][0-9]{6}$/;
// US area codes, less N11 service codes. Twilio's US inventory has nothing in the rest, such as toll-free codes.
const areaCodePattern = /^[2-9](?!11)[0-9]{2}$/;
const sharedTrunkName = "Porch inbound (shared)";
const sharedTrunkKey = "numbers:inbound-trunk";
// Households holding a number or getting one, counted against PORCH_MAX_PHONE_NUMBERS.
export const holdersKey = "numbers:households";
// Twilio's name for each number Porch buys, so a purchase whose response was lost can be found again.
const label = (householdID: string) => `Porch ${householdID}`;
// The wait before the bedside's poll tries again: a minute, doubling to an hour.
const retrySeconds = (attempts: number) => Math.min(3600, 60 * 2 ** Math.max(0, attempts - 1));

export type AvailableNumber = { number: string; locality?: string; region?: string };
export type OwnedNumber = { sid: string; number: string };
export type NumberQuery = { areaCode: string } | { near: { latitude: number; longitude: number } };
/** A purchase Twilio turned down, such as a number someone else bought first. Nothing was sold. */
export class PurchaseRefused extends Error {}
/** Twilio's phone-number API. Tests fake it, so they never buy a number. */
export type NumberProvider = {
  search(query: NumberQuery): Promise<AvailableNumber[]>;
  /** Throws `PurchaseRefused` only when Twilio certainly sold nothing. */
  buy(number: string, options: { voiceURL: string; smsURL: string; label: string }): Promise<OwnedNumber>;
  find(label: string): Promise<OwnedNumber | undefined>;
};
export type NumberServices = {
  provider: NumberProvider;
  sip: Pick<SipClient, "listSipInboundTrunk" | "createSipInboundTrunk" | "updateSipInboundTrunk" | "updateSipInboundTrunkFields" | "updateSipOutboundTrunkFields" | "listSipDispatchRule" | "createSipDispatchRule">;
};
export type NumberSettings = { accountSID: string; authToken: string; voiceURL: string; smsURL: string; outboundTrunkID: string; limit: number; apiSecret: string };
export type NumberContext = { store: FamilyStore; now: number; house: Household; me: Member; input: Record<string, unknown>; headers: Headers;
  services?: (settings: NumberSettings) => NumberServices };

/** Everything buying a number needs. Without all of it, or without a limit on how many, Porch doesn't buy any. */
export function numberSettings(): NumberSettings | undefined {
  const { TWILIO_ACCOUNT_SID: accountSID, TWILIO_AUTH_TOKEN: authToken, PORCH_SERVER_ORIGIN: origin, LIVEKIT_SIP_OUTBOUND_TRUNK_ID: outboundTrunkID,
    LIVEKIT_SIP_URI: sipURI, LIVEKIT_API_SECRET: apiSecret, PORCH_MAX_PHONE_NUMBERS: maximum } = process.env;
  const limit = Number(maximum);
  // The voice webhook needs the SIP URI to reach LiveKit, so a number bought without it couldn't ring anything.
  if (!accountSID || !/^AC[0-9a-f]{32}$/.test(accountSID) || !authToken || !outboundTrunkID || !sipURI?.trim() || !apiSecret || !Number.isSafeInteger(limit) || limit < 1) return undefined;
  try {
    // The live address, never a deployment's own: Twilio keeps calling this URL for as long as the number exists.
    const url = new URL(origin ?? "");
    if (url.protocol !== "https:" || url.origin !== origin?.replace(/\/$/, "")) return undefined;
    return { accountSID, authToken, voiceURL: `${url.origin}/api/calls/inbound/voice`, smsURL: `${url.origin}/api/calls/inbound/text`, outboundTrunkID, limit, apiSecret };
  } catch { return undefined; }
}

class TwilioError extends Error {
  status: number;
  constructor(status: number) { super(`Twilio request failed (${status}).`); this.status = status; }
}

// https://www.twilio.com/docs/phone-numbers/api
export function twilioNumbers(accountSID: string, authToken: string, fetcher: typeof fetch = fetch): NumberProvider {
  const base = `https://api.twilio.com/2010-04-01/Accounts/${accountSID}`;
  const authorization = `Basic ${Buffer.from(`${accountSID}:${authToken}`).toString("base64")}`;
  const call = async (path: string, form?: URLSearchParams) => {
    const response = await fetcher(base + path, { method: form ? "POST" : "GET", body: form, redirect: "error", signal: AbortSignal.timeout(15_000),
      headers: { authorization, ...(form ? { "content-type": "application/x-www-form-urlencoded" } : {}) } });
    // Twilio's error text can include the number, so only the status is kept.
    if (!response.ok) throw new TwilioError(response.status);
    return await response.json() as Record<string, unknown>;
  };
  const list = (value: unknown) => Array.isArray(value) ? value as Record<string, unknown>[] : [];
  const owned = (n: Record<string, unknown> | undefined): OwnedNumber | undefined =>
    n && typeof n.sid === "string" && /^PN[0-9a-f]{32}$/.test(n.sid) && typeof n.phone_number === "string" && usNumber.test(n.phone_number)
      ? { sid: n.sid, number: n.phone_number } : undefined;
  return {
    async search(query) {
      const params = new URLSearchParams({ VoiceEnabled: "true", PageSize: "10" });
      if ("areaCode" in query) params.set("AreaCode", query.areaCode);
      else { params.set("NearLatLong", `${query.near.latitude.toFixed(4)},${query.near.longitude.toFixed(4)}`); params.set("Distance", "50"); }
      const body = await call(`/AvailablePhoneNumbers/US/Local.json?${params}`);
      return list(body.available_phone_numbers).flatMap(n => typeof n.phone_number === "string" && usNumber.test(n.phone_number)
        ? [{ number: n.phone_number, ...(typeof n.locality === "string" ? { locality: n.locality } : {}), ...(typeof n.region === "string" ? { region: n.region } : {}) }] : []);
    },
    async buy(number, options) {
      let body: Record<string, unknown>;
      try { body = await call("/IncomingPhoneNumbers.json", new URLSearchParams({ PhoneNumber: number, VoiceUrl: options.voiceURL, VoiceMethod: "POST", SmsUrl: options.smsURL, SmsMethod: "POST", FriendlyName: options.label })); }
      // A 4xx is Twilio saying no. A 5xx or a timeout may still have sold it.
      catch (error) { throw error instanceof TwilioError && error.status < 500 ? new PurchaseRefused(error.message) : error; }
      const bought = owned(body);
      if (!bought) throw new Error("Twilio didn't return the number it sold.");
      return bought;
    },
    async find(name) {
      const body = await call(`/IncomingPhoneNumbers.json?${new URLSearchParams({ FriendlyName: name, PageSize: "20" })}`);
      return owned(list(body.incoming_phone_numbers).find(n => n.friendly_name === name));
    },
  };
}

export function numberServices(settings: NumberSettings): NumberServices {
  const configuration = config();
  return { provider: twilioNumbers(settings.accountSID, settings.authToken),
    sip: new SipClient(configuration.serverUrl.replace(/^wss:/, "https:"), configuration.apiKey, configuration.apiSecret, { requestTimeout: 10, failover: false }) };
}

// The SDK types list changes as its protocol class but sends their plain fields, which protobuf messages accept.
type ListUpdate = NonNullable<SipInboundTrunkUpdateOptions["numbers"]>;
const adding = (number: string) => ({ add: [number] }) as unknown as ListUpdate;

/** A short lock, since the store can't delete: a claim that has expired or been given back is taken over by compare-and-set. */
async function claim(store: FamilyStore, key: string, now: number, seconds: number): Promise<string | undefined> {
  const value = JSON.stringify({ until: now + seconds, id: randomUUID() });
  if (await store.create(key, value, seconds)) return value;
  const current = await store.get(key);
  if (current === null) return await store.create(key, value, seconds) ? value : undefined;
  return (JSON.parse(current) as { until: number }).until <= now && await store.compareAndSet(key, current, value) ? value : undefined;
}
async function giveBack(store: FamilyStore, key: string, value: string) {
  try { await store.compareAndSet(key, value, JSON.stringify({ until: 0 })); } catch { /* it expires anyway */ }
}

/** Counts the household against Porch's limit on numbers, once. */
export async function holdPlace(store: FamilyStore, householdID: string, limit: number) {
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(holdersKey);
    const holders: string[] = raw ? JSON.parse(raw) : [];
    if (holders.includes(householdID)) return;
    if (holders.length >= limit) throw new FamilyError("Porch can't set up more phone numbers right now. Try again later.", 503, "numberLimit");
    const updated = JSON.stringify([...holders, householdID]);
    if (raw ? await store.compareAndSet(holdersKey, raw, updated) : await store.create(holdersKey, updated)) return;
  }
  throw new FamilyError("Porch is busy. Please try again.", 409);
}
/** Gives back a place no number came of. */
async function givePlaceBack(store: FamilyStore, householdID: string) {
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(holdersKey);
    const holders: string[] = raw ? JSON.parse(raw) : [];
    if (!raw || !holders.includes(householdID)) return;
    if (await store.compareAndSet(holdersKey, raw, JSON.stringify(holders.filter(id => id !== householdID)))) return;
  }
}

/** The LiveKit inbound trunk every bought number shares, made with the first one. It takes calls only from Porch's
 * voice webhook, which signs in with the same digest login as voicemail mode (configure-inbound.mjs --voicemail).
 * A trunk with no numbers would take calls to any number, so it's never made empty. */
async function sharedInboundTrunk(store: FamilyStore, sip: NumberServices["sip"], number: string, now: number, apiSecret: string): Promise<string> {
  const attach = async (id: string) => { await sip.updateSipInboundTrunkFields(id, { numbers: adding(number) }); return id; };
  const existing = await store.get(sharedTrunkKey);
  if (existing) return attach(existing);
  // Held across the LiveKit calls. Two households can both see no trunk; the one that gets the lock second
  // must use the trunk the other just saved, not make a second one and put this number on both.
  const lock = await claim(store, `${sharedTrunkKey}:lock`, now, 180);
  requireValue(lock, "Porch is setting up phone numbers. It will try again shortly.", 409);
  try {
    const won = await store.get(sharedTrunkKey);
    if (won) return attach(won);
    const rules = await sip.listSipDispatchRule();
    // A rule without trunks would send these calls, and every other household's, to rooms of its own.
    if (rules.some(rule => rule.trunkIds.length === 0)) throw new Error("A wildcard SIP dispatch rule needs reviewing first.");
    // A trunk made by a try that stopped before saving its ID.
    const halfMade = (await sip.listSipInboundTrunk()).find(trunk => trunk.name === sharedTrunkName);
    const login = sipInboundCredentials(apiSecret);
    let trunk = halfMade ?? await sip.createSipInboundTrunk(sharedTrunkName, [number], { authUsername: login.username, authPassword: login.password,
      ringingTimeout: inboundRingLimitSeconds, headersToAttributes: { [forwardedVerificationHeader]: callerVerificationAttribute } });
    // Replace clears any field left out, and listing a trunk can come back without its password. Set the voicemail
    // login again, as the setup script does. Create can't set a call limit. It's not in use until saved below.
    trunk.numbers = [...new Set([...trunk.numbers, number])];
    trunk.authUsername = login.username; trunk.authPassword = login.password; trunk.allowedAddresses = [];
    trunk.headersToAttributes = { [forwardedVerificationHeader]: callerVerificationAttribute };
    trunk.ringingTimeout = new SIPInboundTrunkInfo({ ringingTimeout: { seconds: BigInt(inboundRingLimitSeconds) } }).ringingTimeout;
    trunk.maxCallDuration = new SIPInboundTrunkInfo({ maxCallDuration: { seconds: 1800n } }).maxCallDuration;
    trunk = await sip.updateSipInboundTrunk(trunk.sipTrunkId, trunk);
    if (!rules.some(rule => rule.trunkIds.includes(trunk.sipTrunkId))) {
      await sip.createSipDispatchRule({ type: "individual", roomPrefix: inboundRoomPrefix }, { name: sharedTrunkName, trunkIds: [trunk.sipTrunkId], hidePhoneNumber: false,
        roomConfig: new RoomConfiguration({ maxParticipants: 2, emptyTimeout: 60, departureTimeout: 5 }) });
    }
    if (!await store.create(sharedTrunkKey, trunk.sipTrunkId)) requireValue(await store.get(sharedTrunkKey) === trunk.sipTrunkId, "Porch's phone trunks disagree. Check LiveKit before trying again.", 409);
    return trunk.sipTrunkId;
  } finally { await giveBack(store, `${sharedTrunkKey}:lock`, lock); }
}

/** Buys, routes and saves the household's number for its `phoneSetup` area code. Each step can be repeated, so a later
 * try picks up where a failed or interrupted one stopped, and the saved order keeps a bought number from being bought twice.
 * Returns the household, without a number if another request is setting it up right now. */
export async function ensurePorchNumber(store: FamilyStore, householdID: string, now: number, settings: NumberSettings, services: NumberServices): Promise<Household> {
  const read = async () => {
    const raw = await store.get(`house:${householdID}`);
    requireValue(raw, "This household was not found.", 404);
    return JSON.parse(raw) as Household;
  };
  // The bedside polls every couple of seconds, and each poll can queue a try from the household it read.
  // A try that already moved the wait, or asked for another area code, has to be the last one to buy.
  let house = await read();
  if (house.porchNumber) return house;
  // Not due: the last try asked for another area code, or its wait has not finished. A missing setup is a caller error.
  if (!porchNumberDue(house, now)) {
    requireValue(house.members.some(m => m.role === "bedside" && !m.revoked) && house.phoneSetup, "Choose an area code for this Porch's number on the bedside iPad.", 409);
    return house;
  }
  const lockKey = `number-lock:${householdID}`, lock = await claim(store, lockKey, now, 90);
  if (!lock) return house;
  try {
    house = await read();
    if (house.porchNumber || !porchNumberDue(house, now)) return house;
    const bedside = house.members.find(m => m.role === "bedside" && !m.revoked);
    requireValue(bedside && house.phoneSetup, "Choose an area code for this Porch's number on the bedside iPad.", 409);
    const { areaCode } = house.phoneSetup;
    const orderKey = `number-order:${householdID}`;
    let order: OwnedNumber | null = JSON.parse(await store.get(orderKey) ?? "null");
    if (!order) {
      // A purchase can go through even when its response is lost.
      order = await services.provider.find(label(householdID)) ?? null;
      if (!order) {
        const [choice] = await services.provider.search({ areaCode });
        if (!choice) throw new FamilyError(`There are no numbers in area code ${areaCode} right now. Try a nearby area code.`, 409, "noNumbers");
        // Counted only now, so a search that finds nothing, or fails, holds no place. A purchase Twilio turned down
        // gives it back. One whose outcome is unknown, such as a timeout, keeps it: Twilio may have sold the number.
        await holdPlace(store, householdID, settings.limit);
        try { order = await services.provider.buy(choice.number, { voiceURL: settings.voiceURL, smsURL: settings.smsURL, label: label(householdID) }); }
        catch (error) {
          if (error instanceof PurchaseRefused) { try { await givePlaceBack(store, householdID); } catch { /* the next try counts it again */ } }
          throw error;
        }
      }
      if (!await store.create(orderKey, JSON.stringify(order))) order = JSON.parse((await store.get(orderKey))!) as OwnedNumber;
    }
    // A number that already rings someone else must not be added to the shared trunks first. A retry would
    // keep adding it, and LiveKit could deliver those calls to either trunk.
    const routeKey = `phone-number:${order.number}`;
    const claimed = await store.get(routeKey);
    if (claimed) requireValue((JSON.parse(claimed) as InboundRoute).householdID === householdID, "This number already rings another Porch. Check its route before trying again.", 409);
    const trunkID = await sharedInboundTrunk(store, services.sip, order.number, now, settings.apiSecret);
    await services.sip.updateSipOutboundTrunkFields(settings.outboundTrunkID, { numbers: adding(order.number) });
    const route: InboundRoute = { householdID, bedsideID: bedside.id, trunkID };
    if (!await store.create(routeKey, JSON.stringify(route))) {
      const existing: InboundRoute = JSON.parse((await store.get(routeKey))!);
      requireValue(existing.householdID === householdID, "This number already rings another Porch. Check its route before trying again.", 409);
    }
    const bought = order;
    const { house: saved } = await mutate(store, householdID, latest => {
      latest.porchNumber ??= { number: bought.number, sid: bought.sid, assignedAt: now };
      delete latest.phoneSetup;
    });
    return saved;
  } catch (error) {
    try {
      await mutate(store, householdID, latest => {
        if (latest.porchNumber || !latest.phoneSetup) return;
        const attempts = latest.phoneSetup.attempts + 1;
        // No inventory is the caregiver's to resolve. Leaving a retry would buy that area code later, after they
        // were told to choose another. Anything else, including the number limit, keeps its growing wait.
        const needsChoice = error instanceof FamilyError && error.code === "noNumbers";
        latest.phoneSetup = { areaCode: latest.phoneSetup.areaCode, attempts, retryAt: needsChoice ? latest.phoneSetup.retryAt : now + retrySeconds(attempts),
          error: error instanceof FamilyError ? error.message : "Porch couldn't get a phone number yet. It will keep trying.",
          ...(needsChoice ? { needsChoice: true } : {}) };
      });
    } catch { /* the next try records it */ }
    throw error;
  } finally { await giveBack(store, lockKey, lock); }
}

/** Area codes with numbers near the iPad, from where Vercel places its internet address. Nothing outside the US. */
async function nearbyAreaCodes(headers: Headers, provider: NumberProvider): Promise<{ areaCode: string | null; nearby: string[] }> {
  const latitude = Number(headers.get("x-vercel-ip-latitude") ?? NaN), longitude = Number(headers.get("x-vercel-ip-longitude") ?? NaN);
  if (headers.get("x-vercel-ip-country") !== "US" || !Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
    return { areaCode: null, nearby: [] };
  }
  try {
    const codes = [...new Set((await provider.search({ near: { latitude, longitude } })).map(n => n.number.slice(2, 5)))];
    return { areaCode: codes[0] ?? null, nearby: codes.slice(0, 4) };
  } catch { return { areaCode: null, nearby: [] }; } // The caregiver types one instead.
}

/** Caregiver actions on the bedside, PIN-checked before this point. */
export async function handleNumberAction(action: string, { store, now, house, me, input, headers, services }: NumberContext): Promise<object> {
  requireValue(me.role === "bedside", "Set up this Porch's phone number on the bedside iPad.", 403);
  if (house.porchNumber) return { porchNumber: house.porchNumber.number };
  // A household set up by hand, like the first one, keeps the number it has. Only provision-number.mjs records it,
  // so the app can never buy it a new one.
  if (!house.numberFromSetup) throw new FamilyError("This Porch's phone number was set up by hand, so it can't be changed here.", 403, "numberSetByHand");
  const settings = numberSettings();
  requireValue(settings, "Porch phone numbers aren't set up on this server yet.", 503);
  const resolved = (services ?? numberServices)(settings);
  if (action === "phoneNumberOptions") return await nearbyAreaCodes(headers, resolved.provider);
  const areaCode = input.areaCode;
  requireValue(typeof areaCode === "string" && areaCodePattern.test(areaCode), "Enter a three-digit US area code.");
  // Asking again tries right away, with the area code chosen now.
  await mutate(store, house.id, latest => { if (!latest.porchNumber) latest.phoneSetup = { areaCode, attempts: 0, retryAt: now }; });
  try {
    const saved = await ensurePorchNumber(store, house.id, now, settings, resolved);
    return saved.porchNumber ? { porchNumber: saved.porchNumber.number } : { pending: true };
  } catch (error) {
    // Another area code, or Porch's limit, needs the caregiver. Porch keeps trying anything else itself.
    if (error instanceof FamilyError && (error.code === "noNumbers" || error.code === "numberLimit")) throw error;
    return { pending: true };
  }
}

/** Whether the bedside's poll should try again now for a number that isn't set up yet. */
export function porchNumberDue(house: Household, now: number): boolean {
  return !house.porchNumber && !!house.phoneSetup && !house.phoneSetup.needsChoice && house.phoneSetup.retryAt <= now;
}

/** The bedside's poll tries again for a number that isn't set up yet, once its wait is over.
 * The household is read again here: the poll that queued this try may have loaded it before another try finished. */
export async function retryPorchNumber(store: FamilyStore, house: Household, now: number, services?: (settings: NumberSettings) => NumberServices): Promise<Household | undefined> {
  try {
    const raw = await store.get(`house:${house.id}`);
    const latest: Household | undefined = raw ? JSON.parse(raw) as Household : undefined;
    if (!latest || !porchNumberDue(latest, now)) return undefined;
    const settings = numberSettings();
    if (!settings) return undefined;
    return await ensurePorchNumber(store, house.id, now, settings, (services ?? numberServices)(settings));
  } catch { return undefined; } // Recorded on the household for the next try.
}

/** What the bedside and caregivers see of a number still being set up. */
export function publicPhoneSetup(house: Household) {
  const setup = house.phoneSetup;
  return setup && !house.porchNumber ? { areaCode: setup.areaCode, ...(setup.error ? { error: setup.error } : {}), ...(setup.needsChoice ? { needsChoice: true } : {}) } : undefined;
}
