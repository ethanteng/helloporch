import { randomUUID } from "node:crypto";
import { bedsideLanguage, displayName, FamilyError, mutate, requireValue, type Household, type Member } from "./household.ts";
import type { MediaStore } from "./media.ts";
import { discardMedia } from "./messages.ts";
import type { FamilyStore } from "./store.ts";

// Family voices. A caregiver reads aloud for about a minute on their own phone; ElevenLabs makes a voice from it
// (instant voice cloning), and the bedside can then speak announcements in it. Only the person whose voice it is
// can record it, live in the app, after agreeing to its use. The recording is deleted once the voice is made.
// A voice is removed when its caregiver removes it, stops being a caregiver, or leaves the family.
export type FamilyVoice = { id: string; createdAt: number };
/** An uploaded recording waiting to become a voice. It is deleted when the voice is made, or once it expires. */
export type PendingVoice = { pathname: string; expiresAt: number };
export type VoiceService = {
  /** How many made voices the account holds, and may hold. */
  slots(): Promise<{ used: number; limit: number }>;
  /** Makes a voice from the recording at this short-lived link, and returns its ID. */
  add(name: string, recordingURL: string): Promise<string>;
  /** Deletes a voice. A voice that is already gone counts as deleted. */
  remove(voiceID: string): Promise<void>;
};
export type VoiceContext = { store: FamilyStore; media: () => MediaStore; now: number; house: Household; me: Member; input: Record<string, unknown>; voices?: VoiceService };

// ElevenLabs allows the whole account a few dozen new voices a month, so one family can make only a few a day.
export const voiceLimits = { recordingBytes: 5_000_000, minSeconds: 20, maxSeconds: 180, uploadSeconds: 1800, downloadSeconds: 300, madePerDay: 3 };
export const voiceActions = new Set(["voiceUpload", "createVoice", "removeVoice"]);
// ElevenLabs voice IDs.
export const voiceIDPattern = /^[A-Za-z0-9]{16,40}$/;
const unavailable = "Recording a voice isn't available right now.";

/** Caregivers' recorded voices, in the order they were made. A voice belongs to its caregiver while they stay one. */
export function familyVoices(house: Household) {
  return house.members.filter(m => m.voice && m.role === "family" && m.caregiver && !m.revoked)
    .sort((a, b) => a.voice!.createdAt - b.voice!.createdAt)
    .map(m => ({ id: m.voice!.id, name: displayName(m), detail: "Family voice", family: true, memberID: m.id }));
}
export function isFamilyVoice(house: Household, voiceID: unknown) {
  return typeof voiceID === "string" && familyVoices(house).some(v => v.id === voiceID);
}
/** Where announcements in a family voice are kept, so they're deleted with it. */
export function familyVoiceFolder(voiceID: string) { return `voices/${voiceID}`; }

/** Takes a member's voice out of use. It's deleted from ElevenLabs, with its announcements, by `cleanUpVoices`. */
export function retireVoice(house: Household, member: Member, replacement?: string) {
  const voiceID = member.voice?.id;
  delete member.voice;
  if (!voiceID) return;
  for (const [language, choice] of Object.entries(house.speechVoices ?? {})) {
    if (choice !== voiceID) continue;
    if (replacement) house.speechVoices![language] = replacement; else delete house.speechVoices![language];
  }
  house.retiredVoices = [...new Set([...house.retiredVoices ?? [], voiceID])];
}
/** Retires a member's voice and returns their unsaved recording, as they leave or stop being a caregiver. */
export function dropVoice(house: Household, member: Member): string[] {
  retireVoice(house, member);
  const pending = member.pendingVoice?.pathname;
  delete member.pendingVoice;
  return pending ? [pending] : [];
}

/** Deletes retired voices and their announcements. A failure is retried on the bedside's next poll. */
export async function cleanUpVoices(store: FamilyStore, media: () => MediaStore, house: Household, voices: VoiceService) {
  const done: string[] = [];
  for (const voiceID of house.retiredVoices ?? []) {
    try {
      await voices.remove(voiceID);
      await media().removeFolder(`speech/${house.id}/${familyVoiceFolder(voiceID)}/`);
      done.push(voiceID);
    } catch { /* the next poll tries again */ }
  }
  if (!done.length) return;
  await mutate(store, house.id, latest => {
    const left = (latest.retiredVoices ?? []).filter(v => !done.includes(v));
    if (left.length) latest.retiredVoices = left; else delete latest.retiredVoices;
  });
}
/** Recordings that were never made into a voice, and voices still to delete. Runs on bedside polls. */
export async function maintainVoices(store: FamilyStore, media: () => MediaStore, house: Household, now: number, voices: () => VoiceService) {
  if (house.members.some(m => m.pendingVoice && m.pendingVoice.expiresAt <= now)) {
    const { result: stale } = await mutate(store, house.id, latest => latest.members.flatMap(m => {
      if (!m.pendingVoice || m.pendingVoice.expiresAt > now) return [];
      const { pathname } = m.pendingVoice; delete m.pendingVoice; return [pathname];
    }));
    await discardMedia(store, media, house.id, stale, now);
  }
  if (house.retiredVoices?.length) await cleanUpVoices(store, media, house, voices());
}

export async function handleVoiceAction(action: string, { store, media, now, house, me, input, voices }: VoiceContext): Promise<object> {
  // Caregiver actions, PIN-checked before this point. Each person records only their own voice, on their own phone.
  requireValue(me.role === "family" && me.caregiver, "Only a caregiver can record their voice.", 403);
  const service = () => voices ?? elevenLabsVoices();
  const caregiver = (latest: Household) => {
    const member = latest.members.find(m => m.id === me.id && m.role === "family" && m.caregiver && !m.revoked);
    requireValue(member, "Only a caregiver can record their voice.", 403);
    return member;
  };
  if (action === "removeVoice") {
    const { house: latest } = await mutate(store, house.id, latest => { retireVoice(latest, caregiver(latest)); });
    await cleanUpVoices(store, media, latest, service());
    return {};
  }
  if (action === "voiceUpload") {
    requireValue(voices || process.env.ELEVENLABS_API_KEY, unavailable, 503);
    const size = input.sizeBytes, seconds = input.durationSeconds;
    requireValue(input.contentType === "audio/mp4", "Record your voice again.");
    requireValue(typeof size === "number" && Number.isInteger(size) && size > 0, "Record your voice again.");
    requireValue(size <= voiceLimits.recordingBytes, "Record for up to three minutes.", 413);
    requireValue(typeof seconds === "number" && Number.isFinite(seconds) && seconds <= voiceLimits.maxSeconds, "Record for up to three minutes.");
    requireValue(seconds >= voiceLimits.minSeconds, "Read for at least 20 seconds.");
    // Checked before the upload, so a full account says so before anything is sent.
    const { used, limit } = await service().slots();
    requireValue(used < limit, "Recorded voices are full for now.", 503);
    const pathname = `voices/${house.id}/${me.id}/${randomUUID()}.m4a`;
    const { result: stale } = await mutate(store, house.id, latest => {
      const member = caregiver(latest);
      const previous = member.pendingVoice?.pathname;
      member.pendingVoice = { pathname, expiresAt: now + voiceLimits.uploadSeconds };
      return previous ? [previous] : [];
    });
    try { await discardMedia(store, media, house.id, stale, now); } catch { /* the purge pass retries */ }
    return { upload: await media().uploadTarget(pathname, "audio/mp4", size, now + voiceLimits.uploadSeconds), pathname };
  }
  // createVoice: the uploaded recording becomes this caregiver's voice, and the bedside's voice in its language.
  requireValue(input.consent === true, "Confirm that this is your voice.");
  const pathname = input.pathname;
  requireValue(typeof pathname === "string" && me.pendingVoice?.pathname === pathname && me.pendingVoice.expiresAt > now, "Record your voice again.", 409);
  let voiceID: string;
  try {
    // Counted before asking, so failing requests can't use up the account's allowance either.
    const day = Math.floor(now / 86400);
    await mutate(store, house.id, latest => {
      const made = latest.voiceUsage?.day === day ? latest.voiceUsage.made : 0;
      // Not 429: on a caregiver's phone, that ends caregiver mode as too many PIN tries.
      requireValue(made < voiceLimits.madePerDay, "You can record again tomorrow.", 409);
      latest.voiceUsage = { day, made: made + 1 };
    });
    const uploaded = await media().stat(pathname);
    requireValue(uploaded && uploaded.contentType === "audio/mp4" && uploaded.size <= voiceLimits.recordingBytes, "The recording didn't upload. Try again.", 409);
    // ElevenLabs sees two IDs, never a name.
    voiceID = await service().add(`Porch ${house.id.slice(0, 8)} ${me.id.slice(0, 8)}`, await media().downloadURL(pathname, now + voiceLimits.downloadSeconds));
  } finally {
    // The recording is only for making the voice. It isn't kept, whatever happened.
    try {
      await mutate(store, house.id, latest => {
        const member = latest.members.find(m => m.id === me.id);
        if (member?.pendingVoice?.pathname === pathname) delete member.pendingVoice;
      });
    } catch { /* it expires */ }
    try { await discardMedia(store, media, house.id, [pathname], now); } catch { /* the purge pass retries */ }
  }
  const { house: latest, result: kept } = await mutate(store, house.id, latest => {
    const member = latest.members.find(m => m.id === me.id && m.role === "family" && m.caregiver && !m.revoked);
    // Their access changed while the voice was being made: it's deleted, not kept.
    if (!member) { latest.retiredVoices = [...new Set([...latest.retiredVoices ?? [], voiceID])]; return false; }
    // A new recording replaces their voice wherever it was chosen.
    retireVoice(latest, member, voiceID);
    member.voice = { id: voiceID, createdAt: now };
    latest.speechVoices = { ...latest.speechVoices, [bedsideLanguage(latest)]: voiceID };
    return true;
  });
  await cleanUpVoices(store, media, latest, service());
  requireValue(kept, "Only a caregiver can record their voice.", 403);
  return { voiceID };
}

const api = "https://api.elevenlabs.io/v1";
type ElevenLabsError = { detail?: { status?: string; code?: string } };
/** ElevenLabs' voice cloning. Errors can quote what was sent, so they aren't logged. */
export function elevenLabsVoices(): VoiceService {
  const key = process.env.ELEVENLABS_API_KEY;
  requireValue(key, unavailable, 503);
  const call = async (path: string, init: RequestInit = {}, seconds = 15) => {
    try { return await fetch(`${api}${path}`, { ...init, headers: { "xi-api-key": key, ...init.headers }, signal: AbortSignal.timeout(seconds * 1000) }); }
    catch { throw new FamilyError(unavailable, 503); }
  };
  const detail = async (response: Response) => { try { return ((await response.json()) as ElevenLabsError).detail ?? {}; } catch { return {}; } };
  return {
    async slots() {
      const response = await call("/user/subscription");
      if (!response.ok) throw new FamilyError(unavailable, 503);
      const plan = await response.json() as { voice_slots_used?: number; voice_limit?: number; can_use_instant_voice_cloning?: boolean };
      return { used: plan.voice_slots_used ?? 0, limit: plan.can_use_instant_voice_cloning === false ? 0 : plan.voice_limit ?? 0 };
    },
    async add(name, recordingURL) {
      let recording: Response;
      try { recording = await fetch(recordingURL, { signal: AbortSignal.timeout(10_000) }); }
      catch { throw new FamilyError("The recording didn't upload. Try again.", 409); }
      if (!recording.ok) throw new FamilyError("The recording didn't upload. Try again.", 409);
      const form = new FormData();
      form.append("name", name);
      form.append("files", new Blob([await recording.arrayBuffer()], { type: "audio/mp4" }), "recording.m4a");
      form.append("remove_background_noise", "true");
      form.append("description", "A Porch family voice");
      // With the fetch above, well inside the family route's minute (maxDuration), which phones wait out.
      const response = await call("/voices/add", { method: "POST", body: form }, 40);
      if (!response.ok) {
        const { status, code } = await detail(response);
        if (code === "invalid_audio" || status === "invalid_content") throw new FamilyError("That recording didn't work. Record again somewhere quiet.", 422);
        if (`${status} ${code}`.includes("voice_limit")) throw new FamilyError("Recorded voices are full for now.", 503);
        throw new FamilyError(unavailable, 503);
      }
      const { voice_id: voiceID } = await response.json() as { voice_id?: unknown };
      if (typeof voiceID !== "string" || !voiceIDPattern.test(voiceID)) throw new FamilyError(unavailable, 503);
      return voiceID;
    },
    async remove(voiceID) {
      const response = await call(`/voices/${encodeURIComponent(voiceID)}`, { method: "DELETE" });
      if (response.ok || response.status === 404) return;
      const { status, code } = await detail(response);
      if (status === "voice_does_not_exist" || code === "voice_not_found") return;
      throw new FamilyError(unavailable, 503);
    },
  };
}
