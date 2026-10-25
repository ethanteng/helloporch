import { randomUUID } from "node:crypto";
import { RoomServiceClient, SipClient } from "livekit-server-sdk";
import type { CallServer } from "../calls/server.ts";
import { activePhoneGuest, callRoom, displayName, expire, FamilyError, mutate, phoneGuestIdentity, requireValue, type Call, type Household, type Member, type PhoneGuest } from "./household.ts";
import type { FamilyStore } from "./store.ts";

// Three-way calls with a regular phone: a family caregiver talking with the bedside can dial a number, such as a bank
// that needs Mom on the line, into the same LiveKit room. The telephone leg belongs to whoever added it. It hangs up
// when they leave, and the bedside is never left alone with it.
export const phoneGuestActions = new Set(["addPhoneGuest", "removePhoneGuest"]);
/** Bank hold times run long, so a call with a phone guest lasts up to an hour from when the number was added. */
export const phoneGuestLimits = { perCall: 5, label: 40, ringSeconds: 60, callSeconds: 3600 };
export type PhoneGuestServices = {
  rooms: Pick<RoomServiceClient, "getParticipant" | "removeParticipant">;
  sip: Pick<SipClient, "createSipParticipant">;
};
export type PhoneGuestContext = { store: FamilyStore; now: number; house: Household; me: Member; input: Record<string, unknown>;
  services: PhoneGuestServices; endRoom: (room: string) => Promise<void> };

export function phoneGuestServices(configuration: CallServer): PhoneGuestServices {
  const host = configuration.serverUrl.replace(/^wss:/, "https:");
  return {
    rooms: new RoomServiceClient(host, configuration.apiKey, configuration.apiSecret, { requestTimeout: 8 }),
    sip: new SipClient(host, configuration.apiKey, configuration.apiSecret, { requestTimeout: 10, failover: false }),
  };
}

// +1 numbers in the US and Canada, including toll-free. The same country code reaches Caribbean nations and Bermuda at
// international rates, and a few codes are premium-rate or special services; those can't be dialed. Twilio's
// geographic permissions on the trunk remain the backstop.
const northAmericanNumber = /^\+1([2-9][0-9]{2})([2-9][0-9]{2})[0-9]{4}$/;
const blockedAreaCodes = new Set(["242", "246", "264", "268", "284", "345", "441", "473", "649", "658", "664", "721", "758", "767", "784", "809", "829", "849", "868", "869", "876",
  "456", "500", "533", "544", "566", "577", "588", "600", "700", "710", "880", "881", "882", "900"]);
export function dialableNumber(value: unknown): value is string {
  const match = typeof value === "string" ? northAmericanNumber.exec(value) : null;
  return !!match && !blockedAreaCodes.has(match[1]) && !match[1].endsWith("11") && match[2] !== "976";
}
/** Only caregivers can dial a number Porch hasn't approved, and only while they are talking with the bedside. */
export function canAddPhoneGuests(me: Member): boolean {
  return me.role === "family" && me.caregiver === true && !me.revoked && !!process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;
}
/** What a device on the call sees of its phone guest. Only the person who added it sees the number. */
export function publicPhoneGuest(call: Call, me: Member) {
  const guest = activePhoneGuest(call);
  return guest && { id: guest.id, label: guest.label, addedBy: guest.addedBy, ...(guest.addedBy === me.id ? { number: guest.number } : {}) };
}

// LiveKit (Twirp) error codes for a dial request it rejected outright, before starting any telephone leg.
const refusedDial = new Set(["invalid_argument", "not_found", "permission_denied", "failed_precondition", "unauthenticated", "resource_exhausted"]);
function notFound(error: unknown) {
  return !!error && typeof error === "object" && "code" in error && error.code === "not_found";
}
/** Whether this identity is in the room. A telephone leg that has hung up no longer counts. */
export async function inRoom(rooms: PhoneGuestServices["rooms"], room: string, identity: string): Promise<boolean> {
  try { return (await rooms.getParticipant(room, identity)).attributes?.["sip.callStatus"] !== "hangup"; }
  catch (error) { if (notFound(error)) return false; throw error; }
}
async function endGuest(store: FamilyStore, householdID: string, callID: string, guestID: string, now: number) {
  await mutate(store, householdID, house => {
    const guest = house.call?.id === callID ? house.call.guests?.find(g => g.id === guestID) : undefined;
    if (guest && !guest.endedAt) guest.endedAt = now;
  });
}
/** Once an ended call's room is deleted, none of its phone guests can still be connected. */
export async function endPhoneGuests(store: FamilyStore, householdID: string, callID: string, now: number) {
  await mutate(store, householdID, house => {
    if (house.call?.id === callID) for (const guest of house.call.guests ?? []) guest.endedAt ??= now;
  });
}
/** A dial that already failed can still create its leg until ringing gives up, plus a little slack. */
export const phoneGuestReapSeconds = phoneGuestLimits.ringSeconds + 30;
/** Drop a leg that connects after its guest was already ended, so it can't sit on the call untracked.
 * A missing participant is the usual case. Anything else is left for the next poll. */
export async function reapEndedPhoneGuests(rooms: PhoneGuestServices["rooms"], call: Call, now: number) {
  if (call.state === "ended") return;
  const room = callRoom(call);
  for (const guest of call.guests ?? []) {
    if (guest.endedAt === undefined || now - guest.endedAt > phoneGuestReapSeconds) continue;
    try { await rooms.removeParticipant(room, phoneGuestIdentity(guest)); }
    catch (error) { if (!notFound(error)) return; }
  }
}
async function reapStoredPhoneGuests(context: PhoneGuestContext) {
  const raw = await context.store.get(`house:${context.house.id}`);
  const live = raw ? (JSON.parse(raw) as Household).call : undefined;
  if (live) await reapEndedPhoneGuests(context.services.rooms, live, context.now);
}

export async function handlePhoneGuestAction(action: string, context: PhoneGuestContext) {
  const { store, now, house, me, input, services } = context;
  const call = house.call;
  requireValue(call && call.id === input.callID && [call.from, call.to].includes(me.id) && !call.phone, "This call is no longer available.", 404);
  const room = callRoom(call);
  if (action === "removePhoneGuest") {
    const guest = call.guests?.find(g => g.id === input.guestID);
    requireValue(guest, "This phone number is no longer on the call.", 404);
    requireValue(guest.addedBy === me.id, "Only the person who added this number can hang it up.", 403);
    if (!guest.endedAt) {
      try { await services.rooms.removeParticipant(room, phoneGuestIdentity(guest)); }
      catch (error) { if (!notFound(error)) throw new FamilyError("Couldn't hang up the phone. Check your connection and try again.", 502); }
      await endGuest(store, house.id, call.id, guest.id, now);
    }
    return { removed: true };
  }

  requireValue(me.role === "family" && me.caregiver === true, "Only a caregiver can add a phone number to a call.", 403);
  const trunk = process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;
  requireValue(trunk, "Adding a phone number isn't set up on this server yet.", 503);
  requireValue(call.state === "accepted" && call.expiresAt > now && call.left?.[me.id] === undefined, "Add a phone number once you're both on the call.", 409);
  requireValue(dialableNumber(input.phoneNumber), "Enter a US or Canadian phone number with its area code.");
  const label = typeof input.label === "string" ? input.label.trim() : "";
  requireValue(label.length > 0 && label.length <= phoneGuestLimits.label, `Name who you're calling in up to ${phoneGuestLimits.label} characters, such as "Bank".`);
  const bedside = house.members.find(m => m.role === "bedside" && [call.from, call.to].includes(m.id));
  requireValue(bedside, "This call is no longer available.", 404);
  requireValue(call.left?.[bedside.id] === undefined, `${displayName(bedside)} has left this call.`, 409);
  // Don't ring anybody until both of you are actually in the call.
  requireValue(await inRoom(services.rooms, room, bedside.id) && await inRoom(services.rooms, room, me.id),
    `Porch can add a phone number once you and ${displayName(bedside)} are both connected.`, 409);
  // A guest that hung up (busy, no answer, or the far end ended the call) makes way for another number.
  // `inRoom` treats a hang-up status as already gone, so remove the leg too; a timed-out dial can
  // still connect after this, and reapEndedPhoneGuests drops that late leg on a later poll.
  const previous = activePhoneGuest(call);
  if (previous) {
    const previousIdentity = phoneGuestIdentity(previous);
    requireValue(!await inRoom(services.rooms, room, previousIdentity), `Hang up ${previous.label} before adding another number.`, 409);
    try { await services.rooms.removeParticipant(room, previousIdentity); }
    catch (error) { if (!notFound(error)) throw new FamilyError("Couldn't hang up the phone. Check your connection and try again.", 502); }
  }

  const { result: guest } = await mutate(store, house.id, current => {
    expire(current, now);
    const live = current.call, adder = current.members.find(m => m.id === me.id);
    requireValue(live?.id === call.id && live.state === "accepted" && live.left?.[me.id] === undefined && live.left?.[bedside.id] === undefined, "This call ended.", 410);
    requireValue(adder && !adder.revoked && adder.caregiver === true, "Only a caregiver can add a phone number to a call.", 403);
    const guests = live.guests ??= [];
    const stale = previous && guests.find(g => g.id === previous.id);
    if (stale) stale.endedAt ??= now;
    requireValue(!activePhoneGuest(live), "Another phone number is already being added.", 409);
    requireValue(guests.length < phoneGuestLimits.perCall, "This call can't add more phone numbers. Start a new call to add another.", 429);
    const added: PhoneGuest = { id: randomUUID(), number: input.phoneNumber as string, label, addedBy: me.id, addedAt: now };
    guests.push(added);
    return added;
  });
  const identity = phoneGuestIdentity(guest);
  try {
    await services.sip.createSipParticipant(trunk, guest.number, room, {
      participantIdentity: identity, participantName: label,
      // The household's own number, so the bank sees which Porch called and calling back rings it.
      ...(house.porchNumber ? { fromNumber: house.porchNumber.number } : {}),
      // Everyone on the call hears it ring, as on a regular three-way call.
      hidePhoneNumber: true, playDialtone: true, waitUntilAnswered: false,
      ringingTimeout: phoneGuestLimits.ringSeconds, maxCallDuration: phoneGuestLimits.callSeconds, timeout: 10,
    });
  } catch (error) {
    // A refused request created no leg. Any other failure, such as a timeout, may still create one after
    // this removal finds nothing, so the guest stays tracked: ending the call deletes its room, and the
    // caregiver's app hangs it up if it never appears.
    try { await services.rooms.removeParticipant(room, identity); } catch { /* usually it doesn't exist */ }
    const code = error && typeof error === "object" && "code" in error ? String(error.code) : "";
    if (refusedDial.has(code)) await endGuest(store, house.id, call.id, guest.id, now);
    try { await reapStoredPhoneGuests(context); } catch { /* the next poll tries again */ }
    throw new FamilyError("Couldn't call that number. Check it and try again.", 502);
  }
  // Ending the call or hanging up the guest can race with dialing. Release a leg that arrived too late.
  const raw = await store.get(`house:${house.id}`);
  const live = raw ? (JSON.parse(raw) as Household).call : undefined;
  if (live?.id !== call.id || live.state === "ended") {
    // Only mark the guests ended after the room is gone. A failed delete has to stay retryable,
    // which later polls do while a phone guest is still active.
    try {
      await context.endRoom(room);
      await endPhoneGuests(store, house.id, call.id, now);
    } catch { /* the next poll deletes the room */ }
    throw new FamilyError("The call ended before the phone could be added.", 409);
  }
  if (live.guests?.find(g => g.id === guest.id)?.endedAt) {
    try { await services.rooms.removeParticipant(room, identity); } catch { /* the room's call limit ends it */ }
    try { await reapStoredPhoneGuests(context); } catch { /* the next poll tries again */ }
    throw new FamilyError("That phone number was hung up.", 409);
  }
  // The number this one replaced may have connected while it was dialing.
  try { await reapStoredPhoneGuests(context); } catch { /* the next poll tries again */ }
  // Only a number that actually dialed lengthens the call.
  await mutate(store, house.id, current => {
    const dialed = current.call;
    if (dialed?.id === call.id && dialed.state === "accepted" && activePhoneGuest(dialed)?.id === guest.id) {
      dialed.expiresAt = Math.max(dialed.expiresAt, now + phoneGuestLimits.callSeconds);
    }
  });
  return { phoneGuest: { id: guest.id, label, addedBy: me.id, number: guest.number } };
}
