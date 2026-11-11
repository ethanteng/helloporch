import { savedCalls } from "../family/call-log.ts";
import type { Household } from "../family/household.ts";
import { phoneSender, sentRecords, type MessageState } from "../family/messages.ts";
import { readReceivedLog } from "../family/received-log.ts";
import type { FamilyStore } from "../family/store.ts";
import { readHouseholds } from "./porches.ts";
import { assertAdmin, type AdminSession } from "./session.ts";

// How much each Porch is used over a stretch of time, for the admin page. Counts only: never names, phone numbers,
// keypad contents or what was said, and nothing that says who called whom.

/** `count` things, from or to `people` different senders or recipients. Callers who hid their number count once each in
 * `count` but not in `people`. `partial`: the history this comes from has reached its size limit, so earlier ones in the
 * range may have dropped off and `count` is a minimum. */
export type Tally = { count: number; people: number; partial?: true };
/** `contacts`: family members on the Porch app, and the phone numbers the household knows: saved on the bedside keypad,
 * approved to drop in, or allowed by a caregiver. `activeContacts`: those who called, left a recorded message or texted
 * the bedside in the range. `voicemails`: how many audio messages were left by phone callers. */
export type UsageRow = { id: string; contacts: { porchApp: number; phoneNumbers: number }; activeContacts: number;
  callsReceived: Tally & { answered: number }; audioMessages: Tally & { voicemails: number }; videoMessages: Tally; texts: Tally; callsMade: Tally };

/** From the start of `from` up to, not including, `to`, in seconds. */
export type UsageRange = { from: number; to: number };
export const usagePresets = [
  { key: "1w", label: "Last week", days: 7 },
  { key: "2w", label: "Last 2 weeks", days: 14 },
  { key: "1m", label: "Last month", days: 30 },
  { key: "3m", label: "Last 3 months", days: 90 },
] as const;
export const defaultPreset = "1m";
/** Call history, and the log of texts and phone voicemail, go back this far. */
export const usageHistorySeconds = 90 * 86400;

// Dates on the admin page are Pacific time, where it's used.
const zone = "America/Los_Angeles";
const pacific = new Intl.DateTimeFormat("en-US", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
function pacificParts(seconds: number) {
  const part = Object.fromEntries(pacific.formatToParts(new Date(seconds * 1000)).map(p => [p.type, p.value]));
  return { date: `${part.year}-${part.month}-${part.day}`, time: `${part.hour}:${part.minute}` };
}
/** The Pacific calendar day `seconds` falls on, as `YYYY-MM-DD`, the way a date field writes it. */
export const pacificDay = (seconds: number) => pacificParts(seconds).date;
function validDate(date: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  return !!match && new Date(Date.UTC(+match[1], +match[2] - 1, +match[3])).toISOString().slice(0, 10) === date;
}
/** When `date` (`YYYY-MM-DD`) starts in Pacific time: 7 or 8 hours after it starts in UTC, by daylight saving time. */
export function pacificMidnight(date: string): number | undefined {
  if (!validDate(date)) return undefined;
  const utc = Date.parse(`${date}T00:00:00Z`) / 1000;
  return [7, 8].map(hours => utc + hours * 3600).find(at => { const p = pacificParts(at); return p.date === date && p.time === "00:00"; });
}
const nextDay = (date: string) => new Date(Date.parse(`${date}T00:00:00Z`) + 86400_000).toISOString().slice(0, 10);

type Param = string | string[] | undefined;
const one = (value: Param) => typeof value === "string" && value.length <= 20 ? value : undefined;
/** The range the admin page's search parameters ask for: a preset (`range`), or Pacific dates `from` and `to`, both
 * included. A custom range ends now at the latest. Anything unusable shows the default preset, with `error` for dates
 * that were given but can't be used. */
export function usageRange(params: { range?: Param; from?: Param; to?: Param }, now: number):
  UsageRange & ({ preset: string; error?: string } | { custom: { from: string; to: string } }) {
  const from = one(params.from), to = one(params.to);
  let error: string | undefined;
  if (from !== undefined || to !== undefined) {
    const start = from ? pacificMidnight(from) : undefined, end = to && validDate(to) ? pacificMidnight(nextDay(to)) : undefined;
    if (start !== undefined && end !== undefined && start < end && start < now) return { from: start, to: Math.min(end, now), custom: { from: from!, to: to! } };
    error = !from || !to ? "Choose both a start and an end date." : start === undefined || end === undefined ? "Those dates aren't valid."
      : start >= end ? "The start date needs to be on or before the end date." : "The start date can't be in the future.";
  }
  const preset = usagePresets.find(p => p.key === one(params.range)) ?? usagePresets.find(p => p.key === defaultPreset)!;
  return { from: now - preset.days * 86400, to: now, preset: preset.key, ...(error ? { error } : {}) };
}

// A family member's recorded message, or a phone caller's voicemail, that reached the bedside. One its sender unsent
// before it was played doesn't count, nor does one that never finished uploading.
const reachedBedside = new Set<MessageState>(["queued", "played", "expired", "removed"]);
const memberKey = (id: string) => `member:${id}`, numberKey = (number: string) => `number:${number}`;
const tallied = (count: number, people: Set<string>, partial: boolean): Tally => ({ count, people: people.size, ...(partial ? { partial: true as const } : {}) });

export async function porchUsage(session: AdminSession, store: FamilyStore, range: UsageRange, now: number): Promise<UsageRow[]> {
  assertAdmin(session);
  return Promise.all((await readHouseholds(store)).map(house => usageOf(store, house, range, now)));
}

async function usageOf(store: FamilyStore, house: Household, { from, to }: UsageRange, now: number): Promise<UsageRow> {
  const within = (at: number) => at >= from && at < to;
  const family = house.members.filter(m => m.role === "family");
  // Removed family members' messages are deleted with them, but any left still reached the bedside.
  const [calls, received, phoneRecords, memberRecords] = await Promise.all([savedCalls(store, house, now), readReceivedLog(store, house.id, now),
    sentRecords(store, house.id, phoneSender), Promise.all(family.map(async m => ({ id: m.id, records: await sentRecords(store, house.id, m.id) })))]);
  // A full history whose oldest entry is inside the range may have dropped earlier ones in it.
  const callsPartial = calls.full && Math.min(...calls.entries.map(e => e.startedAt)) > from;
  const receivedPartial = received.full && Math.min(...received.entries.map(e => e.at)) > from;

  const callsIn = new Set<string>(), callsOut = new Set<string>(), audio = new Set<string>(), video = new Set<string>(), texts = new Set<string>();
  const add = (people: Set<string>, key: string | undefined) => { if (key) people.add(key); };
  let callsInCount = 0, answered = 0, callsOutCount = 0, audioCount = 0, voicemails = 0, videoCount = 0, textCount = 0;
  for (const call of calls.entries) {
    if (!within(call.startedAt)) continue;
    const key = call.memberID ? memberKey(call.memberID) : call.number ? numberKey(call.number) : undefined;
    if (call.direction === "outgoing") { callsOutCount++; add(callsOut, key); continue; }
    callsInCount++; add(callsIn, key);
    if (call.outcome === "answered" || call.outcome === "ongoing") answered++;
  }
  for (const { id, records } of memberRecords) for (const record of records) {
    // `to` marks the bedside's own messages for family, which family members' records don't have.
    if (record.to !== undefined || record.sentAt === undefined || !within(record.sentAt) || !reachedBedside.has(record.state)) continue;
    if (record.mode === "video") { videoCount++; video.add(memberKey(id)); } else { audioCount++; audio.add(memberKey(id)); }
  }
  // Phone voicemail records don't keep the caller's number. The received log does, for those left since it started.
  const callers = new Map(received.entries.filter(e => e.kind === "voicemail").map(e => [e.id, e.from]));
  for (const record of phoneRecords) {
    if (record.sentAt === undefined || !within(record.sentAt) || !reachedBedside.has(record.state)) continue;
    audioCount++; voicemails++;
    const caller = callers.get(record.id);
    if (caller) audio.add(numberKey(caller));
  }
  for (const entry of received.entries) {
    if (entry.kind !== "text" || !within(entry.at)) continue;
    textCount++; if (entry.from) texts.add(numberKey(entry.from));
  }

  const porchApp = family.filter(m => !m.revoked);
  const numbers = new Set([...house.keypadNumbers ?? [], ...(house.phoneDropIns ?? []).map(p => p.number), ...(house.allowedCallers ?? []).map(c => c.number)]);
  const reachedOut = new Set([...callsIn, ...audio, ...video, ...texts]);
  const activeContacts = porchApp.filter(m => reachedOut.has(memberKey(m.id))).length + [...numbers].filter(n => reachedOut.has(numberKey(n))).length;
  return { id: house.id, contacts: { porchApp: porchApp.length, phoneNumbers: numbers.size }, activeContacts,
    callsReceived: { ...tallied(callsInCount, callsIn, callsPartial), answered },
    audioMessages: { ...tallied(audioCount, audio, false), voicemails }, videoMessages: tallied(videoCount, video, false),
    texts: tallied(textCount, texts, receivedPartial), callsMade: tallied(callsOutCount, callsOut, callsPartial) };
}
