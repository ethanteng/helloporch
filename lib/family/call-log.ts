import { deliveryUnavailable, displayName, FamilyError, phoneDropIn, type Call, type Household } from "./household.ts";
import type { FamilyStore } from "./store.ts";

/** One call to or from the bedside, as caregivers see it in Call history. The name and number are kept as Porch
 * showed them at the time, so a removed family member's calls still read the same.
 * `direction` is the bedside's: `incoming` rang the bedside, `outgoing` was placed from it.
 * `via`: the Porch app, or a regular phone — someone calling the household's Porch number, or the bedside calling a
 * phone, including phone fallback. The bedside's calls to a phone record only that they were dialed (`dialed`),
 * because the server doesn't learn whether they were answered.
 * `endedAt`: when the bedside's part of the call ended, which is earlier than the call itself when it went on without
 * it. Calls from before this was recorded have none.
 * `reached`, on the bedside's unanswered Porch calls: whether the family phone showed the call. Its app reports that
 * once iOS has put the call on screen, so false means it never got there, not that it rang unheard. */
export type CallLogEntry = { id: string; direction: "incoming" | "outgoing"; via: "porch" | "phone"; name: string; memberID?: string; number?: string;
  mode: "voice" | "video"; dropIn?: boolean; startedAt: number; answeredAt?: number; endedAt?: number;
  outcome: "answered" | "missed" | "declined" | "unavailable" | "dialed" | "ringing" | "ongoing"; reached?: boolean };

/** The household's newest calls, for 90 days. */
export const callLogLimits = { entries: 100, keepSeconds: 90 * 86400 };
const logKey = (householdID: string) => `call-log:${householdID}`;
type CallLog = { entries: CallLogEntry[] };

/** How `call` reads in Call history, or nothing for a call the bedside wasn't on. */
export function callLogEntry(house: Household, call: Call): CallLogEntry | undefined {
  const bedside = house.members.find(m => m.role === "bedside" && [call.from, call.to].includes(m.id));
  if (!bedside) return undefined;
  const outgoing = call.from === bedside.id;
  const member = call.phone ? undefined : house.members.find(m => m.id === (outgoing ? call.to : call.from));
  const number = call.phone?.callerNumber;
  // The name the call started with. Calls from before it was kept are named as Porch names them now.
  const name = call.peerName ?? (member ? displayName(member) : phoneDropIn(house, number)?.name ?? number ?? (call.phone ? "Unknown caller" : "Family"));
  // The bedside's part of a call that went on without it, such as Ethan and David talking after Mom hung up.
  const left = call.left?.[bedside.id];
  const endedAt = left !== undefined && (call.endedAt === undefined || left < call.endedAt) ? left : call.endedAt;
  const outcome: CallLogEntry["outcome"] = call.acceptedAt !== undefined ? (call.state === "ended" || left !== undefined ? "answered" : "ongoing")
    : call.state !== "ended" ? "ringing"
    : call.reason === deliveryUnavailable ? "unavailable"
    : call.endedBy === call.to ? "declined" : "missed";
  return { id: call.id, direction: outgoing ? "outgoing" : "incoming", via: call.phone ? "phone" : "porch", name,
    ...(member ? { memberID: member.id } : {}), ...(number ? { number } : {}), mode: call.mode, ...(call.kind === "dropIn" ? { dropIn: true } : {}),
    startedAt: call.createdAt, ...(call.acceptedAt !== undefined ? { answeredAt: call.acceptedAt } : {}),
    ...(endedAt !== undefined && outcome !== "ringing" && outcome !== "ongoing" ? { endedAt } : {}), outcome,
    ...(outgoing && outcome === "missed" ? { reached: call.receivedAt !== undefined } : {}) };
}

/** Adds a finished call to the household's history. Each call is recorded once; the oldest drop off. The whole
 * history expires 90 days after the newest call is added, so a household that stops calling keeps nothing longer. */
export async function recordCall(store: FamilyStore, householdID: string, entry: CallLogEntry, now: number) {
  const key = logKey(householdID);
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(key);
    const log: CallLog = raw ? JSON.parse(raw) : { entries: [] };
    if (log.entries.some(e => e.id === entry.id)) return;
    const entries = [...log.entries.filter(e => e.startedAt + callLogLimits.keepSeconds > now), entry].slice(-callLogLimits.entries);
    const next = JSON.stringify({ entries });
    if (raw === null ? await store.create(key, next, callLogLimits.keepSeconds) : await store.compareAndSet(key, raw, next, callLogLimits.keepSeconds)) return;
  }
  throw new FamilyError("Porch is busy. Please try again.", 409);
}
/** Saves `entry` without holding up the call it rides on: once the device has its answer when `afterResponse`
 * (Next's `after`) is given, otherwise right away. A failed save is dropped; history never fails a call. */
export async function recordCallAfter(store: FamilyStore, householdID: string, entry: CallLogEntry, now: number,
  afterResponse?: (task: () => Promise<unknown>) => void) {
  const save = () => recordCall(store, householdID, entry, now).catch(() => undefined);
  if (afterResponse) afterResponse(save); else await save();
}

/** The household's calls, newest first. The current or most recent call is still in the household itself, and is
 * recorded once the next call replaces it. */
export async function callHistory(store: FamilyStore, house: Household, now: number): Promise<CallLogEntry[]> {
  const raw = await store.get(logKey(house.id));
  const entries: CallLogEntry[] = raw ? (JSON.parse(raw) as CallLog).entries : [];
  const current = house.call ? callLogEntry(house, house.call) : undefined;
  // Newest first, so calls that started in the same second keep the order they were made in.
  return [...(current ? [current] : []), ...entries.filter(e => e.id !== current?.id).reverse()]
    .filter(e => e.startedAt + callLogLimits.keepSeconds > now)
    .sort((a, b) => b.startedAt - a.startedAt).slice(0, callLogLimits.entries);
}
