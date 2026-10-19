import { createHash } from "node:crypto";
import { FamilyError, isCaregiver, mutate, requireValue, type Household, type Member } from "./household.ts";
import type { MediaStore } from "./media.ts";
import type { FamilyStore } from "./store.ts";

// Natural announcement voices. Each bedside language offers a few ElevenLabs voices the family listened to
// (scripts/voice-samples.mjs); a caregiver picks one per language, or keeps the iPad's built-in voice.
// The server reads the bedside's sentences aloud and keeps each clip in the private media store, so a
// sentence is paid for once. The bedside uses its built-in voice whenever a clip isn't ready.
export type SpeechVoice = { id: string; name: string; detail: string };
/** Keyed by the bedside's language codes; `code` is ElevenLabs' language. Each language's first voice is its default. */
export const speechCatalog: Record<string, { code: string; voices: SpeechVoice[] }> = {
  en: { code: "en", voices: [
    { id: "OYTbf65OHHFELVut7v2H", name: "Hope", detail: "Natural, clear and calm · female" },
    { id: "MFZUKuGQUsGJPQjTS4wC", name: "Jon", detail: "Warm and grounded · male" },
    { id: "g6xIsTj2HwM6VR4iXFCw", name: "Jessica", detail: "Chatty and friendly · female" },
  ] },
  "zh-Hant": { code: "zh", voices: [
    { id: "Z8Aisvg1z70p27kGvkZZ", name: "Ling", detail: "Steady, calm and grounded · female" },
    { id: "BrbEfHMQu0fyclQR7lfh", name: "Kevin Tu", detail: "Natural, steady and calm · male" },
    { id: "r6qgCCGI7RWKXCagm158", name: "Anna Su", detail: "Trustworthy, clear and natural · female" },
  ] },
  "zh-Hans": { code: "zh", voices: [
    { id: "APSIkVZudNbPAwyPoeVO", name: "Sage", detail: "Soothing and gentle · female" },
    { id: "4VZIsMPtgggwNg7OXbPY", name: "James Gao", detail: "Calm, friendly and warm · male" },
    { id: "Ca5bKgudqKJzq8YRFoAz", name: "Coco Li", detail: "Calm, young and trustworthy · female" },
  ] },
  "yue-Hant": { code: "yue", voices: [
    { id: "7rrBp44bogxpbQBDkenR", name: "Suk Yee", detail: "Direct, warm narrator · female" },
    { id: "El018FmI047NtSsCfyrY", name: "Nina", detail: "Sweet and warm · female" },
    { id: "R5E9sH7cGUEbuu7YE7K7", name: "Lucky Chan", detail: "Warm and calm · male" },
    { id: "2HZgeWhEm3MJfPZ0MsrV", name: "Chun Wai", detail: "Calm, warm narrator · male" },
  ] },
  es: { code: "es", voices: [
    { id: "RgXx32WYOGrd7gFNifSf", name: "Eva Dorado", detail: "Warm and soft · female" },
    { id: "UOIqAnmS11Reiei1Ytkc", name: "Carolina", detail: "Natural, neutral and clear · female" },
    { id: "y6WtESLj18d0diFRruBs", name: "David Martin", detail: "Clear, calm and elegant · male" },
  ] },
};
export const speechModel = "eleven_v4";
// Announcements are a sentence or two. The daily allowance covers a new household's first clips
// several times over, while keeping one device from spending the whole plan.
export const speechLimits = { textCharacters: 300, dailyCharacters: 4000, audioBytes: 2_000_000, downloadSeconds: 3600 };
export const speechActions = new Set(["speech", "setSpeechVoice"]);
export type Synthesize = (voiceID: string, languageCode: string, text: string) => Promise<Uint8Array>;
export type SpeechContext = { store: FamilyStore; media: () => MediaStore; now: number; house: Household; me: Member; input: Record<string, unknown>; synthesize?: Synthesize };

export function speechConfigured() { return !!process.env.ELEVENLABS_API_KEY; }
/** The household's voice for a language: unset is the default, null is the iPad's built-in voice. */
export function speechVoice(house: Household, language: string): string | null {
  const choice = house.speechVoices?.[language];
  if (choice === null) return null;
  const { voices } = speechCatalog[language];
  return voices.find(v => v.id === choice)?.id ?? voices[0].id;
}
/** What the bedside's voice settings offer, per language. */
export function publicSpeech(house: Household) {
  return { languages: Object.fromEntries(Object.entries(speechCatalog).map(([language, { voices }]) =>
    [language, { selected: speechVoice(house, language), defaultVoice: voices[0].id, voices }])) };
}

async function elevenLabs(voiceID: string, languageCode: string, text: string): Promise<Uint8Array> {
  const key = process.env.ELEVENLABS_API_KEY;
  requireValue(key, "Natural voices aren't set up on this server.", 503);
  let response: Response;
  try {
    response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceID}?output_format=mp3_44100_128`, {
      method: "POST", headers: { "xi-api-key": key, "Content-Type": "application/json", Accept: "audio/mpeg" },
      body: JSON.stringify({ text, model_id: speechModel, language_code: languageCode }), signal: AbortSignal.timeout(15_000) });
  } catch { throw new FamilyError("Natural voices aren't available right now.", 503); }
  // The response can quote the sentence, which may include names, so it isn't logged.
  if (!response.ok) throw new FamilyError("Natural voices aren't available right now.", 503);
  return new Uint8Array(await response.arrayBuffer());
}

export async function handleSpeechAction(action: string, { store, media, now, house, me, input, synthesize }: SpeechContext): Promise<object> {
  const language = input.language;
  requireValue(typeof language === "string" && Object.hasOwn(speechCatalog, language), "Choose a bedside language.");
  if (action === "setSpeechVoice") {
    // A caregiver action, PIN-checked before this point.
    const voiceID = input.voiceID;
    requireValue(voiceID === null || (typeof voiceID === "string" && speechCatalog[language].voices.some(v => v.id === voiceID)), "Choose one of the listed voices.");
    await mutate(store, house.id, latest => {
      requireValue(latest.members.some(m => m.id === me.id && !m.revoked && isCaregiver(m)), "Only an approved caregiver can change access.", 403);
      latest.speechVoices = { ...latest.speechVoices, [language]: voiceID };
    });
    return {};
  }
  requireValue(me.role === "bedside", "Only the bedside speaks announcements.", 403);
  requireValue(synthesize || speechConfigured(), "Natural voices aren't set up on this server.", 503);
  const text = typeof input.text === "string" ? input.text.trim() : "";
  requireValue(text.length > 0 && text.length <= speechLimits.textCharacters, `Announcements can have up to ${speechLimits.textCharacters} characters.`);
  // Settings preview a listed voice before it's saved; otherwise it's the household's choice.
  const requested = input.voiceID;
  requireValue(requested === undefined || (typeof requested === "string" && speechCatalog[language].voices.some(v => v.id === requested)), "Choose one of the listed voices.");
  const voiceID = requested ?? speechVoice(house, language);
  requireValue(voiceID, "This language uses the iPad's built-in voice.", 409);
  // The same sentence in the same voice is the same clip; names stay out of the path.
  const pathname = `speech/${house.id}/${createHash("sha256").update(JSON.stringify([speechModel, voiceID, language, text])).digest("hex")}.mp3`;
  if (!await media().stat(pathname)) {
    // Counted before asking, so failing requests can't run up the plan either.
    const day = Math.floor(now / 86400);
    await mutate(store, house.id, latest => {
      const used = latest.speechUsage?.day === day ? latest.speechUsage.characters : 0;
      requireValue(used + text.length <= speechLimits.dailyCharacters, "Natural voices are resting until tomorrow. The built-in voice is used meanwhile.", 429);
      latest.speechUsage = { day, characters: used + text.length };
    });
    const audio = await (synthesize ?? elevenLabs)(voiceID, speechCatalog[language].code, text);
    requireValue(audio.length > 0 && audio.length <= speechLimits.audioBytes, "Natural voices aren't available right now.", 503);
    await media().put(pathname, audio, "audio/mpeg");
  }
  const expiresAt = now + speechLimits.downloadSeconds;
  return { clip: { voiceID, url: await media().downloadURL(pathname, expiresAt), expiresAt } };
}
