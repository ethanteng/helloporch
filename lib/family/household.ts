import type { CallServer } from "../calls/server.ts";
import type { FamilyStore } from "./store.ts";
import type { VoIPRegistration } from "./push.ts";

export type Role = "bedside" | "family";
export type Mode = "voice" | "video";
export type Permissions = { audio: boolean; video: boolean };
/** A JPEG in the private media store. `id` is the SHA-256 of its bytes, which devices check after downloading. */
export type ProfilePhoto = { id: string; pathname: string };
/** How a family member appears on Porch: the name and photo they chose, or ones a caregiver chose for them. */
export type Profile = { name?: string; photo?: ProfilePhoto };
/** A photo upload the server signed that hasn't been saved yet; deleted once `expiresAt` passes. */
export type PendingPhoto = { pathname: string; expiresAt: number };
/** `name` is the name the caregiver gave the invitation. `profile` is the member's own choice and `override` a caregiver's.
 * `autoDropIn`: a caregiver had this family member's ordinary calls to the bedside drop in (see `callKind`). */
export type Member = { voip?: VoIPRegistration; alerts?: VoIPRegistration; invitationID?: string; caregiver?: boolean; autoDropIn?: boolean; id: string; name: string; role: Role; secretHash: string; permissions: Permissions; revoked: boolean; seenAt: number; available: boolean; profile?: Profile; override?: Profile; pendingPhotos?: PendingPhoto[] };
export type Invite = { id: string; secretHash: string; name: string; permissions: Permissions; caregiver?: boolean; expiresAt: number; claimedBy?: string };
/** `guests`: regular phones a family caregiver added to an answered call with the bedside (see phone-guests.ts).
 * `porchGuests`: other family members rung into it on Porch (see porch-guests.ts).
 * `left`: when each of the call's two ends or a family guest hung up while the call went on without them. */
export type Call = { id: string; from: string; to: string; mode: Mode; kind: "call" | "dropIn"; state: "pending" | "accepted" | "ended"; createdAt: number; receivedAt?: number; announcedAt?: number; acceptedAt?: number; expiresAt: number; reason?: string; phone?: InboundPhone;
  guests?: PhoneGuest[]; porchGuests?: PorchGuest[]; left?: Record<string, number> };
/** A family member rung into a call with the bedside, such as a brother joining Mom and Ethan with video. `id` names
 * this invitation: their phone treats it as an incoming call of its own, which answering joins to the same room. */
export type PorchGuest = { id: string; memberID: string; addedBy: string; invitedAt: number; ringUntil: number;
  state: "ringing" | "joined" | "declined" | "missed" | "cancelled" | "left"; receivedAt?: number; joinedAt?: number; endedAt?: number };
/** A regular phone a family caregiver added to their call with the bedside, such as a bank that needs Mom on the line.
 * It stays only while the person who added it does. `label` is what the bedside shows; the number never reaches it.
 * `endedAt` is set once its telephone leg is known to be gone. */
export type PhoneGuest = { id: string; number: string; label: string; addedBy: string; addedAt: number; endedAt?: number };
export type MessageKind = "message" | "voicemail";
export type MessageMode = "audio" | "video";
/** A queued message. Kept in the household so the bedside's existing poll carries the queue.
 * Phone voicemails come from "phone" and are held until a caregiver releases them, or the bedside does for a
 * carrier-verified caller saved on its keypad. */
export type InboxEntry = { id: string; from: string; fromName: string; kind: MessageKind; mode: MessageMode; contentType: string; pathname: string; durationSeconds: number; sentAt: number; deliveredAt?: number; callerNumber?: string; callerVerified?: boolean; held?: boolean };
/** A message the bedside left for a family member who missed its call, until they play it. */
export type OutboxEntry = { id: string; to: string; sentAt: number };
/** A caregiver-approved telephone number that may drop in with audio when its caller ID is carrier-verified. */
export type PhoneDropIn = { number: string; name: string };
/** A caller ID that tried to ring the bedside while unknown callers were blocked, until a caregiver allows or clears it. */
export type BlockedCaller = { number: string; firstCallAt: number; lastCallAt: number; calls: number };
/** A number a caregiver allowed to ring the bedside although it isn't saved on the keypad. */
export type AllowedCaller = { number: string; allowedAt: number };
/** Characters sent to the speech service on one UTC day (days since 1970), to cap what a household spends. */
export type SpeechUsage = { day: number; characters: number };
/** The bedside's languages: `BedsideLanguage` raw values in the iPad app. */
export const bedsideLanguages = ["en", "zh-Hant", "zh-Hans", "yue-Hant", "es"] as const;
export type BedsideLanguage = (typeof bedsideLanguages)[number];
/** `speechVoices`: the caregiver's natural voice per bedside language, or null for the iPad's built-in voice; unset is the language's default.
 * `bedsideLanguage`: the language chosen on the iPad, as it last reported it; unset is English.
 * `blockUnknownCallers`: only known callers' phone calls ring the bedside (see screening.ts); unset is off.
 * `keypadNumbers`: the phone numbers saved on the bedside keypad, as the iPad last reported them; unset until it first does. */
export type Household = { id: string; name: string; dropInEnabled: boolean; members: Member[]; invites: Invite[]; call?: Call; messagesEnabled?: boolean; inbox?: InboxEntry[]; outbox?: OutboxEntry[]; purgeAt?: number; phoneDropIns?: PhoneDropIn[]; ringSeconds?: number; speechVoices?: Record<string, string | null>; speechUsage?: SpeechUsage; bedsideLanguage?: BedsideLanguage;
  blockUnknownCallers?: boolean; keypadNumbers?: string[]; allowedCallers?: AllowedCaller[]; blockedCallers?: BlockedCaller[] };
export type Auth = { householdID: string; deviceID: string; hash: string };
export type InboundPhone = { room: string; roomSID: string; participantIdentity: string; participantSID: string; trunkID: string; calledNumber: string; callerNumber?: string; checkedAt?: number; cleanedUp?: boolean };
export class FamilyError extends Error { status: number; code?: string; constructor(message: string, status = 400, code?: string) { super(message); this.status = status; this.code = code; } }
export function requireValue(condition: unknown, message: string, status = 400): asserts condition { if (!condition) throw new FamilyError(message, status); }
// A caregiver's choice comes first, then the member's own, then the invitation's name.
export function displayName(member: Member): string { return member.override?.name ?? member.profile?.name ?? member.name; }
export function displayPhoto(member: Member): ProfilePhoto | undefined { return member.override?.photo ?? member.profile?.photo; }
// The bedside device is always a caregiver; family devices need the caregiver's approval (and the PIN).
export function isCaregiver(member: Member) { return member.role === "bedside" || member.caregiver === true; }
export function config(): CallServer {
  const { LIVEKIT_URL: serverUrl, LIVEKIT_API_KEY: apiKey, LIVEKIT_API_SECRET: apiSecret } = process.env;
  requireValue(serverUrl?.startsWith("wss://") && apiKey && apiSecret, "Calling is not configured.", 503);
  return { serverUrl: serverUrl!, apiKey, apiSecret };
}
/** A call saved before leaving was recorded per person: the bedside had already hung up. */
function adoptBedsideLeft(house: Household) {
  const call = house.call as (Call & { bedsideLeftAt?: number }) | undefined;
  if (!call || call.bedsideLeftAt === undefined) return;
  const bedside = house.members.find(m => m.role === "bedside" && [call.from, call.to].includes(m.id));
  if (bedside) (call.left ??= {})[bedside.id] ??= call.bedsideLeftAt;
  delete call.bedsideLeftAt;
}
/** A family member still being rung can't answer a call that is already over. */
export function cancelRingingPorchGuests(call: Call | undefined, now: number) {
  for (const guest of call?.porchGuests ?? []) if (guest.state === "ringing") { guest.state = "cancelled"; guest.endedAt = now; }
}
export function finishCall(call: Call, reason: string, now: number) {
  call.state = "ended"; call.reason = reason; cancelRingingPorchGuests(call, now);
}
export function expire(house: Household, now: number) {
  const call = house.call;
  if (!call) return;
  adoptBedsideLeft(house);
  // The call can end in the same update that is still ringing someone in. A later check-in must not leave that
  // invitation looking answerable: their phone treats it as an ordinary incoming call.
  if (call.state === "ended") { cancelRingingPorchGuests(call, now); return; }
  const end = () => finishCall(call, "The call timed out or a device went offline.", now);
  if (call.expiresAt <= now) return end();
  for (const guest of call.porchGuests ?? []) if (guest.state === "ringing" && guest.ringUntil <= now) { guest.state = "missed"; guest.endedAt = now; }
  if (call.state !== "accepted") return;
  const lost = (id: string) => {
    const member = house.members.find(m => m.id === id);
    return !member || member.revoked || member.seenAt < now - 35;
  };
  if (call.phone) { if (lost(call.to)) end(); return; }
  // Someone whose device stops checking in has left. The call goes on only if it still could without them.
  const present = presentMembers(call), gone = present.filter(lost);
  if (!gone.length) return;
  if (!carriesOn(call, present.filter(id => !gone.includes(id)))) return end();
  for (const id of gone) leaveCall(call, id, now);
}
export async function mutate<T>(store: FamilyStore, id: string, change: (house: Household) => T): Promise<{ house: Household; result: T }> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(`house:${id}`);
    requireValue(raw, "This household was not found.", 404);
    const house: Household = JSON.parse(raw);
    const result = change(house);
    const updated = JSON.stringify(house);
    if (updated === raw || await store.compareAndSet(`house:${id}`, raw, updated)) return { house, result };
  }
  throw new FamilyError("Porch is busy. Please try again.", 409);
}

/** How long a call to the bedside rings, from the family app or a regular phone, before the caller is
 * offered voicemail (or, with messages off, the call ends). Caregivers choose it in Call preferences.
 * Drop-ins keep the standard time so the announcement and countdown, or a manual answer, still fit. */
export const ringLimits = { minimum: 15, maximum: 120, standard: 45 };
export function ringSeconds(house: Household, kind: Call["kind"] = "call"): number {
  return kind === "dropIn" ? ringLimits.standard : house.ringSeconds ?? ringLimits.standard;
}

export function isBedsideLanguage(value: unknown): value is BedsideLanguage {
  return typeof value === "string" && (bedsideLanguages as readonly string[]).includes(value);
}
/** The bedside's language, which phone voicemail greets callers in. */
export function bedsideLanguage(house: Household): BedsideLanguage {
  return isBedsideLanguage(house.bedsideLanguage) ? house.bedsideLanguage : "en";
}

export function callRoom(call: Call): string { return call.phone?.room ?? `porch-paired-${call.id}`; }
/** The family member ringing into or on this call. A call has at most one at a time. */
export function activePorchGuest(call?: Call): PorchGuest | undefined { return call?.porchGuests?.find(g => g.state === "ringing" || g.state === "joined"); }
/** The members still on an answered call: its two ends and a family guest who answered, less anyone who left. */
export function presentMembers(call: Call): string[] {
  const guest = call.porchGuests?.find(g => g.state === "joined");
  return [call.from, call.to, ...(guest ? [guest.memberID] : [])].filter(id => call.left?.[id] === undefined);
}
/** Whether a call can go on with only `remaining` on it: two people, counting a phone guest only while whoever added it
 * stays. So the bedside is never left alone with a phone, and nobody is left talking to no one. */
export function carriesOn(call: Call, remaining: string[]): boolean {
  const phone = activePhoneGuest(call);
  return remaining.length + (phone && remaining.includes(phone.addedBy) ? 1 : 0) >= 2;
}
/** Takes `id` off a call that goes on without them. A phone guest they added hangs up with them. */
export function leaveCall(call: Call, id: string, now: number) {
  (call.left ??= {})[id] = now;
  const phone = activePhoneGuest(call);
  if (phone?.addedBy === id) phone.endedAt = now;
  const guest = call.porchGuests?.find(g => g.memberID === id && g.state === "joined");
  if (guest) { guest.state = "left"; guest.endedAt = now; }
}
/** The phone guest whose telephone leg may still be connected. A call has at most one. */
export function activePhoneGuest(call?: Call): PhoneGuest | undefined { return call?.guests?.find(g => !g.endedAt); }
export function phoneGuestIdentity(guest: PhoneGuest): string { return `phone-guest-${guest.id}`; }
export function phoneDropIn(house: Household, number?: string): PhoneDropIn | undefined {
  return number ? house.phoneDropIns?.find(p => p.number === number) : undefined;
}
// Rechecked on answer and after every access change, for app and telephone drop-ins alike.
export function dropInAllowed(house: Household, call: Call): boolean {
  if (!house.dropInEnabled) return false;
  if (call.phone) return call.mode === "voice" && !!phoneDropIn(house, call.phone.callerNumber);
  const caller = house.members.find(m => m.id === call.from);
  return !!caller && !caller.revoked && caller.permissions[call.mode === "voice" ? "audio" : "video"];
}
/** What a new Porch call becomes. A family member whose calls a caregiver set to drop in drops in with an ordinary
 * call too, whenever they could have chosen that drop-in themselves and the bedside is ready for it. Otherwise it
 * rings as usual, by push if the bedside Porch is closed. */
export function callKind(house: Household, caller: Member, target: Member, mode: Mode, requested: Call["kind"], bedsideReady: boolean): Call["kind"] {
  if (requested === "dropIn" || !caller.autoDropIn || target.role !== "bedside" || !bedsideReady) return requested;
  return house.dropInEnabled && caller.permissions[mode === "voice" ? "audio" : "video"] ? "dropIn" : "call";
}
