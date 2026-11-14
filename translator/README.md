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
3. **Speaking.** ElevenLabs reads it in the household's natural voice for that language, on a track only that side
   hears: `porch-translation-bedside` or `porch-translation-family`. The apps lower the other voices while it speaks.

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
