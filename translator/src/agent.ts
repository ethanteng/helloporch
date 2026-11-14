import { fileURLToPath } from "node:url";
import { AutoSubscribe, cli, defineAgent, inference, ServerOptions, stt, type JobContext } from "@livekit/agents";
import { AudioFrame, AudioSource, AudioStream, LocalAudioTrack, ParticipantKind, RoomEvent, TrackKind, TrackPublishOptions, TrackSource,
  type RemoteParticipant, type RemoteTrack, type Room } from "@livekit/rtc-node";
import { Interpreter, type Message, type Side } from "./interpreter.ts";
import { isLanguage, languages, type Language } from "./languages.ts";
import { claudeTranslator } from "./translate.ts";
import { elevenLabsVoice, voiceSampleRate } from "./voice.ts";

// Porch's call translator. The calling server dispatches it into a family call's room when someone turns
// translation on (lib/family/translation.ts) and removes it when they turn it off. It listens to everyone, says
// what one side said in the other side's language on that side's own track, and sends the words to the apps on the
// `porch-translation` topic. Each app unsubscribes from the other side's track itself: LiveKit's server-side
// unsubscribe doesn't stop a participant that joined with auto-subscribe (tried in scripts/call-test.ts). A phone
// guest hears both tracks.
export const agentName = "porch-translator";
export const topics = { lines: "porch-translation", control: "porch-translation-control" } as const;
export const trackNames: Record<Side, string> = { bedside: "porch-translation-bedside", family: "porch-translation-family" };

/** The dispatch's metadata: who the bedside is, its language and voice, and the family's. */
export type JobConfig = { bedside: string; bedsideLanguage: Language; bedsideVoice: string; familyLanguage: Language; familyVoice: string };

export function parseJobConfig(metadata: string): JobConfig {
  const value: unknown = JSON.parse(metadata);
  if (!value || typeof value !== "object") throw new Error("The translator needs its call's details.");
  const v = value as Record<string, unknown>;
  if (typeof v.bedside !== "string" || !v.bedside || !isLanguage(v.bedsideLanguage) || !isLanguage(v.familyLanguage) ||
      typeof v.bedsideVoice !== "string" || typeof v.familyVoice !== "string") throw new Error("The translator's call details are incomplete.");
  return { bedside: v.bedside, bedsideLanguage: v.bedsideLanguage, bedsideVoice: v.bedsideVoice, familyLanguage: v.familyLanguage, familyVoice: v.familyVoice };
}

/** Google's live transcription handled mixed English and Mandarin best (scripts/stt-bench.ts); AssemblyAI is the fallback. */
function recognizer(languagesHeard: Language[]) {
  return new inference.STT({
    model: "google/gemini-3.5-transcribe-live",
    modelOptions: { language_codes: [...new Set(languagesHeard.map(l => languages[l].recognize))] },
    fallback: ["assemblyai/universal-3-6-pro"],
  });
}

const isPerson = (p: RemoteParticipant) => p.kind !== ParticipantKind.AGENT;

export default defineAgent({
  entry: async (ctx: JobContext) => {
    const config = parseJobConfig(ctx.job.metadata);
    const anthropicConfigured = !!process.env.ANTHROPIC_API_KEY;
    const elevenLabsKey = process.env.ELEVENLABS_API_KEY;
    if (!anthropicConfigured || !elevenLabsKey) throw new Error("The translator needs ANTHROPIC_API_KEY and ELEVENLABS_API_KEY.");
    await ctx.connect(undefined, AutoSubscribe.AUDIO_ONLY);
    const room = ctx.room;
    const voices: Record<Side, string> = { bedside: config.bedsideVoice, family: config.familyVoice };

    // One track per side, so each side hears only the translation meant for it.
    const sources = {} as Record<Side, AudioSource>;
    for (const side of ["bedside", "family"] as const) {
      sources[side] = new AudioSource(voiceSampleRate, 1);
      const track = LocalAudioTrack.createAudioTrack(trackNames[side], sources[side]);
      await room.localParticipant!.publishTrack(track, new TrackPublishOptions({ source: TrackSource.SOURCE_MICROPHONE }));
    }
    await room.localParticipant!.setAttributes({ "porch.translator": "1" });

    const send = (message: Message, to: Side | "everyone") => {
      const people = [...room.remoteParticipants.values()].filter(isPerson).map(p => p.identity);
      const destination = to === "everyone" ? undefined : people.filter(id => (id === config.bedside) === (to === "bedside"));
      if (destination && !destination.length) return;
      room.localParticipant!.publishData(new TextEncoder().encode(JSON.stringify(message)),
        { reliable: true, topic: topics.lines, destination_identities: destination }).catch(error => log("couldn't send", error));
    };
    const speak = async (to: Side, text: string, language: Language) => {
      const source = sources[to];
      const frame = voiceSampleRate / 100; // 10 ms
      let pending = new Int16Array(0);
      const asked = Date.now();
      let first = true;
      for await (const chunk of elevenLabsVoice(text, voices[to], language, elevenLabsKey)) {
        if (first) { log(`voice started in ${Date.now() - asked} ms`); first = false; }
        const samples = new Int16Array(pending.length + chunk.length);
        samples.set(pending); samples.set(chunk, pending.length);
        let i = 0;
        for (; i + frame <= samples.length; i += frame) await source.captureFrame(new AudioFrame(samples.slice(i, i + frame), voiceSampleRate, 1, frame));
        pending = samples.slice(i);
      }
      if (pending.length) await source.captureFrame(new AudioFrame(pending, voiceSampleRate, 1, pending.length));
      await source.waitForPlayout();
    };
    const interpreter = new Interpreter(config, { translate: claudeTranslator(), speak, send, now: Date.now, log });

    // Speech recognition for each person on the call, restarted when the bedside's language changes.
    const listeners = new Map<string, () => void>();
    const listen = (participant: RemoteParticipant, track: RemoteTrack) => {
      listeners.get(participant.identity)?.();
      const recognition = recognizer([interpreter.familyLanguage, interpreter.bedsideLanguage]).stream();
      const audio = new AudioStream(track, 16_000, 1).getReader();
      let stopped = false;
      (async () => {
        while (!stopped) {
          const { value, done } = await audio.read();
          if (done) break;
          recognition.pushFrame(value);
        }
      })().catch(error => log("audio stopped", error));
      (async () => {
        for await (const event of recognition) {
          const text = event.type === stt.SpeechEventType.FINAL_TRANSCRIPT ? event.alternatives?.[0]?.text : undefined;
          if (!text?.trim()) continue;
          if (event.speechEndTime) log(`recognized ${Date.now() - event.speechEndTime} ms after speech ended`);
          void interpreter.heard(participant.identity, participant.name || participant.identity, text);
        }
      })().catch(error => log("recognition stopped", error));
      listeners.set(participant.identity, () => {
        stopped = true;
        audio.cancel().catch(() => {});
        try { recognition.close(); } catch { /* already closed */ }
        listeners.delete(participant.identity);
      });
    };
    const listenAgain = () => {
      for (const p of room.remoteParticipants.values()) {
        const track = [...p.trackPublications.values()].find(t => t.kind === TrackKind.KIND_AUDIO && t.track)?.track;
        if (isPerson(p) && track) listen(p, track as RemoteTrack);
      }
    };

    room.on(RoomEvent.TrackSubscribed, (track, _publication, participant) => {
      if (track.kind === TrackKind.KIND_AUDIO && isPerson(participant)) listen(participant, track);
    });
    room.on(RoomEvent.TrackUnsubscribed, (_track, _publication, participant) => listeners.get(participant.identity)?.());
    room.on(RoomEvent.ParticipantDisconnected, participant => {
      listeners.get(participant.identity)?.();
      if (!stillNeeded(room, config.bedside)) ctx.shutdown("the call no longer has both sides");
    });
    // Only the calling server changes the language; data from people on the call carries no sender-less packets.
    room.on(RoomEvent.DataReceived, (payload, participant, _kind, topic) => {
      if (participant || topic !== topics.control) return;
      try {
        const message = JSON.parse(new TextDecoder().decode(payload));
        if (message?.type === "language" && isLanguage(message.language) && typeof message.voice === "string") {
          voices.bedside = message.voice;
          interpreter.setLanguage(message.language);
          listenAgain();
        }
      } catch (error) { log("ignored a control message", error); }
    });
    ctx.addShutdownCallback(async () => {
      send({ type: "state", on: false, language: interpreter.bedsideLanguage }, "everyone");
      for (const stop of [...listeners.values()]) stop();
    });

    listenAgain();
    send({ type: "state", on: true, language: interpreter.bedsideLanguage }, "everyone");
    if (!stillNeeded(room, config.bedside)) ctx.shutdown("the call no longer has both sides");
  },
});

/** Translation needs the bedside and at least one person on the other side. */
function stillNeeded(room: Room, bedside: string) {
  const people = [...room.remoteParticipants.values()].filter(isPerson);
  return people.some(p => p.identity === bedside) && people.some(p => p.identity !== bedside);
}

function log(message: string, detail?: unknown) {
  // Never the words: only what went wrong.
  console.log(`[translator] ${message}${detail instanceof Error ? `: ${detail.message}` : ""}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  cli.runApp(new ServerOptions({ agent: fileURLToPath(import.meta.url), agentName }));
}
