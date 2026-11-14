# Porch call translator

A LiveKit agent that translates a Porch call between the bedside and family, live. The family member on the call
turns it on with **Translate** on their phone; every call starts with it off. The calling server
(`lib/family/translation.ts`) then dispatches this agent into the call's room and removes it when translation is
turned off.

For each sentence someone finishes:

1. **Hearing.** Google's live transcription (`google/gemini-3.5-transcribe-live`, through LiveKit Inference) listens to each
   person, with the family's and the bedside's languages as hints. It was the best of the models LiveKit offers at
   mixed English and Mandarin (`scripts/stt-bench.ts`); AssemblyAI is its fallback.
2. **Translating.** Claude (`src/translate.ts`) decides whether the listener needs it said again: a sentence entirely in
   their language passes through, and one with any other language in it is said again, all of it, in theirs.
3. **Speaking.** ElevenLabs reads it in the household's natural voice for that language, on that side's own track:
   `porch-translation-bedside` or `porch-translation-family`. Each app unsubscribes from the other side's track
   itself; LiveKit's server-side unsubscribe doesn't stop a participant that joined with auto-subscribe. A phone guest
   hears both. The apps lower the other voices while the translator speaks.

It also sends the words to the apps on the `porch-translation` data topic (`src/interpreter.ts`, `Message`): family see
what was heard and what was said; the bedside shows what is said to it.

Nothing that's said is stored or logged.

## Running it

```bash
npm install
npm test
npm run typecheck
```

It needs `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` (LiveKit Cloud sets these for a deployed agent),
`ANTHROPIC_API_KEY` and `ELEVENLABS_API_KEY`. Locally, `npm run dev` registers a worker named `porch-translator`
with the project in `LIVEKIT_URL`. It only joins rooms it's dispatched to.

## Testing a call

`scripts/call-test.ts` joins "mom" and "ethan" to a test room, dispatches the translator, plays recorded sentences
from each in turn and reports what was heard and said, how long after each sentence the words and voice arrived, and
saves what each side heard as WAV files. Run it against a local LiveKit server (`livekit-server --dev`) with the worker
pointed there, and speech recognition still going through LiveKit Cloud:

```bash
LIVEKIT_URL=ws://localhost:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret \
  LIVEKIT_INFERENCE_API_KEY=… LIVEKIT_INFERENCE_API_SECRET=… ANTHROPIC_API_KEY=… ELEVENLABS_API_KEY=… npm run dev
LIVEKIT_URL=ws://localhost:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret node scripts/call-test.ts <clips folder>
```

On 2026-11-14, with mixed English and Mandarin sentences, the listener saw the words 2.0 to 3.1 seconds after a
sentence ended and heard them 2.6 to 3.8 seconds after: about 1.2 s to recognize, 0.8 to 1.7 s to translate (Claude
Opus 5.5 in fast mode) and 0.5 s for the voice to start. `scripts/translate-check.ts` runs the translation step alone,
and `scripts/stt-bench.ts` compares speech recognition models.

## Deploying

With the LiveKit CLI (`lk`), signed in to the HelloPorch project:

```bash
lk agent create --secrets ANTHROPIC_API_KEY=… --secrets ELEVENLABS_API_KEY=…   # first time; writes livekit.toml
lk agent deploy                                                                  # later versions
```

Then set `LIVEKIT_TRANSLATOR_AGENT=porch-translator` on the calling server (Vercel project `porch-calling-prototype`).
Until it's set, Porch doesn't offer translation.

## Limits

- Each person on a translated call keeps one speech-to-text connection open: two for an ordinary call, three when
  someone was rung in. The project allows 5 at once, so about two translated calls at a time.
- Each sentence said to someone uses ElevenLabs characters from the household's plan.
