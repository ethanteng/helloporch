import { updateJSON, type FamilyStore } from "./store.ts";

/** A text or phone voicemail the household's Porch number received, for the admin page's activity counts. Only who sent
 * it and when: never the words or the recording, which go away on their own schedule. `from` is the sender's number or
 * short code, and is missing for a voicemail from a caller who hid their number. Family members' recorded messages
 * aren't here: their senders' message records already say who sent each one, and when. */
export type ReceivedEntry = { id: string; kind: "text" | "voicemail"; from?: string; at: number };

/** Kept like call history: the newest 200, for up to 90 days. The whole log expires 90 days after its newest entry, so a
 * household that stops receiving texts and voicemail keeps nothing longer. */
export const receivedLogLimits = { entries: 200, keepSeconds: 90 * 86400 };
export const receivedLogKey = (householdID: string) => `received-log:${householdID}`;
type ReceivedLog = { entries: ReceivedEntry[] };

/** Adds `entry` once, however often Twilio repeats its webhook. A failed save is dropped: counting never fails a text or
 * voicemail. */
export async function recordReceived(store: FamilyStore, householdID: string, entry: ReceivedEntry, now: number) {
  try {
    await updateJSON<ReceivedLog>(store, receivedLogKey(householdID), { entries: [] }, log => {
      if (log.entries.some(e => e.id === entry.id)) return undefined;
      return { entries: [...log.entries.filter(e => e.at + receivedLogLimits.keepSeconds > now), entry].slice(-receivedLogLimits.entries) };
    }, receivedLogLimits.keepSeconds);
  } catch { /* counts only */ }
}

/** The log as saved, oldest first, without changing it. `full`: it holds as many entries as it keeps, so older ones may
 * have dropped off. */
export async function readReceivedLog(store: FamilyStore, householdID: string, now: number): Promise<{ entries: ReceivedEntry[]; full: boolean }> {
  const raw = await store.get(receivedLogKey(householdID));
  const saved: ReceivedEntry[] = raw ? (JSON.parse(raw) as ReceivedLog).entries : [];
  return { entries: saved.filter(e => e.at + receivedLogLimits.keepSeconds > now), full: saved.length >= receivedLogLimits.entries };
}
