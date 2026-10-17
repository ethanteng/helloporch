import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { forwardedVerificationHeader, inboundRingSeconds, sipInboundCredentials, verifiedCaller, type InboundRoute } from "./inbound.ts";
import type { Household } from "./household.ts";
import { blobMediaStore, type MediaStore } from "./media.ts";
import { messageLimits, receivePhoneVoicemail, voicemailOpen } from "./messages.ts";
import { familyStore, type FamilyStore } from "./store.ts";

// Regular phone calls reach Porch through a Twilio voice webhook: Twilio dials LiveKit,
// and when the bedside doesn't answer (or is busy or offline) Twilio plays a greeting,
// records the caller and tells this server, which stores the recording as a held voicemail.
export type VoicemailStep = "incoming" | "dialed" | "recorded" | "recording";
export type TwilioRecordings = { download(recordingSID: string): Promise<Uint8Array>; remove(recordingSID: string): Promise<void> };
export type VoicemailDependencies = { store?: FamilyStore; media?: MediaStore; now?: () => number; recordings?: TwilioRecordings };

const numberPattern = /^\+[1-9][0-9]{6,14}$/;
const callSIDPattern = /^CA[0-9a-f]{32}$/;
const recordingSIDPattern = /^RE[0-9a-f]{32}$/;
// Twilio's stand-ins for withheld, restricted and unavailable caller ID.
const withheld = new Set(["+266696687", "+7378742833", "+2562533", "+8656696", "+86282452253"]);
const sessionKey = (callSID: string) => `voicemail-call:${callSID}`;
const verifiedKey = (callSID: string) => `voicemail-verified:${callSID}`;
type Session = { householdID: string; callerNumber?: string; callerVerified?: boolean };

const escape = (value: string) => value.replace(/[<>&"']/g, c => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&apos;" })[c]!);
const twiml = (body: string, status = 200) =>
  new Response(`<?xml version="1.0" encoding="UTF-8"?><Response>${body}</Response>`, { status, headers: { "Content-Type": "text/xml", "Cache-Control": "no-store" } });
const say = (text: string) => `<Say language="en-US">${escape(text)}</Say>`;

function settings() {
  const { TWILIO_ACCOUNT_SID: accountSID, TWILIO_AUTH_TOKEN: authToken, LIVEKIT_SIP_URI: sipURI, LIVEKIT_API_SECRET: apiSecret } = process.env;
  if (!accountSID || !/^AC[0-9a-f]{32}$/.test(accountSID) || !authToken) return undefined;
  const sipHost = sipURI?.trim().replace(/^sip:/, "").replace(/;.*$/, "");
  return { accountSID, authToken, sipHost: sipHost && apiSecret && /^[a-z0-9.-]+$/i.test(sipHost) ? sipHost : undefined, sip: apiSecret ? sipInboundCredentials(apiSecret) : undefined };
}

// https://www.twilio.com/docs/usage/security#validating-requests
function signed(url: string, params: URLSearchParams, token: string, supplied: string | null) {
  if (!supplied) return false;
  const actual = Buffer.from(supplied, "base64");
  const payload = [...params.entries()].sort(([a, x], [b, y]) => a < b ? -1 : a > b ? 1 : x < y ? -1 : x > y ? 1 : 0).map(([k, v]) => k + v).join("");
  // Twilio may sign with or without the default port.
  const parsed = new URL(url), variants = new Set([url]);
  if (!parsed.port) { parsed.port = "443"; variants.add(parsed.toString()); }
  return [...variants].some(candidate => {
    const expected = createHmac("sha1", token).update(candidate + payload, "utf8").digest();
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  });
}

function twilioRecordings(accountSID: string, authToken: string): TwilioRecordings {
  const base = `https://api.twilio.com/2010-04-01/Accounts/${accountSID}/Recordings`;
  const authorization = `Basic ${Buffer.from(`${accountSID}:${authToken}`).toString("base64")}`;
  return {
    async download(recordingSID) {
      const response = await fetch(`${base}/${recordingSID}.mp3`, { headers: { authorization }, signal: AbortSignal.timeout(20_000) });
      if (!response.ok) throw new Error(`Recording download failed (${response.status}).`);
      if (Number(response.headers.get("content-length") ?? 0) > messageLimits.audioBytes) throw new Error("Recording is too large.");
      return new Uint8Array(await response.arrayBuffer());
    },
    async remove(recordingSID) {
      const response = await fetch(`${base}/${recordingSID}.json`, { method: "DELETE", headers: { authorization }, signal: AbortSignal.timeout(10_000) });
      if (!response.ok && response.status !== 404) throw new Error(`Recording delete failed (${response.status}).`);
    },
  };
}

// The same recording always becomes the same message, so a repeated callback is harmless.
export function voicemailMessageID(recordingSID: string) {
  const h = createHash("sha256").update(`porch-voicemail.${recordingSID}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-${"89ab"[parseInt(h[16], 16) & 3]}${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

async function household(store: FamilyStore, calledNumber: string | null): Promise<Household | undefined> {
  if (!calledNumber || !numberPattern.test(calledNumber)) return undefined;
  const route = await store.get(`phone-number:${calledNumber}`);
  if (!route) return undefined;
  const raw = await store.get(`house:${(JSON.parse(route) as InboundRoute).householdID}`);
  return raw ? JSON.parse(raw) : undefined;
}

export async function handleTwilioVoice(request: Request, step: VoicemailStep, dependencies: VoicemailDependencies = {}) {
  const configured = settings();
  // Without the account's auth token, requests can't be verified as Twilio's.
  if (!configured) return new Response("Phone voicemail isn't configured on this server.", { status: 503 });
  const body = await request.text();
  if (body.length > 16384) return new Response("Request too large.", { status: 413 });
  const params = new URLSearchParams(body);
  if (!signed(request.url, params, configured.authToken, request.headers.get("x-twilio-signature")) || params.get("AccountSid") !== configured.accountSID) {
    return new Response("Invalid Twilio signature.", { status: 403 });
  }
  const origin = new URL(request.url).origin;
  const store = dependencies.store ?? familyStore();
  const now = dependencies.now?.() ?? Math.floor(Date.now() / 1000);
  const callSID = params.get("CallSid") ?? "";
  const from = params.get("From") ?? "";
  const callerNumber = numberPattern.test(from) && !withheld.has(from) ? from : undefined;
  try {
    if (step === "incoming") {
      const calledNumber = params.get("To");
      if (!configured.sipHost || !configured.sip || !await household(store, calledNumber)) return twiml("<Reject/>");
      // LiveKit keeps this leg ringing until the bedside answers; answerOnBridge lets the caller hear it.
      // Twilio's signed STIR/SHAKEN result travels on as a SIP header, so phone drop-in still works.
      const verification = params.get("StirVerstat");
      // Remembered for voicemail: only a verified caller on the keypad skips caregiver review.
      if (verification === verifiedCaller && callSIDPattern.test(callSID)) await store.create(verifiedKey(callSID), "1", 3600);
      const headers = verification && /^[A-Za-z0-9-]{1,64}$/.test(verification) ? `?${forwardedVerificationHeader}=${verification}` : "";
      return twiml(`<Dial answerOnBridge="true" timeout="${inboundRingSeconds + 10}" action="${escape(`${origin}/api/calls/inbound/voice/dialed`)}" method="POST">` +
        `<Sip username="${escape(configured.sip.username)}" password="${escape(configured.sip.password)}">${escape(`sip:${calledNumber}@${configured.sipHost};transport=tcp${headers}`)}</Sip></Dial>`);
    }
    if (step === "dialed") {
      const status = params.get("DialCallStatus");
      if (status === "completed" || status === "answered") return twiml("<Hangup/>");
      const house = await household(store, params.get("To"));
      const storage = !!dependencies.media || !!process.env.BLOB_READ_WRITE_TOKEN;
      if (!house || !storage || !callSIDPattern.test(callSID) || !voicemailOpen(house, callerNumber, now)) return twiml(`${say("Sorry, no one can answer right now. Please try again later. Goodbye.")}<Hangup/>`);
      const verified = params.get("StirVerstat") === verifiedCaller || !!await store.get(verifiedKey(callSID));
      const session: Session = { householdID: house.id, ...(callerNumber ? { callerNumber } : {}), ...(callerNumber && verified ? { callerVerified: true } : {}) };
      await store.create(sessionKey(callSID), JSON.stringify(session), 3600);
      return twiml(`${say("Sorry, no one can come to the phone right now. Please leave a message after the tone, then hang up.")}` +
        `<Record maxLength="120" timeout="5" playBeep="true" trim="trim-silence" finishOnKey="#" method="POST"` +
        ` action="${escape(`${origin}/api/calls/inbound/voice/recorded`)}"` +
        ` recordingStatusCallback="${escape(`${origin}/api/calls/inbound/voice/recording`)}" recordingStatusCallbackMethod="POST" recordingStatusCallbackEvent="completed absent"/>` +
        `${say("No message was recorded. Goodbye.")}<Hangup/>`);
    }
    if (step === "recorded") return twiml(`${say("Thank you. Goodbye.")}<Hangup/>`);
    // step === "recording": Twilio's recording status callback.
    const recordingSID = params.get("RecordingSid") ?? "";
    if (!recordingSIDPattern.test(recordingSID) || !callSIDPattern.test(callSID)) return twiml("", 400);
    const recordings = dependencies.recordings ?? twilioRecordings(configured.accountSID, configured.authToken);
    const raw = await store.get(sessionKey(callSID));
    const duration = Number(params.get("RecordingDuration"));
    if (raw && params.get("RecordingStatus") === "completed" && duration >= 1) {
      const session: Session = JSON.parse(raw);
      const audio = await recordings.download(recordingSID);
      await receivePhoneVoicemail(store, dependencies.media ?? blobMediaStore(), session.householdID,
        { id: voicemailMessageID(recordingSID), callerNumber: session.callerNumber, callerVerified: session.callerVerified, audio, durationSeconds: duration }, now);
    }
    // Porch keeps its own copy; nothing stays with the phone provider.
    await recordings.remove(recordingSID);
    return twiml("");
  } catch {
    // A failed recording stays at Twilio so it isn't lost. No numbers or payloads in logs.
    return twiml(step === "recording" ? "" : `${say("Sorry, something went wrong. Please try again later.")}<Hangup/>`, step === "recording" ? 500 : 200);
  }
}
