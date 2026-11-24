import { createHash } from "node:crypto";
import { bedsideDevice, FamilyError, isCaregiver, mutate, requireValue, type BedsideLanguage, type Household, type Member } from "./household.ts";
import type { MediaStore } from "./media.ts";
import { discardMedia } from "./messages.ts";
import type { FamilyStore } from "./store.ts";
import { keepTextClip, readableText, textKept } from "./texts.ts";
import { familyVoiceFolder, familyVoices, isFamilyVoice } from "./voices.ts";

// Natural announcement voices. Each bedside language offers a few ElevenLabs voices the family listened to
// (scripts/voice-samples.mjs); a caregiver picks one per language, or keeps the iPad's built-in voice.
// The server reads the bedside's sentences, and phone voicemail's greetings, aloud and keeps each clip in the
// private media store, so a sentence is paid for once. The bedside uses its built-in voice whenever a clip isn't ready.
// Caregivers can also record their own voice (voices.ts), which is offered in every language after the listed ones.
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
  // ElevenLabs calls Tagalog Filipino.
  tl: { code: "fil", voices: [
    { id: "4RLeKvASM0Zt73Htf5GF", name: "Maria", detail: "Soothing, gentle and clear · female" },
    { id: "mOYuoC0AAGM3erLKflvc", name: "Nanay Pilar", detail: "Calm, warm host · female" },
    { id: "MUVOVB3VWCo7pumU3SIO", name: "Kuya Manny", detail: "Soothing, fatherly narrator · male" },
  ] },
  ko: { code: "ko", voices: [
    { id: "uyVNoMrnUku1dZyVEXwD", name: "Anna Kim", detail: "Tender, calm and clear · female" },
    { id: "ksaI0TCD9BstzEzlxj4q", name: "Seulki", detail: "Inviting, calm and measured · female" },
    { id: "YBRudLRm83BV5Mazcr42", name: "Jason", detail: "Gentle, calm and measured · male" },
  ] },
  he: { code: "he", voices: [
    { id: "s0T0DT6EAPeX57MQpn3I", name: "Danit", detail: "Natural and clear · female" },
    { id: "ZiofZHcEBTn5sRySe5h8", name: "Nimrod", detail: "Warm and confident · male" },
    { id: "l7Q9rbdCC6j3J5dNlOOg", name: "Itamar", detail: "Clear, steady narrator · male" },
  ] },
};
export const speechModel = "eleven_v4";
/** What a caregiver's phone hears in a voice before choosing it: the bedside's own preview, a drop-in announcement
 * (BedsideLanguage's "%@ is dropping in with video. Connecting in five seconds." with "A family member"). It is the
 * server's own sentence, so a phone can't make a caregiver's voice say anything else. */
export const previewSentences: Record<BedsideLanguage, string> = {
  en: "A family member is dropping in with video. Connecting in five seconds.",
  "zh-Hant": "家人要和您視訊通話，五秒後接通。",
  "zh-Hans": "家人要和您视频通话，五秒后接通。",
  "yue-Hant": "屋企人想同您視像通話，五秒後接通。",
  es: "Un familiar quiere hablar con usted por vídeo. La llamada se conectará en cinco segundos.",
  tl: "Tumatawag po si Kapamilya sa video call. Kokonekta ito sa loob ng limang segundo.",
  ko: "가족에게서 영상통화가 왔어요. 5초 후에 연결돼요.",
  // The apps isolate a name in a right-to-left sentence (U+2068…U+2069), so this matches the bedside's own preview and
  // shares its clip.
  he: "שיחת וידאו מאת \u2068מישהו מהמשפחה\u2069. מתחברים בעוד חמש שניות.",
};
// Announcements are a sentence or two. The daily allowance covers a new household's first clips
// several times over, while keeping one device from spending the whole plan.
export const speechLimits = { textCharacters: 300, dailyCharacters: 4000, audioBytes: 2_000_000, downloadSeconds: 3600 };
// `previewSpeech`: a caregiver's phone hears a voice before choosing it, as the bedside's settings do with `speech`.
export const speechActions = new Set(["speech", "setSpeechVoice", "previewSpeech"]);
// The bedside plays clips at full quality; a phone line carries 8 kHz, so phone voicemail greetings are small.
export const speechFormats = { bedside: "mp3_44100_128", phone: "mp3_22050_32" } as const;
export type SpeechFormat = keyof typeof speechFormats;
export type Synthesize = (voiceID: string, languageCode: string, text: string, outputFormat: string) => Promise<Uint8Array>;
export type ClipContext = { store: FamilyStore; media: () => MediaStore; now: number; house: Household; synthesize?: Synthesize };
export type SpeechContext = ClipContext & { me: Member; input: Record<string, unknown> };

export function speechConfigured() { return !!process.env.ELEVENLABS_API_KEY; }
/** The household's voice for a language: unset is the default, null is the iPad's built-in voice.
 * Phone callers never hear a family voice (`family` false): the language's default greets them instead. */
export function speechVoice(house: Household, language: string, family = true): string | null {
  const choice = house.speechVoices?.[language];
  if (choice === null) return null;
  const { voices } = speechCatalog[language];
  if (family && isFamilyVoice(house, choice)) return choice as string;
  return voices.find(v => v.id === choice)?.id ?? voices[0].id;
}
/** A voice that can be chosen for a language: a listed one, or a caregiver's own. */
function offered(house: Household, language: string, voiceID: unknown): voiceID is string {
  return typeof voiceID === "string" && (speechCatalog[language].voices.some(v => v.id === voiceID) || isFamilyVoice(house, voiceID));
}
/** What the voice settings offer, per language: the listed voices, then caregivers' own, which say whose they are. */
export function publicSpeech(house: Household) {
  const family = familyVoices(house);
  return { languages: Object.fromEntries(Object.entries(speechCatalog).map(([language, { voices }]) =>
    [language, { selected: speechVoice(house, language), defaultVoice: voices[0].id, voices: [...voices, ...family] }])) };
}

async function elevenLabs(voiceID: string, languageCode: string, text: string, outputFormat: string): Promise<Uint8Array> {
  const key = process.env.ELEVENLABS_API_KEY;
  requireValue(key, "Natural voices aren't set up on this server.", 503);
  let response: Response;
  try {
    response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceID}?output_format=${outputFormat}`, {
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
    requireValue(voiceID === null || offered(house, language, voiceID), "Choose one of the listed voices.");
    await mutate(store, house.id, latest => {
      requireValue(latest.members.some(m => m.id === me.id && !m.revoked && isCaregiver(m)), "Only an approved caregiver can change access.", 403);
      requireValue(voiceID === null || offered(latest, language, voiceID), "Choose one of the listed voices.");
      latest.speechVoices = { ...latest.speechVoices, [language]: voiceID };
    });
    return {};
  }
  // A caregiver action on a phone, PIN-checked before this point; the bedside previews with `speech`.
  if (action === "previewSpeech") requireValue(me.role === "family" && me.caregiver, "Only a caregiver can preview voices.", 403);
  else requireValue(me.role === "bedside", "Only the bedside speaks announcements.", 403);
  requireValue(synthesize || speechConfigured(), "Natural voices aren't set up on this server.", 503);
  // A phone's preview reads the server's sentence, whatever it sends: a family voice says only what Porch says.
  const text = action === "previewSpeech" ? previewSentences[language as BedsideLanguage] : typeof input.text === "string" ? input.text.trim() : "";
  // A text message's words, which can be longer than an announcement, up to their own limit.
  const textID = action === "speech" && text.length > 0 && await readableText(store, house, input.textID, language as BedsideLanguage, text, now) ? input.textID as string : undefined;
  requireValue(text.length > 0 && (text.length <= speechLimits.textCharacters || textID), `Announcements can have up to ${speechLimits.textCharacters} characters.`);
  // Settings preview a listed voice before it's saved; otherwise it's the household's choice.
  const requested = input.voiceID;
  requireValue(requested === undefined || offered(house, language, requested), "Choose one of the listed voices.");
  const voiceID = requested ?? speechVoice(house, language);
  requireValue(voiceID, `This language uses the ${bedsideDevice(house)}'s built-in voice.`, 409);
  if (!textID) {
    try { return { clip: await speechClip({ store, media, now, house, synthesize }, voiceID, language, text) }; }
    catch (error) {
      // The daily allowance, as 409 on a caregiver's phone, where 429 ends caregiver mode as too many PIN tries.
      if (action === "previewSpeech" && error instanceof FamilyError && error.status === 429) throw new FamilyError(error.message, 409);
      throw error;
    }
  }
  // A text's words are private: their reading is kept apart and deleted with the text.
  const folder = `texts/${textID}`;
  const pathname = clipPathname(house.id, voiceID, language, text, "bedside", folder);
  requireValue(await keepTextClip(store, house.id, textID, pathname, now), "This text is no longer available.", 404);
  const clip = await speechClip({ store, media, now, house, synthesize }, voiceID, language, text, "bedside", folder);
  // Spoken after the clip is recorded. A text read or removed in that gap would otherwise keep the file
  // until its record expired.
  if (!await textKept(store, house.id, textID)) {
    await discardMedia(store, media, house.id, [pathname], now);
    throw new FamilyError("This text is no longer available.", 404);
  }
  return { clip };
}

/** Where a sentence's clip is kept. The same sentence in the same voice is the same clip; names stay out of the path. */
export function clipPathname(householdID: string, voiceID: string, language: string, text: string, format: SpeechFormat = "bedside", folder?: string) {
  const key = [speechModel, voiceID, language, text, ...(format === "bedside" ? [] : [format])];
  return `speech/${householdID}/${folder ? `${folder}/` : ""}${createHash("sha256").update(JSON.stringify(key)).digest("hex")}.mp3`;
}

/** A sentence read in an offered voice, and a short-lived link to it. Kept in the media store, so it's paid for once.
 * A family voice's sentences are kept in its own folder, which is deleted with it. */
export async function speechClip({ store, media, now, house, synthesize }: ClipContext, voiceID: string, language: string, text: string, format: SpeechFormat = "bedside", folder?: string) {
  const pathname = clipPathname(house.id, voiceID, language, text, format, folder ?? (isFamilyVoice(house, voiceID) ? familyVoiceFolder(voiceID) : undefined));
  if (!await media().stat(pathname)) {
    // Counted before asking, so failing requests can't run up the plan either.
    const day = Math.floor(now / 86400);
    await mutate(store, house.id, latest => {
      const used = latest.speechUsage?.day === day ? latest.speechUsage.characters : 0;
      requireValue(used + text.length <= speechLimits.dailyCharacters, "Natural voices are resting until tomorrow. The built-in voice is used meanwhile.", 429);
      latest.speechUsage = { day, characters: used + text.length };
    });
    const audio = await (synthesize ?? elevenLabs)(voiceID, speechCatalog[language].code, text, speechFormats[format]);
    requireValue(audio.length > 0 && audio.length <= speechLimits.audioBytes, "Natural voices aren't available right now.", 503);
    await media().put(pathname, audio, "audio/mpeg");
    // The voice may have been removed while this clip was made. Its folder is already gone by then, so this file
    // would otherwise stay. Don't hand out a link to it.
    if (isFamilyVoice(house, voiceID)) {
      const raw = await store.get(`house:${house.id}`);
      const latest: Household | undefined = raw ? JSON.parse(raw) : undefined;
      if (!latest || !isFamilyVoice(latest, voiceID)) {
        await discardMedia(store, media, house.id, [pathname], now);
        throw new FamilyError("Natural voices aren't available right now.", 503);
      }
    }
  }
  const expiresAt = now + speechLimits.downloadSeconds;
  return { voiceID, url: await media().downloadURL(pathname, expiresAt), expiresAt };
}
