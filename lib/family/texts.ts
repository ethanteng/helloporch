import { createHash } from "node:crypto";
import { bedsideLanguage, FamilyError, mutate, requireValue, type BedsideLanguage, type Household, type Member, type TextEntry } from "./household.ts";
import { knownCaller } from "./screening.ts";
import { familyStore, type FamilyStore } from "./store.ts";
import { claudeTranslate, translationConfigured, type Translate, type Translation } from "./translate.ts";
import { household, settings, signed } from "./voicemail.ts";

// Text messages to the household's Porch number. Twilio's messaging webhook brings each one here. A text from a number
// the household knows (saved on the keypad, approved for phone drop-in, or allowed by a caregiver) shows on the bedside
// after its waiting messages and is read aloud, translated when it isn't written in the bedside's language. Texts from
// other numbers wait for a caregiver, like phone voicemail. Texts carry no carrier check, so a faked number gets through.
// Pictures aren't shown yet; the bedside says that a text came with some.
export const textLimits = { characters: 1600, waiting: 20, held: 10, perSender: 10, heldPerSender: 3, pictures: 10,
  unreadSeconds: 7 * 86400, keepSeconds: 8 * 86400, spokenCharacters: 600, translatedCharacters: 4000, retrySeconds: 600 };
export const textActions = new Set(["textMessage", "textRead", "releaseText", "removeText", "caregiverTexts"]);
export type TextDependencies = { store?: FamilyStore; now?: () => number };
export type TextContext = { store: FamilyStore; now: number; house: Household; me: Member; input: Record<string, unknown>; translate?: Translate };
/** The words of one text, kept apart from the household until the text is read or removed. `translations`: what the
 * bedside showed and read, per bedside language, so a text is translated once. A removed text keeps only its ID for a
 * day, so Twilio repeating the webhook can't bring it back. */
type TextRecord = { id: string; from: string; body: string; pictures: number; receivedAt: number; translations?: Partial<Record<BedsideLanguage, Translation>> };
type Removed = { id: string; removed: true };

const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const messageSIDPattern = /^(SM|MM)[0-9a-f]{32}$/;
// A phone number, or a short code such as a pharmacy's reminders.
const senderPattern = /^(\+[1-9][0-9]{6,14}|[0-9]{3,8})$/;
// Twilio answers these itself. YES and INFO are left out: someone may well text Mom just "Yes".
const keywords = new Set(["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT", "REVOKE", "OPTOUT", "START", "UNSTOP", "HELP"]);
const textKey = (householdID: string, id: string) => `text:${householdID}:${id}`;
const live = (entry: TextEntry, now: number) => entry.sentAt + textLimits.unreadSeconds > now;
// A held text goes through once a caregiver saves or allows its number, even before the bedside's poll releases it.
const held = (house: Household, entry: TextEntry) => entry.held === true && !knownCaller(house, entry.from);
const reply = (status = 200) => new Response(`<?xml version="1.0" encoding="UTF-8"?><Response></Response>`, { status, headers: { "Content-Type": "text/xml", "Cache-Control": "no-store" } });

// The same Twilio message always becomes the same text, so a repeated webhook is harmless.
export function textMessageID(messageSID: string) {
  const h = createHash("sha256").update(`porch-text.${messageSID}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-${"89ab"[parseInt(h[16], 16) & 3]}${h.slice(17, 20)}-${h.slice(20, 32)}`;
}
/** Texts on their way to the bedside, and held ones, without their words. */
export function publicTexts(house: Household, now: number) {
  return (house.texts ?? []).filter(entry => live(entry, now)).map(entry => {
    const { deliveredAt, held: _held, ...rest } = entry;
    return { ...rest, held: held(house, entry), delivered: deliveredAt !== undefined };
  });
}
/** Texts waiting for a caregiver; approved caregivers see the count on their phones. */
export const heldTextCount = (house: Household, now: number) => (house.texts ?? []).filter(entry => held(house, entry) && live(entry, now)).length;

async function saved(store: FamilyStore, householdID: string, id: string): Promise<TextRecord | undefined> {
  const raw = await store.get(textKey(householdID, id));
  const record: TextRecord | Removed | undefined = raw ? JSON.parse(raw) : undefined;
  return record && !("removed" in record) ? record : undefined;
}
/** Changes a saved text's record. It keeps its original expiry, and a removed one stays removed. */
async function updateRecord(store: FamilyStore, householdID: string, id: string, now: number, change: (record: TextRecord) => void) {
  const key = textKey(householdID, id);
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(key);
    const record: TextRecord | Removed | undefined = raw ? JSON.parse(raw) : undefined;
    if (!raw || !record || "removed" in record) return;
    change(record);
    if (await store.compareAndSet(key, raw, JSON.stringify(record), Math.max(60, record.receivedAt + textLimits.keepSeconds - now))) return;
  }
  throw new FamilyError("Porch is busy. Please try again.", 409);
}
/** The text leaves the bedside's queue and its words are deleted. */
async function endText(store: FamilyStore, householdID: string, id: string) {
  await mutate(store, householdID, house => { house.texts = (house.texts ?? []).filter(entry => entry.id !== id); });
  const key = textKey(householdID, id), removed = JSON.stringify({ id, removed: true });
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(key);
    if (raw === null || raw === removed) return;
    if (await store.compareAndSet(key, raw, removed, 86400)) return;
  }
}

/** Whether a text from this number can join the queue now. Unknown numbers can't fill it. */
function textsOpen(house: Household, from: string, holding: boolean, now: number) {
  const waiting = (house.texts ?? []).filter(entry => live(entry, now));
  const theirs = waiting.filter(entry => entry.from === from);
  return house.messagesEnabled !== false && house.members.some(m => m.role === "bedside" && !m.revoked) && waiting.length < textLimits.waiting &&
    (holding ? waiting.filter(entry => held(house, entry)).length < textLimits.held && theirs.length < textLimits.heldPerSender : theirs.length < textLimits.perSender);
}

/** Saves a text and queues it for the bedside, or holds it for a caregiver. Safe to repeat for the same message. */
export async function receiveText(store: FamilyStore, householdID: string, text: { messageSID: string; from: string; body: string; pictures: number }, now: number) {
  const id = textMessageID(text.messageSID);
  const record: TextRecord = { id, from: text.from, body: text.body, pictures: text.pictures, receivedAt: now };
  // The words first, so the bedside never sees a text it can't fetch.
  if (!await store.create(textKey(householdID, id), JSON.stringify(record), textLimits.keepSeconds) && !await saved(store, householdID, id)) return false;
  const { result: queued } = await mutate(store, householdID, house => {
    house.texts ??= [];
    if (house.texts.some(entry => entry.id === id)) return true;
    const holding = !knownCaller(house, text.from);
    if (!textsOpen(house, text.from, holding, now)) return false;
    house.texts.push({ id, from: text.from, sentAt: now, ...(text.pictures ? { pictures: text.pictures } : {}), ...(holding ? { held: true } : {}) });
    return true;
  });
  if (!queued) await endText(store, householdID, id);
  return queued;
}

/** Expires week-old unread texts, and releases held ones from numbers the household has since saved or allowed. Runs on bedside polls. */
export async function maintainTexts(store: FamilyStore, house: Household, now: number) {
  const due = (entry: TextEntry) => !live(entry, now) || (entry.held === true && !held(house, entry));
  if (!(house.texts ?? []).some(due)) return;
  // The words of an expired text are already due to expire with it.
  await mutate(store, house.id, current => {
    current.texts = (current.texts ?? []).filter(entry => live(entry, now));
    for (const entry of current.texts) if (entry.held && !held(current, entry)) delete entry.held;
  });
}

/** What the bedside shows and reads for a text in its language. A text in that language already is read as it was sent. */
async function readable(store: FamilyStore, householdID: string, record: TextRecord, language: BedsideLanguage, now: number, translate?: Translate): Promise<{ text: string; translated: boolean; language?: string }> {
  const cached = record.translations?.[language];
  if (cached) return cached;
  // A picture alone has no words.
  if (!record.body) return { text: "", translated: false };
  const using = translate ?? (translationConfigured() ? claudeTranslate : undefined);
  if (!using) return { text: record.body, translated: false };
  let translation: Translation;
  try {
    translation = await using(record.body, language);
    // A text in the bedside's language is read as it was sent.
    if (!translation.translated) translation = { ...translation, text: record.body };
    requireValue(translation.text.length > 0 && translation.text.length <= textLimits.translatedCharacters, "This translation can't be shown.");
  } catch {
    // The bedside fetches it again in a minute. After a while it shows the text as it was sent, rather than nothing.
    if (now - record.receivedAt < textLimits.retrySeconds) throw new FamilyError("Translation isn't available right now.", 503);
    return { text: record.body, translated: false };
  }
  await updateRecord(store, householdID, record.id, now, r => { r.translations = { ...r.translations, [language]: translation }; });
  return translation;
}

/** Whether the bedside may have this sentence read in a natural voice although it's longer than an announcement:
 * it's what the bedside shows for a text it can play. */
export async function readableText(store: FamilyStore, house: Household, id: unknown, language: BedsideLanguage, text: string, now: number) {
  if (typeof id !== "string" || !uuid.test(id) || text.length > textLimits.spokenCharacters) return false;
  const entry = (house.texts ?? []).find(e => e.id === id);
  const record = entry && live(entry, now) && !held(house, entry) ? await saved(store, house.id, id) : undefined;
  return !!record && (record.translations?.[language]?.text === text || record.body === text);
}

function textID(input: Record<string, unknown>) {
  requireValue(typeof input.textID === "string" && uuid.test(input.textID), "This text was not found.", 404);
  return input.textID;
}

export async function handleTextAction(action: string, { store, now, house, me, input, translate }: TextContext): Promise<object> {
  if (action === "caregiverTexts") {
    // Caregiver review, PIN-checked before this point: each text's words, with what the bedside showed if it was translated.
    const entries = (house.texts ?? []).filter(entry => live(entry, now));
    const records = await Promise.all(entries.map(entry => saved(store, house.id, entry.id)));
    return { texts: entries.flatMap((entry, index) => {
      const record = records[index];
      if (!record) return [];
      const translation = record.translations?.[bedsideLanguage(house)];
      return [{ id: entry.id, from: entry.from, sentAt: entry.sentAt, held: held(house, entry), delivered: entry.deliveredAt !== undefined, body: record.body,
        ...(record.pictures ? { pictures: record.pictures } : {}), ...(translation?.translated ? { translation: translation.text, sourceLanguage: translation.language } : {}) }];
    }) };
  }
  const id = textID(input);
  const entry = (house.texts ?? []).find(e => e.id === id);
  if (action === "releaseText") {
    requireValue(entry, "This text was already read or removed.", 404);
    await mutate(store, house.id, current => { const e = current.texts?.find(e => e.id === id); if (e) delete e.held; });
    return { released: true };
  }
  if (action === "removeText") {
    requireValue(entry, "This text was already read or removed.", 404);
    await endText(store, house.id, id);
    return { removed: true };
  }
  requireValue(me.role === "bedside", "Only the bedside device shows texts.", 403);
  if (action === "textRead") {
    // Already read or removed: nothing left to do. A held text stays until a caregiver releases or removes it.
    // Its id is on the bedside snapshot, and reading it deletes the words the caregiver reviews.
    if (entry && held(house, entry)) throw new FamilyError("A caregiver needs to review this text first.", 403);
    if (entry) await endText(store, house.id, id);
    return { ok: true };
  }
  // textMessage: the bedside fetches a text to show and read.
  requireValue(entry && live(entry, now), "This text is no longer available.", 404);
  requireValue(!held(house, entry), "A caregiver needs to review this text first.", 403);
  const record = await saved(store, house.id, id);
  requireValue(record, "This text is no longer available.", 404);
  const language = bedsideLanguage(house);
  const shown = await readable(store, house.id, record, language, now, translate);
  if (entry.deliveredAt === undefined) await mutate(store, house.id, current => { const e = current.texts?.find(e => e.id === id); if (e) e.deliveredAt ??= now; });
  return { text: { id, from: record.from, sentAt: entry.sentAt, body: record.body, ...(record.pictures ? { pictures: record.pictures } : {}), language,
    text: shown.text, translated: shown.translated, ...(shown.language ? { sourceLanguage: shown.language } : {}) } };
}

export async function handleTwilioText(request: Request, dependencies: TextDependencies = {}) {
  const configured = settings();
  // Without the account's auth token, requests can't be verified as Twilio's.
  if (!configured) return new Response("Text messages aren't configured on this server.", { status: 503 });
  const body = await request.text();
  // The longest text, encoded, with everything Twilio sends alongside it.
  if (body.length > 65536) return new Response("Request too large.", { status: 413 });
  const params = new URLSearchParams(body);
  if (!signed(request.url, params, configured.authToken, request.headers.get("x-twilio-signature")) || params.get("AccountSid") !== configured.accountSID) {
    return new Response("Invalid Twilio signature.", { status: 403 });
  }
  try {
    const store = dependencies.store ?? familyStore();
    const now = dependencies.now?.() ?? Math.floor(Date.now() / 1000);
    const messageSID = params.get("MessageSid") ?? "", from = params.get("From") ?? "";
    const text = [...(params.get("Body") ?? "").trim()].slice(0, textLimits.characters).join("");
    const pictures = Math.min(textLimits.pictures, Math.max(0, Math.floor(Number(params.get("NumMedia")) || 0)));
    // An empty reply, so nothing is texted back. Twilio already answered STOP, START and HELP, which aren't for Mom.
    if (!messageSIDPattern.test(messageSID) || !senderPattern.test(from) || params.get("OptOutType") || keywords.has(text.toUpperCase()) || (!text && !pictures)) return reply();
    const house = await household(store, params.get("To"));
    if (house) await receiveText(store, house.id, { messageSID, from, body: text, pictures }, now);
    return reply();
  } catch {
    // No numbers or words in logs; Twilio's console shows the failed request.
    return reply(500);
  }
}
