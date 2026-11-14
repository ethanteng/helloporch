import { languages, type Language } from "./languages.ts";

// The translator speaks in the household's natural voice for each language (lib/family/speech.ts), streamed from
// ElevenLabs as raw 24 kHz audio so it can start playing before the whole sentence is ready.
// ElevenLabs' announcement model, which the family chose voices with; it starts speaking within about half a second.
export const voiceSampleRate = 24_000;
export const voiceModel = "eleven_v4";

/** Yields the sentence's audio as 16-bit mono samples, a chunk at a time. */
export async function* elevenLabsVoice(text: string, voiceID: string, language: Language, apiKey: string, signal?: AbortSignal): AsyncGenerator<Int16Array> {
  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceID)}/stream?output_format=pcm_${voiceSampleRate}`, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "content-type": "application/json" },
    body: JSON.stringify({ text, model_id: voiceModel, language_code: languages[language].speak }),
    signal: signal ?? AbortSignal.timeout(20_000),
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

function concat(a: Uint8Array, b: Uint8Array) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a); out.set(b, a.length);
  return out;
}
