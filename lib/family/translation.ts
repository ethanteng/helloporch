import { AgentDispatchClient, DataPacket_Kind, RoomServiceClient } from "livekit-server-sdk";
import { bedsideLanguage, callRoom, FamilyError, isBedsideLanguage, mutate, presentMembers, requireValue, type BedsideLanguage, type Call,
  type Household, type Member } from "./household.ts";
import { speechCatalog, speechVoice } from "./speech.ts";
import type { FamilyStore } from "./store.ts";

// Live translation on a Porch call with the bedside. The family member on the call turns it on when they can't get
// something across, and off again; every call starts with it off. Turning it on dispatches the translator
// (translator/ in this repository, a LiveKit agent) into the call's room. It says what each side says in the other
// side's language, unless it's already in it, and the bedside shows the words it says.
export const translationActions = new Set(["setCallTranslation"]);
/** Bedside apps that can show captions and keep the translator out of the call's people say so when they check in. */
export const translationFeature = "translation";
/** The family side hears English for now. The bedside's side follows its language, or the language chosen on the call. */
export const familyLanguage: BedsideLanguage = "en";
export const translatorTopics = { control: "porch-translation-control" } as const;

/** What the call's two ends see: whether translation is on, into which language, and who last changed it. */
export type CallTranslation = { on: boolean; language: BedsideLanguage; by: string; at: number };
export type TranslationServices = {
  /** Brings the translator into the room with what it needs to know (translator/src/agent.ts, `JobConfig`). */
  start: (room: string, metadata: string) => Promise<void>;
  /** Tells a translator already in the room about a new language. */
  configure: (room: string, message: { type: "language"; language: BedsideLanguage; voice: string }) => Promise<void>;
  /** Takes the translator out of the room. */
  stop: (room: string) => Promise<void>;
};
export type TranslationContext = { store: FamilyStore; now: number; house: Household; me: Member; input: Record<string, unknown>; services: TranslationServices };

/** The translator's LiveKit agent name. Translation is offered only once it's set, so the server can ship first. */
export function translatorName() { return process.env.LIVEKIT_TRANSLATOR_AGENT || undefined; }

export function translationServices(config: { apiKey: string; apiSecret: string; serverUrl: string }): TranslationServices {
  const host = config.serverUrl.replace(/^wss:/, "https:");
  const rooms = new RoomServiceClient(host, config.apiKey, config.apiSecret, { requestTimeout: 8 });
  const dispatch = new AgentDispatchClient(host, config.apiKey, config.apiSecret);
  const name = () => translatorName() ?? "porch-translator";
  return {
    start: async (room, metadata) => { await dispatch.createDispatch(room, name(), { metadata }); },
    configure: async (room, message) => {
      // The translator acts only on messages from the server, which carry no sender.
      await rooms.sendData(room, new TextEncoder().encode(JSON.stringify(message)), DataPacket_Kind.RELIABLE, { topic: translatorTopics.control });
    },
    stop: async room => {
      for (const d of await dispatch.listDispatch(room)) if (d.agentName === name()) await dispatch.deleteDispatch(d.id, room);
      for (const p of await rooms.listParticipants(room)) if (p.attributes?.["porch.translator"] === "1") await rooms.removeParticipant(room, p.identity);
    },
  };
}

function bedsideOf(house: Household, call: Call) {
  return house.members.find(m => m.role === "bedside" && !m.revoked && [call.from, call.to].includes(m.id));
}
/** The household's natural voice for a language, or its default when the family chose the iPad's built-in voice for announcements. */
function voiceFor(house: Household, language: BedsideLanguage) {
  return speechVoice(house, language) ?? speechCatalog[language].voices[0].id;
}

/** Whether `me` can turn translation on for this call: one of its two ends, with the bedside on an app that supports it. */
export function translationOffered(house: Household, call: Call, me: Member) {
  const bedside = bedsideOf(house, call);
  return !!translatorName() && call.state === "accepted" && !call.phone && me.role === "family" && [call.from, call.to].includes(me.id) &&
    !!bedside?.features?.includes(translationFeature);
}

export async function handleTranslationAction(_action: string, { store, now, house, me, input, services }: TranslationContext) {
  const call = house.call;
  requireValue(call && call.id === input.callID && call.state === "accepted", "Translation works only while the call is on.", 409);
  requireValue(typeof input.on === "boolean", "Say whether translation should be on.");
  requireValue(me.role === "family" && [call.from, call.to].includes(me.id) && presentMembers(call).includes(me.id),
    "Only the person on this call with the bedside can turn translation on or off.", 403);
  requireValue(translationOffered(house, call, me), "Translation isn't available on this call. Update Porch on the bedside first.", 409);
  const bedside = bedsideOf(house, call)!;
  const current = call.translation;
  const language = input.language === undefined ? (current?.language ?? bedsideLanguage(house)) : input.language;
  requireValue(isBedsideLanguage(language), "Choose one of the bedside's languages.");
  const room = callRoom(call);
  try {
    if (input.on && !current?.on) {
      await services.start(room, JSON.stringify({ bedside: bedside.id, bedsideLanguage: language, bedsideVoice: voiceFor(house, language),
        familyLanguage, familyVoice: voiceFor(house, familyLanguage) }));
    } else if (input.on && current?.language !== language) {
      await services.configure(room, { type: "language", language, voice: voiceFor(house, language) });
    } else if (!input.on && current?.on) {
      await services.stop(room);
    }
  } catch {
    throw new FamilyError(input.on ? "Translation couldn't start. Try again in a moment." : "Translation couldn't be turned off. Try again in a moment.", 502);
  }
  const translation: CallTranslation = { on: input.on, language, by: me.id, at: now };
  await mutate(store, house.id, latest => {
    if (latest.call?.id === call.id && latest.call.state === "accepted") latest.call.translation = translation;
  });
  return { translation };
}
