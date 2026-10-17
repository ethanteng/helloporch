import { randomUUID } from "node:crypto";
import { FamilyError, mutate, requireValue, type Household, type InboxEntry, type Member, type MessageKind, type MessageMode } from "./household.ts";
import type { MediaStore } from "./media.ts";
import type { FamilyStore } from "./store.ts";

export type MessageState = "uploading" | "queued" | "played" | "expired" | "removed" | "unsent" | "failed";
/** The sender's record. Played messages are soft-deleted: the record stays and only the media is purged later. */
export type MessageRecord = { id: string; kind: MessageKind; mode: MessageMode; contentType: string; pathname: string; durationSeconds: number; sizeBytes: number; createdAt: number; state: MessageState; sentAt?: number; deliveredAt?: number; playedAt?: number; endedAt?: number };
type Ended = { id: string; from: string; pathname: string };

export const messageLimits = { durationSeconds: 125, audioBytes: 10 * 1024 * 1024, videoBytes: 100 * 1024 * 1024, pendingPerSender: 10, inbox: 30, unplayedSeconds: 7 * 86400, keepMediaSeconds: 90 * 86400, uploadSeconds: 1800, downloadSeconds: 3600, listed: 50, voicemailsPerCaller: 3, heldVoicemails: 10 };
const contentTypes: Record<MessageMode, string[]> = { audio: ["audio/mp4"], video: ["video/mp4", "video/quicktime"] };
const extensions: Record<string, string> = { "audio/mp4": "m4a", "video/mp4": "mp4", "video/quicktime": "mov", "audio/mpeg": "mp3" };
/** The sender of voicemails left by regular phone callers; their records share one document. */
export const phoneSender = "phone";
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const sentKey = (householdID: string, memberID: string) => `messages:${householdID}:${memberID}`;
const purgeKey = (householdID: string) => `message-purge:${householdID}`;
const live = (entry: InboxEntry, now: number) => entry.sentAt + messageLimits.unplayedSeconds > now;
// An upload that never completed: its URL has long expired.
const stale = (record: MessageRecord, now: number) => record.state === "uploading" && record.createdAt + 2 * messageLimits.uploadSeconds <= now;
// Unsent, removed and expired media is deleted at once; played media is kept for 90 days.
const replayable = (record: MessageRecord, now: number) => record.state === "queued" || (record.state === "played" && (record.playedAt ?? 0) + messageLimits.keepMediaSeconds > now);

export const messageActions = new Set(["createMessage", "completeMessage", "unsendMessage", "listMessages", "sentMessageMedia", "messageMedia", "messageDelivered", "messagePlayed", "caregiverMessageMedia", "removeMessage", "releaseMessage", "releaseKnownCaller"]);
export type MessageContext = { store: FamilyStore; media: () => MediaStore; now: number; house: Household; me: Member; input: Record<string, unknown> };

export function publicRecord(record: MessageRecord, now: number) {
  const { pathname: _pathname, ...rest } = record;
  return stale(record, now) ? { ...rest, state: "failed" as const, replayable: false } : { ...rest, replayable: replayable(record, now) };
}
export function publicInbox(house: Household, now: number) {
  return (house.inbox ?? []).filter(entry => live(entry, now)).map(({ pathname: _pathname, deliveredAt, held, ...entry }) => ({
    ...entry, fromName: house.members.find(m => m.id === entry.from && !m.revoked)?.name ?? entry.fromName, delivered: deliveredAt !== undefined, held: held === true,
  }));
}
/** Phone voicemails waiting for a caregiver; approved caregivers see the count on their phones. */
export const heldCount = (house: Household, now: number) => (house.inbox ?? []).filter(entry => entry.held && live(entry, now)).length;

async function update<D, T>(store: FamilyStore, key: string, empty: () => D, change: (doc: D) => T): Promise<T> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(key);
    const doc: D = raw ? JSON.parse(raw) : empty();
    const result = change(doc);
    const next = JSON.stringify(doc);
    if (next === raw || (raw === null ? await store.create(key, next) : await store.compareAndSet(key, raw, next))) return result;
  }
  throw new FamilyError("Porch is busy. Please try again.", 409);
}
const updateSent = <T>(store: FamilyStore, householdID: string, memberID: string, change: (records: MessageRecord[]) => T) =>
  update(store, sentKey(householdID, memberID), () => ({ records: [] as MessageRecord[] }), doc => change(doc.records));
async function sentRecords(store: FamilyStore, householdID: string, memberID: string): Promise<MessageRecord[]> {
  const raw = await store.get(sentKey(householdID, memberID));
  return raw ? JSON.parse(raw).records : [];
}
// Records are kept for good; once a sender has many, older finished ones move to archive pages.
async function archive(store: FamilyStore, householdID: string, memberID: string) {
  const key = sentKey(householdID, memberID);
  const records = await sentRecords(store, householdID, memberID);
  if (records.length <= 200) return;
  const old = records.slice(0, 100).filter(r => !["uploading", "queued"].includes(r.state));
  if (!old.length) return;
  await store.create(`${key}:archive:${old[0].id}`, JSON.stringify({ records: old }));
  const moved = new Set(old.map(r => r.id));
  await update(store, key, () => ({ records: [] as MessageRecord[] }), doc => { doc.records = doc.records.filter(r => !moved.has(r.id)); });
}

async function schedulePurge(store: FamilyStore, householdID: string, pathnames: string[], at: number) {
  await update(store, purgeKey(householdID), () => ({ items: [] as { pathname: string; at: number }[] }), doc => {
    for (const pathname of pathnames) if (!doc.items.some(item => item.pathname === pathname)) doc.items.push({ pathname, at });
  });
}

// The sender's record changes first, then the shared queue; a retry finishes whatever is left.
async function endMessages(store: FamilyStore, media: () => MediaStore, householdID: string, items: Ended[], state: "expired" | "removed" | "unsent", now: number) {
  for (const from of new Set(items.map(item => item.from))) {
    const ids = new Set(items.filter(item => item.from === from).map(item => item.id));
    await updateSent(store, householdID, from, records => {
      for (const record of records) if (ids.has(record.id) && (record.state === "uploading" || record.state === "queued")) { record.state = state; record.endedAt = now; }
    });
  }
  let deleted = false;
  try { await media().remove(items.map(item => item.pathname)); deleted = true; } catch { /* the purge pass retries */ }
  if (!deleted) await schedulePurge(store, householdID, items.map(item => item.pathname), now);
  const ids = new Set(items.map(item => item.id));
  await mutate(store, householdID, house => {
    house.inbox = (house.inbox ?? []).filter(entry => !ids.has(entry.id));
    if (!deleted) house.purgeAt = Math.min(house.purgeAt ?? now, now);
  });
}

async function purge(store: FamilyStore, media: () => MediaStore, householdID: string, now: number) {
  const raw = await store.get(purgeKey(householdID));
  const due: { pathname: string; at: number }[] = raw ? JSON.parse(raw).items.filter((item: { at: number }) => item.at <= now) : [];
  if (due.length) await media().remove(due.map(item => item.pathname));
  const done = new Set(due.map(item => item.pathname));
  const remaining = await update(store, purgeKey(householdID), () => ({ items: [] as { pathname: string; at: number }[] }), doc => {
    doc.items = doc.items.filter(item => !done.has(item.pathname)); return doc.items;
  });
  const next = remaining.length ? Math.min(...remaining.map(item => item.at)) : undefined;
  await mutate(store, householdID, house => {
    // Keep a later time another request set while this pass ran.
    const pending = [next, house.purgeAt !== undefined && house.purgeAt > now ? house.purgeAt : undefined].filter((at): at is number => at !== undefined);
    if (pending.length) house.purgeAt = Math.min(...pending); else delete house.purgeAt;
  });
}

/** Expires week-old unplayed messages and purges media past its retention. Runs on bedside polls. */
export async function maintainMessages(store: FamilyStore, media: () => MediaStore, house: Household, now: number) {
  const expired = (house.inbox ?? []).filter(entry => !live(entry, now));
  if (expired.length) await endMessages(store, media, house.id, expired, "expired", now);
  if (house.purgeAt !== undefined && house.purgeAt <= now) await purge(store, media, house.id, now);
}

/** A caregiver removing someone's access also removes their unplayed messages. */
export async function removeMessagesFrom(store: FamilyStore, media: () => MediaStore, house: Household, memberID: string, now: number) {
  const theirs = (house.inbox ?? []).filter(entry => entry.from === memberID);
  if (theirs.length) await endMessages(store, media, house.id, theirs, "removed", now);
}

/** Whether a regular phone caller can leave a voicemail now; spam callers can't fill the queue. */
export function voicemailOpen(house: Household, callerNumber: string | undefined, now: number) {
  const inbox = (house.inbox ?? []).filter(entry => live(entry, now));
  const held = inbox.filter(entry => entry.held);
  return house.messagesEnabled !== false && house.members.some(m => m.role === "bedside" && !m.revoked) && inbox.length < messageLimits.inbox &&
    held.length < messageLimits.heldVoicemails &&
    inbox.filter(entry => entry.from === phoneSender && entry.callerNumber === callerNumber).length < messageLimits.voicemailsPerCaller;
}

/** Stores a phone caller's recording and holds it for review. Safe to repeat for the same recording. */
export async function receivePhoneVoicemail(store: FamilyStore, media: MediaStore, householdID: string, recording: { id: string; callerNumber?: string; audio: Uint8Array; durationSeconds: number }, now: number) {
  const { id, callerNumber, audio } = recording;
  const existing = (await sentRecords(store, householdID, phoneSender)).find(r => r.id === id);
  if (existing && existing.state !== "uploading") return existing.state === "queued";
  requireValue(audio.byteLength > 0 && audio.byteLength <= messageLimits.audioBytes, "This recording is too large.", 413);
  const durationSeconds = Math.max(1, Math.min(messageLimits.durationSeconds, Math.round(recording.durationSeconds)));
  const record: MessageRecord = { id, kind: "voicemail", mode: "audio", contentType: "audio/mpeg", pathname: `messages/${householdID}/${id}.mp3`, durationSeconds, sizeBytes: audio.byteLength, createdAt: now, state: "uploading" };
  await updateSent(store, householdID, phoneSender, records => { if (!records.some(r => r.id === id)) records.push(record); });
  await media.put(record.pathname, audio, record.contentType);
  const { result: queued } = await mutate(store, householdID, house => {
    house.inbox ??= [];
    if (house.inbox.some(entry => entry.id === id)) return true;
    if (!voicemailOpen(house, callerNumber, now)) return false;
    house.inbox.push({ id, from: phoneSender, fromName: callerNumber ?? "Phone caller", kind: "voicemail", mode: "audio", contentType: record.contentType, pathname: record.pathname, durationSeconds, sentAt: now, held: true, ...(callerNumber ? { callerNumber } : {}) });
    return true;
  });
  await updateSent(store, householdID, phoneSender, records => {
    const r = records.find(r => r.id === id);
    if (r?.state === "uploading") { r.state = queued ? "queued" : "failed"; if (queued) r.sentAt = now; else r.endedAt = now; }
  });
  if (!queued) await media.remove([record.pathname]);
  try { await archive(store, householdID, phoneSender); } catch { /* housekeeping only */ }
  return queued;
}

function messageID(input: Record<string, unknown>) {
  requireValue(typeof input.messageID === "string" && uuid.test(input.messageID), "This message was not found.", 404);
  return input.messageID;
}

export async function handleMessageAction(action: string, { store, media, now, house, me, input }: MessageContext): Promise<object> {
  if (action === "createMessage") {
    requireValue(me.role === "family", "Only family devices send messages.", 403);
    requireValue(house.messagesEnabled !== false, "Messages are turned off for this Porch.", 403);
    requireValue(house.members.some(m => m.role === "bedside" && !m.revoked), "This Porch isn't set up yet.", 409);
    const mode = input.mode, kind = input.kind ?? "message";
    requireValue(mode === "audio" || mode === "video", "Choose audio or video.");
    requireValue(kind === "message" || kind === "voicemail", "Choose a message type.");
    requireValue(typeof input.contentType === "string" && contentTypes[mode].includes(input.contentType), "This recording format isn't supported.");
    const contentType = input.contentType, size = input.sizeBytes, duration = input.durationSeconds;
    requireValue(typeof duration === "number" && Number.isFinite(duration) && duration > 0 && duration <= messageLimits.durationSeconds, "Messages can be up to two minutes long.");
    requireValue(typeof size === "number" && Number.isInteger(size) && size > 0, "Record the message again.");
    requireValue(size <= (mode === "audio" ? messageLimits.audioBytes : messageLimits.videoBytes), mode === "audio" ? "Audio messages can be up to 10 MB." : "Video messages can be up to 100 MB. Record a shorter message.", 413);
    const blob = media();
    const id = randomUUID();
    const record: MessageRecord = { id, kind, mode, contentType, pathname: `messages/${house.id}/${id}.${extensions[contentType]}`, durationSeconds: Math.round(duration), sizeBytes: size, createdAt: now, state: "uploading" };
    const abandoned = await updateSent(store, house.id, me.id, records => {
      const abandoned = records.filter(r => stale(r, now));
      for (const r of abandoned) { r.state = "failed"; r.endedAt = now; }
      requireValue(records.filter(r => r.state === "uploading" || r.state === "queued").length < messageLimits.pendingPerSender, "You have 10 messages waiting. Send more once some are played.", 409);
      records.push(record);
      return abandoned.map(r => r.pathname);
    });
    try { await blob.remove(abandoned); await archive(store, house.id, me.id); } catch { /* housekeeping only */ }
    const upload = await blob.uploadTarget(record.pathname, contentType, size, now + messageLimits.uploadSeconds);
    return { message: publicRecord(record, now), upload };
  }
  if (action === "completeMessage" || action === "unsendMessage") {
    requireValue(me.role === "family", "Only the sender can change this message.", 403);
    const id = messageID(input);
    const record = (await sentRecords(store, house.id, me.id)).find(r => r.id === id);
    requireValue(record, "This message was not found.", 404);
    if (action === "unsendMessage") {
      if (record.state !== "unsent") {
        requireValue(record.state === "uploading" || record.state === "queued", "This message was already played or removed.", 409);
        await endMessages(store, media, house.id, [{ id, from: me.id, pathname: record.pathname }], "unsent", now);
      }
      return { message: publicRecord({ ...record, state: "unsent", endedAt: record.endedAt ?? now }, now) };
    }
    if (record.state === "queued") return { message: publicRecord(record, now) };
    requireValue(record.state === "uploading" && !stale(record, now), "This upload expired. Record the message again.", 409);
    requireValue(house.messagesEnabled !== false, "Messages are turned off for this Porch.", 403);
    const uploaded = await media().stat(record.pathname);
    requireValue(uploaded, "The upload didn't finish. Try sending again.", 409);
    requireValue(uploaded.contentType === record.contentType && uploaded.size <= (record.mode === "audio" ? messageLimits.audioBytes : messageLimits.videoBytes), "This upload doesn't match the recording. Record the message again.");
    // Queue first so the bedside sees it on its next poll; a retry then finishes the sender's record.
    await mutate(store, house.id, current => {
      current.inbox ??= [];
      if (current.inbox.some(entry => entry.id === id)) return;
      requireValue(current.inbox.length < messageLimits.inbox, "This Porch has 30 messages waiting. Try again after some are played.", 409);
      current.inbox.push({ id, from: me.id, fromName: me.name, kind: record.kind, mode: record.mode, contentType: record.contentType, pathname: record.pathname, durationSeconds: record.durationSeconds, sentAt: now });
    });
    const sent = await updateSent(store, house.id, me.id, records => {
      const r = records.find(r => r.id === id)!;
      if (r.state === "uploading") { r.state = "queued"; r.sentAt = now; r.sizeBytes = uploaded.size; }
      return r;
    });
    return { message: publicRecord(sent, now) };
  }
  if (action === "listMessages") {
    if (me.role === "bedside") return { messages: publicInbox(house, now) };
    const records = await sentRecords(store, house.id, me.id);
    return { messages: records.slice(-messageLimits.listed).reverse().map(r => publicRecord(r, now)) };
  }
  if (action === "sentMessageMedia") {
    // Senders replay their own messages while the media is kept.
    requireValue(me.role === "family", "Only the sender can replay this message.", 403);
    const id = messageID(input);
    const record = (await sentRecords(store, house.id, me.id)).find(r => r.id === id);
    requireValue(record && replayable(record, now), "This recording is no longer available.", 404);
    const expiresAt = now + messageLimits.downloadSeconds;
    return { media: { url: await media().downloadURL(record.pathname, expiresAt), expiresAt, contentType: record.contentType } };
  }
  // Every remaining action concerns a queued message.
  const id = messageID(input);
  const entry = (house.inbox ?? []).find(e => e.id === id);
  if (action === "messageMedia" || action === "caregiverMessageMedia") {
    // Caregiver previews are PIN-checked before this point; the bedside plays its own queue.
    if (action === "messageMedia") requireValue(me.role === "bedside", "Only the bedside device plays messages.", 403);
    requireValue(entry && live(entry, now), "This message is no longer available.", 404);
    requireValue(action === "caregiverMessageMedia" || !entry.held, "A caregiver needs to review this voicemail first.", 403);
    const expiresAt = now + messageLimits.downloadSeconds;
    return { media: { url: await media().downloadURL(entry.pathname, expiresAt), expiresAt, contentType: entry.contentType } };
  }
  if (action === "removeMessage") {
    requireValue(entry, "This message was already played or removed.", 404);
    await endMessages(store, media, house.id, [entry], "removed", now);
    return { removed: true };
  }
  if (action === "releaseMessage" || action === "releaseKnownCaller") {
    // A caregiver approves with the PIN; the bedside releases callers saved on its keypad.
    if (action === "releaseKnownCaller") requireValue(me.role === "bedside", "Only the bedside device can do this.", 403);
    requireValue(entry, "This message was already played or removed.", 404);
    if (action === "releaseKnownCaller") requireValue(entry.from === phoneSender && entry.callerNumber, "This caller isn't saved on the keypad.", 403);
    await mutate(store, house.id, current => { const e = current.inbox?.find(e => e.id === id); if (e) delete e.held; });
    return { released: true };
  }
  requireValue(me.role === "bedside", "Only the bedside device plays messages.", 403);
  // Already played or removed: nothing left to record.
  if (!entry) return { ok: true };
  if (action === "messageDelivered") {
    if (entry.deliveredAt === undefined) {
      await updateSent(store, house.id, entry.from, records => { const r = records.find(r => r.id === id); if (r) r.deliveredAt ??= now; });
      await mutate(store, house.id, current => { const e = current.inbox?.find(e => e.id === id); if (e) e.deliveredAt ??= now; });
    }
    return { ok: true };
  }
  if (action === "messagePlayed") {
    const purgeAt = now + messageLimits.keepMediaSeconds;
    await updateSent(store, house.id, entry.from, records => {
      const r = records.find(r => r.id === id);
      if (r?.state === "queued") { r.state = "played"; r.playedAt = now; r.deliveredAt ??= now; }
    });
    await schedulePurge(store, house.id, [entry.pathname], purgeAt);
    await mutate(store, house.id, current => {
      current.inbox = (current.inbox ?? []).filter(e => e.id !== id);
      current.purgeAt = Math.min(current.purgeAt ?? purgeAt, purgeAt);
    });
    return { ok: true };
  }
  throw new FamilyError("Unknown family action.");
}
