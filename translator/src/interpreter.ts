import type { Language } from "./languages.ts";

// What the translator does with each thing someone says, kept apart from LiveKit so it can be tested.
// The bedside is one side of the call; everyone else (family on Porch, a phone guest) is the other.
// Speech from one side is said again in the other side's language, unless it's already in it.
export type Side = "bedside" | "family";
/** One thing someone said. `said` is what the translator said for the other side, null when it didn't need saying. */
export type Line = { id: string; speaker: string; name: string; side: Side; heard: string; said: string | null; language: Language; at: number };
export type Rendering = { say: boolean; text: string };
export type Translate = (heard: string, from: Side, target: Language, recent: Line[]) => Promise<Rendering>;
/** Sent to the call's apps on the `porch-translation` topic. */
export type Message =
  | ({ type: "line" } & Line)
  | { type: "state"; on: boolean; language: Language }
  | { type: "speaking"; on: boolean };
export type InterpreterDeps = {
  translate: Translate;
  /** Plays `text` to one side's translation track; resolves once it has played. */
  speak: (to: Side, text: string, language: Language) => Promise<void>;
  send: (message: Message, to: Side | "everyone") => void;
  now: () => number;
  log?: (message: string, detail?: unknown) => void;
};
export type InterpreterConfig = { bedside: string; bedsideLanguage: Language; familyLanguage: Language };

/** How long the translator's own voice can come back through a microphone and still be recognized as an echo. */
export const echoWindowMs = 20_000;
const recentLines = 6;

export class Interpreter {
  bedsideLanguage: Language;
  readonly familyLanguage: Language;
  private readonly recent: Line[] = [];
  private readonly spoken: { side: Side; text: string; at: number }[] = [];
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

  /** Something a person finished saying. Each speaker's sentences are handled in order. */
  heard(identity: string, name: string, text: string): Promise<void> {
    const next = (this.speakers.get(identity) ?? Promise.resolve()).then(() => this.handle(identity, name, text));
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

  private async handle(identity: string, name: string, heard: string) {
    const text = heard.trim();
    if (!text) return;
    const side = this.sideOf(identity);
    // A side's microphone can pick up the translator speaking to that side. That isn't the person talking.
    if (this.isEcho(side, text)) { this.deps.log?.("ignored an echo of the translator"); return; }
    const listener: Side = side === "bedside" ? "family" : "bedside";
    const target = listener === "bedside" ? this.bedsideLanguage : this.familyLanguage;
    let rendering: Rendering;
    const asked = this.deps.now();
    try {
      rendering = await this.deps.translate(text, side, target, this.recent.slice(-recentLines));
      this.deps.log?.(`translated in ${this.deps.now() - asked} ms`);
    } catch (error) {
      this.deps.log?.("translation failed", error);
      rendering = { say: false, text: "" };
    }
    const said = rendering.say && rendering.text.trim() ? rendering.text.trim() : null;
    const line: Line = { id: `${++this.count}`, speaker: identity, name, side, heard: text, said, language: target, at: this.deps.now() };
    this.recent.push(line);
    if (this.recent.length > recentLines) this.recent.shift();
    // Family see everything heard and said, so they can tell when something was misheard. The bedside sees
    // only what the translator says to it, as it says it.
    this.deps.send({ type: "line", ...line }, "family");
    if (said) this.playing[listener] = this.playing[listener].then(() => this.play(listener, line, said));
  }

  private async play(listener: Side, line: Line, said: string) {
    this.spoken.push({ side: listener, text: said, at: this.deps.now() });
    while (this.spoken.length && this.deps.now() - this.spoken[0].at > echoWindowMs) this.spoken.shift();
    if (listener === "bedside") this.deps.send({ type: "line", ...line }, "bedside");
    this.deps.send({ type: "speaking", on: true }, listener);
    try { await this.deps.speak(listener, said, line.language); }
    catch (error) { this.deps.log?.("speaking failed", error); }
    finally {
      // The echo window runs from when the voice stops, not when it starts.
      const entry = this.spoken.findLast(s => s.text === said);
      if (entry) entry.at = this.deps.now();
      this.deps.send({ type: "speaking", on: false }, listener);
    }
  }

  private isEcho(side: Side, text: string) {
    const now = this.deps.now();
    return this.spoken.some(s => s.side === side && now - s.at <= echoWindowMs && similarity(s.text, text) >= 0.6);
  }
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
