import { createHmac, randomUUID } from "node:crypto";
import { RoomServiceClient, WebhookReceiver, type ParticipantInfo, type WebhookEvent } from "livekit-server-sdk";
import { callJSON, type CallServer } from "../calls/server.ts";
import { callLogEntry, recordCall } from "./call-log.ts";
import { callRoom, config, deliveryUnavailable, expire, finishCall, mutate, phoneDropIn, ringLimits, ringSeconds, type Call, type Household, type InboundPhone } from "./household.ts";
import { blockCall, callerAllowed } from "./screening.ts";
import { familyStore, type FamilyStore } from "./store.ts";
import { sendVoIPPush, voipConfigured, type VoIPRegistration, type IncomingCallPush, type PushResult } from "./push.ts";

export const inboundRoomPrefix = "porch-inbound-";
/** The inbound trunk's ringing cap. Each household's own ring time ends calls sooner. */
export const inboundRingLimitSeconds = ringLimits.maximum;
/** The digest login Twilio's voice webhook uses to reach the LiveKit inbound trunk. It is
 * derived from the LiveKit API secret, so the server and the setup script agree without a new secret. */
export function sipInboundCredentials(apiSecret: string) {
  return { username: "porch", password: createHmac("sha256", apiSecret).update("porch-sip-inbound-v1").digest("base64url") };
}
// The inbound trunk maps Twilio's STIR/SHAKEN result header to this attribute.
// Only full ("A") attestation lets an approved number drop in; anything else rings.
export const callerVerificationHeader = "X-Twilio-VerStat";
export const callerVerificationAttribute = "porch.callerVerification";
// With voicemail routing, the voice webhook copies Twilio's signed StirVerstat result into
// this header instead; the trunk then requires the digest login, so only the server can set it.
export const forwardedVerificationHeader = "X-Porch-VerStat";
export const verifiedCaller = "TN-Validation-Passed-A";
const numberPattern = /^\+[1-9][0-9]{6,14}$/;
// ParticipantInfo.Kind.SIP in the LiveKit protocol (not exported by this SDK).
const sipParticipantKind = 3;
export type InboundRoute = { householdID: string; bedsideID: string; trunkID: string };
type Session = { householdID: string; callID: string; phone: InboundPhone };
export type InboundDependencies = {
  sendPush?: (device: VoIPRegistration, call: IncomingCallPush) => Promise<PushResult>;
  store?: FamilyStore;
  now?: () => number;
  endRoom?: (room: string, configuration: CallServer) => Promise<void>;
  getPhoneParticipant?: (room: string, identity: string, configuration: CallServer) => Promise<ParticipantInfo>;
};

function notFound(error: unknown) {
  return !!error && typeof error === "object" && "code" in error && error.code === "not_found";
}
function rooms(configuration: CallServer) {
  return new RoomServiceClient(configuration.serverUrl.replace(/^wss:/, "https:"), configuration.apiKey, configuration.apiSecret, { requestTimeout: 8 });
}
async function participant(phone: InboundPhone, dependencies: InboundDependencies) {
  const configuration = config();
  try {
    return await (dependencies.getPhoneParticipant
      ? dependencies.getPhoneParticipant(phone.room, phone.participantIdentity, configuration)
      : rooms(configuration).getParticipant(phone.room, phone.participantIdentity));
  } catch (error) { if (notFound(error)) return undefined; throw error; }
}
function matches(phone: InboundPhone, actual?: ParticipantInfo) {
  return actual?.kind === sipParticipantKind && actual.sid === phone.participantSID &&
    actual.attributes["sip.trunkID"] === phone.trunkID && actual.attributes["sip.trunkPhoneNumber"] === phone.calledNumber &&
    actual.attributes["sip.callStatus"] !== "hangup";
}
async function deleteRoom(room: string, dependencies: InboundDependencies) {
  const configuration = config();
  try {
    if (dependencies.endRoom) await dependencies.endRoom(room, configuration);
    else await rooms(configuration).deleteRoom(room);
  } catch (error) { if (!notFound(error)) throw error; }
}
const sessionKey = (roomSID: string) => `inbound-session:${roomSID}`;
const endedKey = (roomSID: string) => `inbound-ended:${roomSID}`;

export async function cleanupInboundCall(store: FamilyStore, householdID: string, call: Call, dependencies: InboundDependencies) {
  if (!call.phone) return;
  // A terminal marker prevents delayed/duplicate join events reopening the call,
  // including when the household has already moved on to a different call.
  await store.create(endedKey(call.phone.roomSID), "1", 86400);
  await deleteRoom(callRoom(call), dependencies);
  await mutate(store, householdID, house => {
    if (house.call?.id === call.id && house.call.phone) house.call.phone.cleanedUp = true;
  });
}

async function endSession(store: FamilyStore, session: Session, reason: string, now: number, dependencies: InboundDependencies) {
  await store.create(endedKey(session.phone.roomSID), "1", 86400);
  const { house } = await mutate(store, session.householdID, house => {
    if (house.call?.id === session.callID && house.call.state !== "ended") finishCall(house.call, reason, now);
  });
  if (house.call?.id === session.callID) await cleanupInboundCall(store, session.householdID, house.call, dependencies);
  else await deleteRoom(session.phone.room, dependencies);
}

// Reconcile missed webhooks during normal signaling. Never interpret an API
// outage as a confirmed hangup, and never require a device heartbeat from SIP.
export async function reconcileInboundCall(store: FamilyStore, householdID: string, now: number, dependencies: InboundDependencies, force = false) {
  const raw = await store.get(`house:${householdID}`);
  if (!raw) return;
  const call: Call | undefined = (JSON.parse(raw) as Household).call;
  if (!call?.phone) return;
  const { house } = await mutate(store, householdID, current => { expire(current, now); });
  if (house.call?.id !== call.id) return;
  if (house.call.state === "ended") {
    if (!house.call.phone?.cleanedUp) await cleanupInboundCall(store, householdID, house.call, dependencies);
    return;
  }
  if (!force && now - (call.phone.checkedAt ?? 0) < 5) return;
  if (!matches(call.phone, await participant(call.phone, dependencies))) {
    await endSession(store, { householdID, callID: call.id, phone: call.phone }, "The phone caller hung up.", now, dependencies);
  } else {
    await mutate(store, householdID, current => {
      if (current.call?.id === call.id && current.call.phone) current.call.phone.checkedAt = now;
    });
  }
}

async function joined(event: WebhookEvent, store: FamilyStore, now: number, dependencies: InboundDependencies) {
  const room = event.room!, caller = event.participant!;
  // Old events must not revive expired calls, even after deduplication keys expire.
  const createdAt = Number(event.createdAt);
  if (!createdAt || createdAt > now + 30 || createdAt + inboundRingLimitSeconds <= now) return;
  const phone: InboundPhone = {
    room: room.name, roomSID: room.sid, participantIdentity: caller.identity, participantSID: caller.sid,
    trunkID: caller.attributes["sip.trunkID"], calledNumber: caller.attributes["sip.trunkPhoneNumber"], checkedAt: now,
    ...(numberPattern.test(caller.attributes["sip.phoneNumber"] ?? "") ? { callerNumber: caller.attributes["sip.phoneNumber"] } : {}),
  };
  if (!phone.trunkID || !numberPattern.test(phone.calledNumber) || !phone.participantIdentity || !phone.participantSID) return;
  if (await store.get(endedKey(room.sid))) { await deleteRoom(room.name, dependencies); return; }
  const rawRoute = await store.get(`phone-number:${phone.calledNumber}`);
  const route: InboundRoute | undefined = rawRoute ? JSON.parse(rawRoute) : undefined;
  if (!route || route.trunkID !== phone.trunkID) { await deleteRoom(room.name, dependencies); return; }
  const actual = await participant(phone, dependencies);
  if (!matches(phone, actual)) {
    await store.create(endedKey(room.sid), "1", 86400);
    await deleteRoom(room.name, dependencies); return;
  }
  // Direct SIP trunking skips the voice webhook, so blocked callers are turned away here too.
  const screened: Household | null = JSON.parse((await store.get(`house:${route.householdID}`)) ?? "null");
  if (screened && !callerAllowed(screened, phone.callerNumber)) {
    await store.create(endedKey(room.sid), "1", 86400);
    try { await blockCall(store, route.householdID, room.sid, phone.callerNumber, now); } catch { /* blocked either way */ }
    await deleteRoom(room.name, dependencies); return;
  }
  // Read from LiveKit's own participant record, never the webhook payload.
  const verified = actual!.attributes[callerVerificationAttribute] === verifiedCaller;
  const proposed: Session = { householdID: route.householdID, callID: randomUUID(), phone };
  await store.create(sessionKey(room.sid), JSON.stringify(proposed), 86400);
  const session: Session = JSON.parse((await store.get(sessionKey(room.sid)))!);
  if (session.householdID !== route.householdID || session.phone.participantSID !== phone.participantSID) {
    await deleteRoom(room.name, dependencies); return;
  }
  // Clear an expired prior phone call before trying to reserve the household.
  await reconcileInboundCall(store, route.householdID, now, dependencies);
  const pushEnabled = !!dependencies.sendPush || voipConfigured();
  // The finished call this one takes the place of, saved to call history once this change is.
  let replaced: Call | undefined;
  const { house, result } = await mutate(store, route.householdID, house => {
    replaced = undefined;
    expire(house, now);
    if (house.call?.id === session.callID) return house.call.state !== "ended";
    const bedside = house.members.find(m => m.id === route.bedsideID && m.role === "bedside" && !m.revoked);
    const ready = !!bedside?.available && bedside.seenAt > now - 30;
    if (!bedside || (!ready && !(bedside.voip && pushEnabled)) || (house.call && house.call.state !== "ended")) return false;
    // Caller ID alone never grants drop-in. Like app drop-ins, it also needs the
    // master switch and a foreground bedside; otherwise the call rings normally.
    const dropIn = ready && verified && house.dropInEnabled && !!phoneDropIn(house, phone.callerNumber);
    const expiresAt = createdAt + ringSeconds(house, dropIn ? "dropIn" : "call");
    if (expiresAt <= now) return false;
    replaced = house.call;
    house.call = { id: session.callID, from: `sip:${phone.participantSID}`, to: bedside.id, mode: "voice", kind: dropIn ? "dropIn" : "call",
      state: "pending", createdAt, expiresAt, phone: session.phone };
    return true;
  });
  const entry = replaced && callLogEntry(house, replaced);
  if (entry) { try { await recordCall(store, house.id, entry, now); } catch { /* history never fails a call */ } }
  if (!result || await store.get(endedKey(room.sid))) {
    await endSession(store, session, "Porch is busy or unavailable.", now, dependencies);
    return;
  }
  const call = house.call!, bedside = house.members.find(m => m.id === call.to)!;
  // Webhook retries and simultaneous copies share one delivery claim. No VoIP
  // push is used for drop-ins, cancellation, accepted calls, or an ended session.
  if (call.kind !== "call" || call.state !== "pending" || !bedside.voip || !pushEnabled ||
      !await store.create(`inbound-push:${room.sid}`, "1", 86400)) return;
  const registration = bedside.voip;
  let delivery: PushResult;
  try {
    delivery = await (dependencies.sendPush ?? sendVoIPPush)(registration, {
      callID: call.id, recipientID: bedside.id, callerName: phone.callerNumber ?? "Phone caller", mode: "voice", expiresAt: call.expiresAt,
    });
  } catch { delivery = { delivered: false }; }
  if (!delivery.delivered) {
    const updated = await mutate(store, house.id, current => {
      const recipient = current.members.find(m => m.id === bedside.id);
      if (delivery.invalidToken && recipient?.voip?.token === registration.token && recipient.voip.environment === registration.environment) delete recipient.voip;
      const active = current.call;
      if (recipient && !(recipient.available && recipient.seenAt > now - 30) && active?.id === call.id && active.state === "pending" && active.receivedAt === undefined) {
        finishCall(active, deliveryUnavailable, now);
        return true;
      }
      return false;
    });
    if (updated.result) await cleanupInboundCall(store, house.id, updated.house.call!, dependencies);
  }
}

export async function handleInboundWebhook(request: Request, dependencies: InboundDependencies = {}) {
  let configuration: CallServer;
  try { configuration = config(); } catch { return callJSON({ error: "Calling is not configured." }, 503); }
  let event: WebhookEvent;
  try {
    const body = await request.text();
    if (body.length > 65536) return callJSON({ error: "Webhook is too large." }, 413);
    event = await new WebhookReceiver(configuration.apiKey, configuration.apiSecret).receive(body, request.headers.get("authorization") ?? undefined);
  } catch { return callJSON({ error: "Invalid LiveKit webhook." }, 401); }
  const room = event.room;
  if (!room?.sid || !room.name.startsWith(inboundRoomPrefix)) return callJSON({ received: true });
  try {
    const store = dependencies.store ?? familyStore();
    const now = dependencies.now?.() ?? Math.floor(Date.now() / 1000);
    if (event.event === "participant_joined" && event.participant?.kind === sipParticipantKind) {
      await joined(event, store, now, dependencies);
    } else if (event.event === "room_finished" || event.event === "participant_left" || event.event === "participant_connection_aborted") {
      const rawSession = await store.get(sessionKey(room.sid));
      const session: Session | undefined = rawSession ? JSON.parse(rawSession) : undefined;
      const relevant = event.event === "room_finished" || event.participant?.kind === sipParticipantKind ||
        (session && event.participant?.identity === (JSON.parse((await store.get(`house:${session.householdID}`)) ?? "null") as Household | null)?.call?.to);
      if (relevant) {
        await store.create(endedKey(room.sid), "1", 86400);
        if (session) await endSession(store, session, "Call ended.", now, dependencies);
      }
    }
    return callJSON({ received: true });
  } catch {
    // Non-2xx asks LiveKit to retry. No credentials, numbers, or payloads in logs.
    return callJSON({ error: "Incoming call processing unavailable." }, 503);
  }
}
