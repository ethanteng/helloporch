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
/** `name` is the name the caregiver gave the invitation. `profile` is the member's own choice and `override` a caregiver's. */
export type Member = { voip?: VoIPRegistration; alerts?: VoIPRegistration; invitationID?: string; caregiver?: boolean; id: string; name: string; role: Role; secretHash: string; permissions: Permissions; revoked: boolean; seenAt: number; available: boolean; profile?: Profile; override?: Profile; pendingPhotos?: PendingPhoto[] };
export type Invite = { id: string; secretHash: string; name: string; permissions: Permissions; caregiver?: boolean; expiresAt: number; claimedBy?: string };
/** `guests`: regular phones a family caregiver added to an answered call with the bedside (see phone-guests.ts).
 * `bedsideLeftAt`: the bedside hung up while a phone guest was on, leaving the family member and the guest talking. */
export type Call = { id: string; from: string; to: string; mode: Mode; kind: "call" | "dropIn"; state: "pending" | "accepted" | "ended"; createdAt: number; receivedAt?: number; announcedAt?: number; acceptedAt?: number; expiresAt: number; reason?: string; phone?: InboundPhone;
  guests?: PhoneGuest[]; bedsideLeftAt?: number };
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
export function expire(house: Household, now: number) {
  const call = house.call;
  if (!call || call.state === "ended") return;
  // Once the bedside has left a call with a phone guest, only the family member still on it must stay reachable.
  const present = call.phone ? [call.to] : call.bedsideLeftAt
    ? [call.from, call.to].filter(id => house.members.find(m => m.id === id)?.role !== "bedside") : [call.from, call.to];
  if (call.expiresAt <= now || (call.state === "accepted" && present.some(id => {
    const member = house.members.find(m => m.id === id);
    return !member || member.revoked || member.seenAt < now - 35;
  }))) { call.state = "ended"; call.reason = "The call timed out or a device went offline."; }
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
