import { authorizeNativeOrBedside } from "../family/auth-calls.ts";
import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { AccessToken, RoomConfiguration, RoomServiceClient, SipClient, TrackSource } from "livekit-server-sdk";
import { authorizeCalls, callInput, callJSON, type CallServer } from "./server.ts";
import { verifyContactApproval } from "./contacts.ts";

const numberPattern = /^\+[1-9][0-9]{6,14}$/;
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const phoneIdentity = "phone";
const dialMarker = "porch.phoneDialStarted";
// Concurrent duplicate requests in one process are rejected. A participant
// attribute also blocks sequential replays across server instances. Never retry
// a dial request automatically; a new user attempt must prepare a new session.
const dialing = new Set<string>();

type Ticket = { id: string; phoneNumber: string; name: string; startBy: number; exp: number; contactAuthorization?: string; localRingback?: boolean };
type PhoneServices = {
  rooms: Pick<RoomServiceClient, "getParticipant" | "updateParticipant" | "deleteRoom">;
  sip: Pick<SipClient, "createSipParticipant">;
};
type Dependencies = { services?: (config: CallServer) => PhoneServices; now?: () => number };
type Action = "prepare" | "start" | "end";

function services(config: CallServer): PhoneServices {
  const host = config.serverUrl.replace(/^wss:/, "https:");
  return {
    rooms: new RoomServiceClient(host, config.apiKey, config.apiSecret, { requestTimeout: 8 }),
    sip: new SipClient(host, config.apiKey, config.apiSecret, { requestTimeout: 10, failover: false }),
  };
}

function signature(value: string, secret: string) {
  return createHmac("sha256", secret).update(`porch-phone-v1.${value}`).digest();
}

function encodeTicket(ticket: Ticket, secret: string) {
  const body = Buffer.from(JSON.stringify(ticket)).toString("base64url");
  return `${body}.${signature(body, secret).toString("base64url")}`;
}

function decodeTicket(value: unknown, secret: string, now: number): Ticket | undefined {
  if (typeof value !== "string" || value.length > 1800) return;
  const [body, supplied, extra] = value.split(".");
  if (!body || !supplied || extra !== undefined) return;
  const expected = signature(body, secret);
  const actual = Buffer.from(supplied, "base64url");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return;
  try {
    const ticket: Ticket = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
    if (typeof ticket.id !== "string" || !idPattern.test(ticket.id) ||
        typeof ticket.phoneNumber !== "string" || !numberPattern.test(ticket.phoneNumber) ||
        typeof ticket.name !== "string" || !ticket.name.trim() || ticket.name.length > 80 ||
        !Number.isInteger(ticket.startBy) || !Number.isInteger(ticket.exp) || ticket.exp <= now) return;
    return ticket;
  } catch { return; }
}

function notFound(error: unknown) {
  return !!error && typeof error === "object" && "code" in error && error.code === "not_found";
}

async function hangUp(rooms: PhoneServices["rooms"], room: string) {
  try { await rooms.deleteRoom(room); } catch (error) { if (!notFound(error)) throw error; }
}

function approvedNumbers(): string[] | undefined {
  const numbers = (process.env.PORCH_PHONE_NUMBERS ?? "").split(",").map((number) => number.trim()).filter(Boolean);
  return numbers.length && numbers.every((number) => numberPattern.test(number)) ? numbers : undefined;
}

export async function handlePhoneCall(request: Request, action: Action, dependencies: Dependencies = {}) {
  const config = await authorizeNativeOrBedside(request);
  if (config instanceof Response) return config;
  const input = await callInput(request);
  if (input instanceof Response) return input;
  const now = dependencies.now?.() ?? Math.floor(Date.now() / 1000);

  if (action === "prepare") {
    const { phoneNumber, name, contactAuthorization, localRingback } = input;
    if (typeof phoneNumber !== "string" || !numberPattern.test(phoneNumber) ||
        typeof name !== "string" || !name.trim() || name.trim().length > 80 ||
        (localRingback !== undefined && typeof localRingback !== "boolean")) {
      return callJSON({ error: "Enter a phone number with + and the country code, and the person's name." }, 400);
    }
    const numbers = approvedNumbers();
    if (!process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID || (contactAuthorization === undefined && !numbers)) {
      return callJSON({ error: "Phone fallback needs an outbound trunk and an approved contact. Ask a caregiver to check setup and save the contact in the updated Porch app." }, 503);
    }
    if (contactAuthorization !== undefined) {
      if (!verifyContactApproval(contactAuthorization, phoneNumber, new URL(request.url).origin, config, now)) {
        return callJSON({ error: "This contact's phone approval is invalid or expired. Ask a caregiver to save the contact again." }, 403);
      }
    } else if (!numbers?.includes(phoneNumber)) {
      return callJSON({ error: "A caregiver needs to save and approve this phone contact in Porch." }, 403);
    }
    const ticket: Ticket = { id: randomUUID(), phoneNumber, name: name.trim(), startBy: now + 120, exp: now + 1200,
      ...(localRingback === true ? { localRingback: true } : {}),
      ...(typeof contactAuthorization === "string" ? { contactAuthorization } : {}) };
    const room = `porch-phone-${ticket.id}`;
    const token = new AccessToken(config.apiKey, config.apiSecret, { identity: `porch-${ticket.id}`, name: "Porch iPad", ttl: "2m" });
    token.roomConfig = new RoomConfiguration({ maxParticipants: 2, emptyTimeout: 90, departureTimeout: 5 });
    token.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true, canPublishData: false,
      canUpdateOwnMetadata: false, canPublishSources: [TrackSource.MICROPHONE] });
    return callJSON({ token: await token.toJwt(), serverUrl: config.serverUrl, room, controlToken: encodeTicket(ticket, config.apiSecret) });
  }

  const ticket = decodeTicket(input.controlToken, config.apiSecret, now);
  if (!ticket) return callJSON({ error: "This phone call session is invalid or expired." }, 401);
  const room = `porch-phone-${ticket.id}`;
  const identity = `porch-${ticket.id}`;
  const client = (dependencies.services ?? services)(config);
  if (action === "end") {
    // Cleanup stays available even if the trunk or allowlist has been disabled.
    try { await hangUp(client.rooms, room); return callJSON({ ended: true }); }
    catch { return callJSON({ error: "Couldn't confirm the phone call ended. Check your connection and try End call again." }, 502); }
  }

  const trunk = process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID;
  if (ticket.startBy <= now) return callJSON({ error: "This phone call attempt expired. Start a new call from Porch." }, 410);
  const approved = ticket.contactAuthorization !== undefined
    ? verifyContactApproval(ticket.contactAuthorization, ticket.phoneNumber, new URL(request.url).origin, config, now)
    : approvedNumbers()?.includes(ticket.phoneNumber);
  if (!trunk || !approved) return callJSON({ error: "Phone fallback is disabled or this number is no longer approved." }, 403);
  if (dialing.has(room)) return callJSON({ error: "This phone call is already starting." }, 409);
  dialing.add(room);
  try {
    // Don't ring anybody until the iPad has actually joined the audio room.
    const caller = await client.rooms.getParticipant(room, identity);
    if (caller.attributes[dialMarker]) return callJSON({ error: "This phone call was already started. End it before starting another." }, 409);
    await client.rooms.updateParticipant(room, identity, { attributes: { [dialMarker]: "true" } });
    await client.sip.createSipParticipant(trunk, ticket.phoneNumber, room, {
      participantIdentity: phoneIdentity, participantName: ticket.name,
      // Updated iPads play local ringback immediately; older builds retain SIP ringback.
      hidePhoneNumber: true, playDialtone: ticket.localRingback !== true, waitUntilAnswered: false,
      ringingTimeout: 45, maxCallDuration: 900, timeout: 10,
    });
    // End/cancel can race with dialing. Remove a late SIP leg if the iPad left.
    try { await client.rooms.getParticipant(room, identity); }
    catch (error) {
      if (!notFound(error)) throw error;
      await hangUp(client.rooms, room);
      return callJSON({ error: "The phone call was cancelled." }, 409);
    }
    return callJSON({ started: true });
  } catch (error) {
    // A timed-out request can still have created a SIP leg. Try to remove it.
    try { await hangUp(client.rooms, room); } catch { /* Client also retries cleanup on End call. */ }
    if (notFound(error)) return callJSON({ error: "Porch left the call before the phone could be dialed." }, 409);
    const code = error && typeof error === "object" && "sipStatusCode" in error ? Number(error.sipStatusCode) : 0;
    const message = code === 486 || code === 600 ? "Their phone is busy. Try again later."
      : code === 408 || code === 480 ? "Their phone didn't answer. Try again later."
      : code === 603 ? "The phone call was declined."
      : "Couldn't connect the phone call. Check the calling server and try again.";
    return callJSON({ error: message }, 502);
  } finally { dialing.delete(room); }
}
