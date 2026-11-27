import type { Language } from "./languages.ts";
import { readAhead } from "./read-ahead.ts";

// What the translator does with each thing someone says, kept apart from LiveKit so it can be tested.
// The bedside is one side of the call; everyone else (family on Porch, a phone guest) is the other.
// Speech from one side is said again in the other side's language, unless it's already in it.
export type Side = "bedside" | "family";
/** One thing someone said. `said` is what the translator said for the other side, null when it didn't need saying. */
export type Line = { id: string; speaker: string; name: string; side: Side; heard: string; said: string | null; language: Language; at: number };
/** What to say for the listener, a bit at a time as it's written, or nothing at all when nothing needs saying. */
export type Translate = (heard: string, from: Side, target: Language, recent: Line[]) => AsyncIterable<string>;
/** Sent to the call's apps on the `porch-translation` topic. */
export type Message =
  | ({ type: "line" } & Line)
  | { type: "state"; on: boolean; language: Language }
  | { type: "speaking"; on: boolean };
export type InterpreterDeps = {
  translate: Translate;
  /** Says each piece on one side's translation track in turn, starting as soon as the first arrives; resolves once
   * all of them have played. */
  speak: (to: Side, pieces: AsyncIterable<string>, language: Language) => Promise<void>;
  send: (message: Message, to: Side | "everyone") => void;
  now: () => number;
  log?: (message: string, detail?: unknown) => void;
};
export type InterpreterConfig = { bedside: string; bedsideLanguage: Language; familyLanguage: Language };
/** A translation under way: the pieces for the voice (see voicePieces), and all of it once it's written. */
type Translation = { pieces: AsyncIterable<string>; said: Promise<string | null> };

/** How long after the translator stops speaking its voice, picked up by a microphone, can still arrive from speech
 * recognition (about 1.2 s on test calls). Later speech is the person's own. */
export const echoTailMs = 5_000;
/** How closely recognized speech must match what the translator said to count as its echo. Recognition of the
 * translator's own voice matched it at 0.9 to 1 on test calls; a reply such as "I am not coming on Saturday." after
 * "Are you coming on Saturday?" is 0.71, and is the person's own. */
export const echoSimilarity = 0.85;
const recentLines = 6;

export class Interpreter {
  bedsideLanguage: Language;
  readonly familyLanguage: Language;
  private readonly recent: Line[] = [];
  /** What the translator said to each side; `ended` is unset while it's still speaking. */
  private readonly spoken: { side: Side; text: string; ended?: number }[] = [];
  private readonly speakers = new Map<string, Promise<void>>();
  private readonly playing: Record<Side, Promise<void>> = { bedside: Promise.resolve(), family: Promise.resolve() };
  private count = 0;
  readonly config: InterpreterConfig;
  private readonly deps: InterpreterDeps;

  constructor(config: InterpreterConfig, deps: InterpreterDeps) {
    this.config = config;
    this.deps = deps;
    this.bedsideLanguage = config.bedsideLanguage;
    this.familyLanguage = config.familyLanguage;
  }

  sideOf(identity: string): Side { return identity === this.config.bedside ? "bedside" : "family"; }

  /** Something a person finished saying. Its translation starts at once, even while the same person's sentence before
   * it is still being translated, but their lines reach family and are said in the order they were spoken. One that
   * fails, say because a message couldn't be sent, doesn't stop the ones after it. Never rejects. */
  heard(identity: string, name: string, text: string): Promise<void> {
    let report: (() => Promise<void>) | undefined;
    try { report = this.begin(identity, name, text); }
    catch (error) { this.deps.log?.("a sentence couldn't be handled", error); }
    const next = (this.speakers.get(identity) ?? Promise.resolve())
      .then(() => report?.())
      .catch(error => this.deps.log?.("a sentence couldn't be handled", error));
    this.speakers.set(identity, next);
    return next;
  }

  setLanguage(language: Language) {
    this.bedsideLanguage = language;
    this.deps.send({ type: "state", on: true, language }, "everyone");
  }

  /** Resolves once everything queued has been played. */
  async settled() {
    await Promise.all(this.speakers.values());
    await Promise.all(Object.values(this.playing));
  }

  /** Starts translating a sentence and queues it to be said; returns what tells family, in the speaker's order. */
  private begin(identity: string, name: string, heard: string) {
    const text = heard.trim();
    if (!text) return;
    const side = this.sideOf(identity);
    // A side's microphone can pick up the translator speaking to that side. That isn't the person talking.
    if (this.isEcho(side, text)) { this.deps.log?.("ignored an echo of the translator"); return; }
    const listener: Side = side === "bedside" ? "family" : "bedside";
    const target = listener === "bedside" ? this.bedsideLanguage : this.familyLanguage;
    const line: Line = { id: `${++this.count}`, speaker: identity, name, side, heard: text, said: null, language: target, at: 0 };
    const translation = this.translate(text, side, target, this.recent.slice(-recentLines));
    // The context is what people said, not what the translator said, so the next sentence needn't wait for this one.
    this.recent.push(line);
    if (this.recent.length > recentLines) this.recent.shift();
    this.playing[listener] = this.playing[listener].then(() => this.play(listener, line, translation))
      .catch(error => this.deps.log?.("a translation couldn't be played", error));
    return async () => {
      line.said = await translation.said;
      line.at = this.deps.now();
      // Family see everything heard and said, so they can tell when something was misheard. The bedside sees
      // only what the translator says to it, as it says it.
      this.deps.send({ type: "line", ...line }, "family");
    };
  }

  /** Reads the translation as it's written, without waiting for this line's turn to be said. */
  private translate(text: string, from: Side, target: Language, recent: Line[]): Translation {
    const deps = this.deps;
    let said = "";
    let settle!: (said: string | null) => void;
    const whole = new Promise<string | null>(resolve => { settle = resolve; });
    const pieces = readAhead((async function* () {
      const asked = deps.now();
      try {
        for await (const piece of voicePieces(deps.translate(text, from, target, recent))) {
          if (!said) deps.log?.(`translation started in ${deps.now() - asked} ms`);
          said += piece;
          yield piece;
        }
        deps.log?.(`translated in ${deps.now() - asked} ms`);
      } catch (error) {
        // What was already written is still said; the rest is left out rather than guessed at.
        deps.log?.("translation failed", error);
      } finally {
        settle(said.trim() || null);
      }
    })());
    return { pieces, said: whole };
  }

  private async play(listener: Side, line: Line, translation: Translation) {
    const pieces = translation.pieces[Symbol.asyncIterator]();
    const first = await pieces.next();
    if (first.done) return;
    const entry: { side: Side; text: string; ended?: number } = { side: listener, text: first.value };
    this.spoken.push(entry);
    while (this.spoken.length > 1 && this.spoken[0].ended !== undefined && this.deps.now() - this.spoken[0].ended > echoTailMs) this.spoken.shift();
    // The bedside's caption is the whole translation, so it goes once all of it is written, just after the voice starts.
    const caption = translation.said.then(said => {
      if (!said) return;
      entry.text = said;
      if (listener === "bedside") this.deps.send({ type: "line", ...line, said, at: this.deps.now() }, "bedside");
    }).catch(error => this.deps.log?.("a caption couldn't be sent", error));
    this.deps.send({ type: "speaking", on: true }, listener);
    try { await this.deps.speak(listener, prepend(first.value, pieces), line.language); }
    catch (error) { this.deps.log?.("speaking failed", error); }
    finally {
      await caption;
      entry.ended = this.deps.now();
      this.deps.send({ type: "speaking", on: false }, listener);
    }
  }

  /** Only while the translator is speaking to this side, or just after, and only an almost exact match. */
  private isEcho(side: Side, text: string) {
    const now = this.deps.now();
    return this.spoken.some(s => s.side === side && (s.ended === undefined || now - s.ended <= echoTailMs) && echoes(s.text, text));
  }
}

/** How much the first sentence must hold for the voice to start on it alone: about a second of speech, time enough
 * to fetch the voice for the rest without a pause. A Han, kana or Hangul character counts as three letters. */
export const firstPieceWeight = 20;

/** Splits what's written for the voice: the first sentence as soon as it's complete, when there's more after it and
 * it's long enough to say alone, then the rest in one piece. Together they're exactly what was written. Two pieces at
 * most, so a side never asks for more than one voice at a time (agent.ts fetches the next once one has arrived). */
export async function* voicePieces(text: AsyncIterable<string>): AsyncGenerator<string> {
  let buffer = "", split = false;
  for await (const delta of text) {
    buffer += delta;
    if (split) continue;
    const end = firstSentenceEnd(buffer);
    if (end === undefined) continue;
    yield buffer.slice(0, end);
    buffer = buffer.slice(end);
    split = true;
  }
  if (buffer.trim()) yield buffer;
}

function firstSentenceEnd(text: string) {
  // A full stop only counts before a space, so "10.5" and a period still being written don't split.
  // A period after one to three letters is "Dr." or "a.m.", not the end of the sentence.
  for (const end of sentenceEnds(text)) {
    if (weight(text.slice(0, end)) >= firstPieceWeight && text.slice(end).trim()) return end;
  }
  return undefined;
}

/** Offsets just after sentence punctuation. Skips a period that ends a one-to-three-letter word. */
function sentenceEnds(text: string) {
  const ends: number[] = [];
  for (const match of text.matchAll(/[。！？]|[.!?](?=\s)/g)) {
    const at = match.index;
    if (at === undefined || (match[0] === "." && abbreviates(text, at))) continue;
    ends.push(at + 1);
  }
  return ends;
}

function abbreviates(text: string, dot: number) {
  const word = text.slice(0, dot).match(/(\p{L}+)$/u)?.[1] ?? "";
  return word.length >= 1 && word.length <= 3;
}

function sentences(text: string) {
  const parts: string[] = [];
  let start = 0;
  for (const end of sentenceEnds(text)) {
    if (text.slice(start, end).trim()) parts.push(text.slice(start, end));
    start = end;
  }
  if (text.slice(start).trim()) parts.push(text.slice(start));
  return parts;
}

/** How much a sentence of a longer line must hold before it can count as the translator's echo on its own.
 * Below this, "OK" or "好" after a longer line is still the person talking. */
const echoSentenceWeight = 10;

/** A line spoken in two pieces can come back from the microphone one sentence at a time. */
function echoes(spoken: string, heard: string) {
  if (similarity(spoken, heard) >= echoSimilarity) return true;
  return sentences(spoken).some(part => weight(part) >= echoSentenceWeight && similarity(part, heard) >= echoSimilarity);
}

function weight(text: string) {
  let total = 0;
  for (const char of text) total += /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(char) ? 3 : /[\p{L}\p{N}]/u.test(char) ? 1 : 0;
  return total;
}

async function* prepend<T>(first: T, rest: AsyncIterator<T>) {
  yield first;
  for (let next = await rest.next(); !next.done; next = await rest.next()) yield next.value;
}

/** Dice similarity of character pairs, ignoring case, spaces and punctuation. Works for Chinese and English alike. */
export function similarity(a: string, b: string) {
  const pairs = (s: string) => {
    const letters = [...s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "")];
    const out = new Map<string, number>();
    for (let i = 0; i < letters.length - 1; i++) out.set(letters[i] + letters[i + 1], (out.get(letters[i] + letters[i + 1]) ?? 0) + 1);
    return { out, total: Math.max(letters.length - 1, 0) };
  };
  const x = pairs(a), y = pairs(b);
  if (!x.total || !y.total) return 0;
  let shared = 0;
  for (const [pair, n] of x.out) shared += Math.min(n, y.out.get(pair) ?? 0);
  return (2 * shared) / (x.total + y.total);
}
