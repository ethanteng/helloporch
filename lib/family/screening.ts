import { isCaregiver, mutate, phoneDropIn, requireValue, FamilyError, type BlockedCaller, type Household, type Member } from "./household.ts";
import type { FamilyStore } from "./store.ts";

// Blocking unknown callers: while a caregiver has it on, a regular phone call rings the bedside only when its
// caller ID is saved on the keypad, approved for phone drop-in, or allowed by a caregiver. Every other number
// that calls is listed as blocked until a caregiver allows it. Caller ID alone decides, so a faked number gets through.
export const screeningActions = new Set(["setKeypadNumbers", "setBlockUnknownCallers", "setCallerAllowed", "clearBlockedCallers"]);
/** Ten keys with up to five numbers each (`CallContact.maximumPhoneNumbers`). The blocked list keeps this many
 * numbers that still can't ring. Numbers that can ring stay recorded, so removing that permission brings their
 * calls back, but they don't take a slot from the numbers a caregiver still has to review. */
export const callerLimits = { keypad: 50, allowed: 50, blocked: 30 };
/** Twilio's stand-ins for withheld, restricted and unavailable caller ID. They aren't real numbers. */
export const withheldCallerNumbers = new Set(["+266696687", "+7378742833", "+2562533", "+8656696", "+86282452253"]);
export type ScreeningContext = { store: FamilyStore; now: number; house: Household; me: Member; input: Record<string, unknown> };
const numberPattern = /^\+[1-9][0-9]{6,14}$/;

/** A caller ID that can be saved or listed. Withheld placeholders never can, even if someone typed one in. */
function listedCallerNumber(number?: string): string | undefined {
  return number && !withheldCallerNumbers.has(number) ? number : undefined;
}
export function knownCaller(house: Household, number?: string): boolean {
  const caller = listedCallerNumber(number);
  return !!caller && (!!house.keypadNumbers?.includes(caller) || !!house.allowedCallers?.some(c => c.number === caller) || !!phoneDropIn(house, caller));
}
/** Whether a regular phone call may ring the bedside. With unknown callers blocked, withheld caller ID never does. */
export function callerAllowed(house: Household, number?: string): boolean {
  return !house.blockUnknownCallers || knownCaller(house, number);
}
/** Lists a blocked call, newest first. Withheld numbers can't be allowed, so they aren't listed. */
export function recordBlockedCall(house: Household, number: string | undefined, now: number) {
  if (!number) return;
  const list = house.blockedCallers ??= [];
  const entry = list.find(c => c.number === number);
  if (entry) { entry.lastCallAt = now; entry.calls += 1; }
  else list.push({ number, firstCallAt: now, lastCallAt: now, calls: 1 });
  pruneBlockedCallers(house);
}
/** Drops the oldest numbers that still can't ring once the visible list is full. Numbers that can ring are kept. */
export function pruneBlockedCallers(house: Household) {
  const list = house.blockedCallers;
  if (!list?.length) return;
  list.sort((a, b) => b.lastCallAt - a.lastCallAt);
  const kept: BlockedCaller[] = [];
  let visible = 0;
  for (const entry of list) {
    if (knownCaller(house, entry.number)) kept.push(entry);
    else if (visible < callerLimits.blocked) { kept.push(entry); visible += 1; }
  }
  house.blockedCallers = kept;
}
/** Records one blocked call, however often its webhook is delivered. `callKey` names the call (Twilio's CallSid or LiveKit's room). */
export async function blockCall(store: FamilyStore, householdID: string, callKey: string, number: string | undefined, now: number) {
  // Withheld caller ID has nothing a caregiver can allow, so it isn't listed.
  const caller = listedCallerNumber(number);
  if (!caller || !await store.create(`blocked-call:${callKey}`, "1", 86400)) return;
  // Allowed meanwhile: nothing for a caregiver to do.
  await mutate(store, householdID, house => { if (!callerAllowed(house, caller)) recordBlockedCall(house, caller, now); });
}
/** Caregiver data: only the bedside and PIN-checked admin state carry it. */
export function publicCallScreening(house: Household) {
  return { enabled: !!house.blockUnknownCallers, keypadNumbers: house.keypadNumbers ?? null, allowed: house.allowedCallers ?? [],
    // A number saved or allowed since it called no longer needs a caregiver; it shows again if that changes.
    blocked: (house.blockedCallers ?? []).filter(c => !knownCaller(house, c.number)) };
}

function phoneNumber(value: unknown): string {
  requireValue(typeof value === "string" && numberPattern.test(value), "Enter the phone number with + and the country code, such as +14155550123.");
  return value;
}
function number(value: unknown): string {
  const caller = phoneNumber(value);
  // A withheld placeholder isn't a number a caregiver can allow. Saving it on the keypad is harmless:
  // knownCaller never treats it as someone who may ring.
  requireValue(!withheldCallerNumbers.has(caller), "That caller ID is withheld and can't be allowed.");
  return caller;
}

/** Caregiver actions, PIN-checked before this point. */
export async function handleScreeningAction(action: string, { store, now, house, me, input }: ScreeningContext): Promise<object> {
  if (action === "setKeypadNumbers") {
    // Keypad contacts live on the iPad, which reports their numbers whenever they change.
    requireValue(me.role === "bedside", "Only the bedside can report its keypad contacts.", 403);
    requireValue(Array.isArray(input.numbers) && input.numbers.length <= callerLimits.keypad, "Send the keypad's phone numbers.");
    const numbers = [...new Set(input.numbers.map(phoneNumber))].sort();
    await mutate(store, house.id, latest => { latest.keypadNumbers = numbers; pruneBlockedCallers(latest); });
    return {};
  }
  if (action === "setBlockUnknownCallers") {
    requireValue(typeof input.enabled === "boolean", "Choose whether unknown callers are blocked.");
    const enabled = input.enabled;
    await mutate(store, house.id, latest => {
      requireValue(latest.members.some(m => m.id === me.id && !m.revoked && isCaregiver(m)), "Only an approved caregiver can change access.", 403);
      // Until the iPad has reported its keypad, blocking would turn away the people saved on it.
      if (enabled && !latest.keypadNumbers) throw new FamilyError("Open Porch on the bedside iPad so it can share its keypad contacts, then try again.", 409);
      latest.blockUnknownCallers = enabled;
    });
    return {};
  }
  if (action === "setCallerAllowed") {
    const allowed = input.allowed, caller = number(input.number);
    requireValue(typeof allowed === "boolean", "Choose whether this number can call.");
    await mutate(store, house.id, latest => {
      requireValue(latest.members.some(m => m.id === me.id && !m.revoked && isCaregiver(m)), "Only an approved caregiver can change access.", 403);
      const others = (latest.allowedCallers ?? []).filter(c => c.number !== caller);
      if (allowed) {
        requireValue(others.length < callerLimits.allowed, "Remove an allowed number before allowing another.");
        others.push(latest.allowedCallers?.find(c => c.number === caller) ?? { number: caller, allowedAt: now });
      }
      latest.allowedCallers = others;
      pruneBlockedCallers(latest);
    });
    return {};
  }
  // clearBlockedCallers
  await mutate(store, house.id, latest => {
    requireValue(latest.members.some(m => m.id === me.id && !m.revoked && isCaregiver(m)), "Only an approved caregiver can change access.", 403);
    delete latest.blockedCallers;
  });
  return {};
}
