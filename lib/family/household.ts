import type { CallServer } from "../calls/server.ts";
import type { FamilyStore } from "./store.ts";
import type { VoIPRegistration } from "./push.ts";

export type Role = "bedside" | "family";
export type Mode = "voice" | "video";
export type Permissions = { audio: boolean; video: boolean };
export type Member = { voip?: VoIPRegistration; invitationID?: string; caregiver?: boolean; id: string; name: string; role: Role; secretHash: string; permissions: Permissions; revoked: boolean; seenAt: number; available: boolean };
export type Invite = { id: string; secretHash: string; name: string; permissions: Permissions; caregiver?: boolean; expiresAt: number; claimedBy?: string };
export type Call = { id: string; from: string; to: string; mode: Mode; kind: "call" | "dropIn"; state: "pending" | "accepted" | "ended"; createdAt: number; receivedAt?: number; announcedAt?: number; acceptedAt?: number; expiresAt: number; reason?: string; phone?: InboundPhone };
export type MessageKind = "message" | "voicemail";
export type MessageMode = "audio" | "video";
/** A queued message. Kept in the household so the bedside's existing poll carries the queue. */
export type InboxEntry = { id: string; from: string; fromName: string; kind: MessageKind; mode: MessageMode; contentType: string; pathname: string; durationSeconds: number; sentAt: number; deliveredAt?: number };
/** A caregiver-approved telephone number that may drop in with audio when its caller ID is carrier-verified. */
export type PhoneDropIn = { number: string; name: string };
export type Household = { id: string; name: string; dropInEnabled: boolean; members: Member[]; invites: Invite[]; call?: Call; messagesEnabled?: boolean; inbox?: InboxEntry[]; purgeAt?: number; phoneDropIns?: PhoneDropIn[] };
export type Auth = { householdID: string; deviceID: string; hash: string };
export type InboundPhone = { room: string; roomSID: string; participantIdentity: string; participantSID: string; trunkID: string; calledNumber: string; callerNumber?: string; checkedAt?: number; cleanedUp?: boolean };
export class FamilyError extends Error { status: number; code?: string; constructor(message: string, status = 400, code?: string) { super(message); this.status = status; this.code = code; } }
export function requireValue(condition: unknown, message: string, status = 400): asserts condition { if (!condition) throw new FamilyError(message, status); }
export function config(): CallServer {
  const { LIVEKIT_URL: serverUrl, LIVEKIT_API_KEY: apiKey, LIVEKIT_API_SECRET: apiSecret } = process.env;
  requireValue(serverUrl?.startsWith("wss://") && apiKey && apiSecret, "Calling is not configured.", 503);
  return { serverUrl: serverUrl!, apiKey, apiSecret };
}
export function expire(house: Household, now: number) {
  const call = house.call;
  if (!call || call.state === "ended") return;
  if (call.expiresAt <= now || (call.state === "accepted" && (call.phone ? [call.to] : [call.from, call.to]).some(id => {
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

export function callRoom(call: Call): string { return call.phone?.room ?? `porch-paired-${call.id}`; }
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
