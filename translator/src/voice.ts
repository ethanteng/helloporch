import { languages, type Language } from "./languages.ts";

// The translator speaks in the household's natural voice for each language (lib/family/speech.ts), streamed from
// ElevenLabs as raw 24 kHz audio so it can start playing before the whole sentence is ready. A family member who
// recorded their own voice (lib/family/voices.ts) is heard in it.
// ElevenLabs' announcement model, which the family chose voices with; it starts speaking within about half a second.
export const voiceSampleRate = 24_000;
export const voiceModel = "eleven_v4";
/** How long a caregiver's own voice has to start before the listed voice says the sentence instead. Both start in well
 * under a second (0.66 s for a recorded voice in Mandarin, 2026-11-27), so only a stuck request waits this long. */
export const ownVoiceStartMs = 3_000;

/** Yields the sentence's audio as 16-bit mono samples, a chunk at a time. It gives up after 20 seconds, or when
 * `signal` aborts. */
export async function* elevenLabsVoice(text: string, voiceID: string, language: Language, apiKey: string, signal?: AbortSignal): AsyncGenerator<Int16Array> {
  const limit = AbortSignal.timeout(20_000);
  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceID)}/stream?output_format=pcm_${voiceSampleRate}`, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({ text, model_id: voiceModel, language_code: languages[language].speak }),
    signal: signal ? AbortSignal.any([signal, limit]) : limit,
  });
  if (!response.ok || !response.body) throw new Error(`ElevenLabs answered ${response.status}.`);
  let carry: Uint8Array | undefined;
  const reader = response.body.getReader();
  for (;;) {
    const { value: chunk, done } = await reader.read();
    if (done) break;
    const bytes = carry ? concat(carry, chunk) : chunk;
    const whole = bytes.length - (bytes.length % 2);
    carry = whole < bytes.length ? bytes.slice(whole) : undefined;
    if (whole) yield new Int16Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + whole));
  }
}

/** A voice that hadn't started within `ownVoiceStartMs`. It may only be slow, so it's tried again on the next sentence. */
export class VoiceDidNotStart extends Error {}

/** Says it in the first of `voiceIDs`, or, when that one fails or hasn't started within `startMs`, the next: a
 * caregiver's own voice removed during the call, or stuck, is followed by the listed voice. Audio that started isn't
 * said again. `speakIn` stops when its signal aborts. */
export async function* firstVoiceThatSpeaks(voiceIDs: string[], speakIn: (voiceID: string, signal: AbortSignal) => AsyncIterable<Int16Array>,
  failed?: (voiceID: string, error: unknown) => void, startMs = ownVoiceStartMs): AsyncGenerator<Int16Array> {
  const choices = [...new Set(voiceIDs)];
  for (const [i, voiceID] of choices.entries()) {
    const last = i === choices.length - 1;
    const stop = new AbortController();
    // The last choice has nothing to give way to, so it keeps the request's own limit.
    const timer = last ? undefined : setTimeout(() => stop.abort(new VoiceDidNotStart(`The voice didn't start in ${startMs} ms.`)), startMs);
    let started = false;
    try {
      for await (const chunk of speakIn(voiceID, stop.signal)) {
        if (!started) { started = true; clearTimeout(timer); }
        yield chunk;
      }
      return;
    } catch (error) {
      if (started || last) throw error;
      failed?.(voiceID, stop.signal.aborted ? stop.signal.reason : error);
    } finally {
      clearTimeout(timer);
    }
  }
}

function concat(a: Uint8Array, b: Uint8Array) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a); out.set(b, a.length);
  return out;
}
