import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { AccessToken, RoomConfiguration, RoomServiceClient, TrackSource } from "livekit-server-sdk";
import { callInput, callJSON, type CallServer } from "../calls/server.ts";
import { familyStore, type FamilyStore } from "./store.ts";
import { checkCaregiverCode, configureCaregiverPIN, CaregiverAuthError } from "./caregiver.ts";

type Role = "bedside" | "family";
type Mode = "voice" | "video";
type Permissions = { audio: boolean; video: boolean };
type Member = { id: string; name: string; role: Role; secretHash: string; permissions: Permissions; revoked: boolean; seenAt: number; available: boolean };
type Invite = { id: string; secretHash: string; name: string; permissions: Permissions; expiresAt: number; claimedBy?: string };
type Call = { id: string; from: string; to: string; mode: Mode; kind: "call" | "dropIn"; state: "pending" | "accepted" | "ended"; createdAt: number; announcedAt?: number; acceptedAt?: number; expiresAt: number; reason?: string };
type Household = { id: string; name: string; dropInEnabled: boolean; members: Member[]; invites: Invite[]; call?: Call };
type Auth = { householdID: string; deviceID: string; hash: string };
export type FamilyDependencies = { store?: FamilyStore; now?: () => number; endRoom?: (room: string, config: CallServer) => Promise<void> };
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const codePattern = /^[a-f0-9]{64}$/;
const equal = (a: string, b: string) => timingSafeEqual(Buffer.from(hash(a), "hex"), Buffer.from(hash(b), "hex"));
class FamilyError extends Error { status: number; code?: string; constructor(message: string, status = 400, code?: string) { super(message); this.status = status; this.code = code; } }
function requireValue(condition: unknown, message: string, status = 400): asserts condition { if (!condition) throw new FamilyError(message, status); }
function name(value: unknown): string { requireValue(typeof value === "string" && value.trim().length > 0 && value.trim().length <= 80, "Enter a name with 1–80 characters."); return value.trim(); }
function permissions(value: unknown): Permissions {
  requireValue(value !== null && typeof value === "object" && "audio" in value && "video" in value && typeof value.audio === "boolean" && typeof value.video === "boolean", "Choose audio and video permissions.");
  return { audio: value.audio, video: value.video };
}
function config(): CallServer {
  const { LIVEKIT_URL: serverUrl, LIVEKIT_API_KEY: apiKey, LIVEKIT_API_SECRET: apiSecret } = process.env;
  requireValue(serverUrl?.startsWith("wss://") && apiKey && apiSecret, "Calling is not configured.", 503);
  return { serverUrl: serverUrl!, apiKey, apiSecret };
}
function registration(input: Record<string, unknown>) {
  requireValue(typeof input.deviceID === "string" && uuid.test(input.deviceID) && typeof input.deviceSecret === "string" && codePattern.test(input.deviceSecret), "Retry pairing from your Porch app.");
  return { deviceID: input.deviceID, secret: input.deviceSecret };
}
async function reserveDevice(store: FamilyStore, deviceID: string, secret: string, householdID: string, invitation: string) {
  const key = `device:${deviceID}`;
  const reference = JSON.stringify({ householdID, secretHash: hash(secret), invitation });
  if (!await store.create(key, reference)) {
    requireValue(await store.get(key) === reference, "This device identity is already in use. Request a new invitation.", 409);
  }
}
async function authenticate(request: Request, store: FamilyStore): Promise<Auth> {
  const bearer = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  const [deviceID, secret, extra] = bearer.split(".");
  requireValue(uuid.test(deviceID ?? "") && codePattern.test(secret ?? "") && extra === undefined, "Pair this device with Porch first.", 401);
  const raw = await store.get(`device:${deviceID}`);
  requireValue(raw, "This device is no longer paired.", 401);
  return { householdID: JSON.parse(raw).householdID, deviceID, hash: hash(secret) };
}
function memberFor(house: Household, auth: Auth): Member {
  const member = house.members.find(m => m.id === auth.deviceID && !m.revoked && equal(m.secretHash, auth.hash));
  requireValue(member, "This device's access was removed. Ask for a new invitation.", 401);
  return member;
}
function online(member: Member, now: number) { return !member.revoked && member.available && member.seenAt > now - 30; }
function expire(house: Household, now: number) {
  const call = house.call;
  if (!call || call.state === "ended") return;
  if (call.expiresAt <= now || (call.state === "accepted" && [call.from, call.to].some(id => {
    const member = house.members.find(m => m.id === id);
    return !member || member.revoked || member.seenAt < now - 35;
  }))) { call.state = "ended"; call.reason = "The call timed out or a device went offline."; }
}
async function mutate<T>(store: FamilyStore, id: string, change: (house: Household) => T): Promise<{ house: Household; result: T }> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(`house:${id}`);
    requireValue(raw, "This household was not found.", 404);
    const house: Household = JSON.parse(raw);
    const result = change(house);
    const updated = JSON.stringify(house);
    if (updated === raw || await store.compareAndSet(`house:${id}`, raw, updated)) return { house, result };
  }
  throw new FamilyError("Porch is busy. Please try again.", 409);
}
function snapshot(house: Household, me: Member, now: number) {
  const publicMember = (m: Member) => ({ id: m.id, name: m.name, role: m.role, permissions: m.permissions, online: online(m, now) });
  const call = house.call;
  return { householdID: house.id, householdName: house.name, dropInEnabled: house.dropInEnabled, me: publicMember(me),
    people: house.members.filter(m => !m.revoked && m.role !== me.role).map(publicMember),
    call: call && (call.from === me.id || call.to === me.id) ? { ...call, callerName: house.members.find(m => m.id === call.from)?.name ?? "Family" } : null,
    busy: !!call && call.state !== "ended", serverTime: now };
}
async function endRoom(callID: string, dependencies: FamilyDependencies) {
  const configuration = config();
  const room = `porch-paired-${callID}`;
  if (dependencies.endRoom) { await dependencies.endRoom(room, configuration); return; }
  try { await new RoomServiceClient(configuration.serverUrl.replace(/^wss:/, "https:"), configuration.apiKey, configuration.apiSecret, { requestTimeout: 8 }).deleteRoom(room); }
  catch (error) { if (!(error && typeof error === "object" && "code" in error && error.code === "not_found")) throw error; }
}

export async function handleFamily(request: Request, dependencies: FamilyDependencies = {}) {
  try {
    const origin = request.headers.get("origin");
    requireValue(!origin || origin === new URL(request.url).origin, "Use your Porch app to manage family calls.", 403);
    const input = await callInput(request);
    if (input instanceof Response) return input;
    const store = dependencies.store ?? familyStore();
    const now = dependencies.now?.() ?? Math.floor(Date.now() / 1000);
    const action = input.action;
    if (action === "setCaregiverPIN") {
      if ((request.headers.get("X-Porch-Setup-Code") ?? "").length < 16) {
        const auth = await authenticate(request, store);
        const raw = await store.get(`house:${auth.householdID}`);
        requireValue(raw && memberFor(JSON.parse(raw), auth).role === "bedside", "Only a bedside caregiver can change the PIN.", 403);
      }
      await configureCaregiverPIN(request, input.pin, store, now);
      return callJSON({ saved: true });
    }
    if (action === "createHousehold") {
      config();
      await checkCaregiverCode(request, store, now);
      const { deviceID, secret } = registration(input);
      const id = deviceID;
      await reserveDevice(store, deviceID, secret, id, "bedside");
      const me: Member = { id: deviceID, name: name(input.name), role: "bedside", secretHash: hash(secret), permissions: { audio: false, video: false }, revoked: false, seenAt: now, available: false };
      const house: Household = { id, name: me.name, dropInEnabled: false, members: [me], invites: [] };
      if (!await store.create(`house:${id}`, JSON.stringify(house))) {
        const existing: Household = JSON.parse((await store.get(`house:${id}`))!);
        const owner = memberFor(existing, { householdID: id, deviceID, hash: hash(secret) });
        await store.create(`device:${deviceID}`, JSON.stringify({ householdID: id }));
        return callJSON({ credential: `${deviceID}.${secret}`, role: "bedside", state: snapshot(existing, owner, now) });
      }
      await store.create(`device:${deviceID}`, JSON.stringify({ householdID: id }));
      return callJSON({ credential: `${deviceID}.${secret}`, role: "bedside", state: snapshot(house, me, now) });
    }
    if (action === "claimInvite") {
      requireValue(typeof input.code === "string" && codePattern.test(input.code), "Paste a valid invitation.");
      const inviteHash = hash(input.code);
      const reference = await store.get(`invite:${inviteHash}`);
      requireValue(reference, "This invitation expired or was cancelled. Ask for a new one.", 410);
      const { householdID, inviteID } = JSON.parse(reference);
      const { deviceID, secret } = registration(input);
      await reserveDevice(store, deviceID, secret, householdID, inviteID);
      const { house } = await mutate(store, householdID, house => {
        const invite = house.invites.find(i => i.id === inviteID && i.secretHash === inviteHash && i.expiresAt > now);
        requireValue(invite, "This invitation was already used, expired, or was cancelled.", 410);
        if (invite.claimedBy) {
          requireValue(invite.claimedBy === deviceID && house.members.some(m => m.id === deviceID && !m.revoked && equal(m.secretHash, hash(secret))), "This invitation was already used.", 410);
          return;
        }
        requireValue(!house.members.some(m => m.id === deviceID), "This device identity is already in use.", 409);
        requireValue(house.members.filter(m => !m.revoked).length < 20, "This household has reached its device limit.");
        const me: Member = { id: deviceID, name: invite.name, role: "family", secretHash: hash(secret), permissions: invite.permissions, revoked: false, seenAt: now, available: false };
        house.members.push(me); invite.claimedBy = deviceID;
      });
      await store.create(`device:${deviceID}`, JSON.stringify({ householdID }));
      return callJSON({ credential: `${deviceID}.${secret}`, role: "family", state: snapshot(house, house.members.find(m => m.id === deviceID)!, now) });
    }
    const auth = await authenticate(request, store);
    if (["createInvite", "setPermissions", "setDropIn", "revoke", "cancelInvites", "verifyPIN"].includes(String(action))) {
      const raw = await store.get(`house:${auth.householdID}`);
      requireValue(raw && memberFor(JSON.parse(raw), auth).role === "bedside", "Only a bedside caregiver can change access.", 403);
      await checkCaregiverCode(request, store, now);
    }
    let cleanupID: string | undefined;
    let issuedCode: string | undefined;
    if (action === "createInvite") issuedCode = randomBytes(32).toString("hex");
    const { house, result } = await mutate(store, auth.householdID, house => {
      const me = memberFor(house, auth);
      expire(house, now);
      if (action === "verifyPIN") { requireValue(me.role === "bedside", "Only a bedside caregiver can unlock settings.", 403); return undefined; }
      if (action === "poll") {
        requireValue(typeof input.available === "boolean", "Send this device's availability.");
        me.seenAt = now; me.available = input.available;
        if (input.available && house.call?.to === me.id && house.call.state === "pending" && !house.call.announcedAt) house.call.announcedAt = now;
        return undefined;
      }
      if (action === "createInvite" || action === "setPermissions" || action === "setDropIn" || action === "revoke" || action === "cancelInvites") {
        requireValue(me.role === "bedside", "Only the bedside caregiver can change access.", 403);
        if (action === "createInvite") {
          house.invites = house.invites.filter(i => !i.claimedBy && i.expiresAt > now);
          requireValue(house.invites.length < 10, "Cancel an unused invitation before creating another.");
          const invite: Invite = { id: randomUUID(), secretHash: hash(issuedCode!), name: name(input.name), permissions: permissions(input.permissions), expiresAt: now + 900 };
          house.invites.push(invite);
          return { inviteID: invite.id, expiresAt: invite.expiresAt };
        }
        if (action === "cancelInvites") { house.invites = []; return undefined; }
        if (action === "setDropIn") {
          requireValue(typeof input.enabled === "boolean", "Choose whether drop-in is enabled.");
          house.dropInEnabled = input.enabled;
        } else {
          const target = house.members.find(m => m.id === input.memberID && m.role === "family" && !m.revoked);
          requireValue(target, "This family member was not found.", 404);
          if (action === "revoke") target.revoked = true;
          else target.permissions = permissions(input.permissions);
        }
        const call = house.call;
        if (call && call.state !== "ended" && (house.members.some(m => m.revoked && [call.from, call.to].includes(m.id)) || (call.kind === "dropIn" && (!house.dropInEnabled || !house.members.find(m => m.id === call.from)?.permissions[call.mode === "voice" ? "audio" : "video"])))) {
          call.state = "ended"; call.reason = "Drop-in access was changed."; cleanupID = call.id;
        }
        return undefined;
      }
      if (action === "startCall") {
        requireValue(input.mode === "voice" || input.mode === "video", "Choose audio or video.");
        requireValue(input.kind === "call" || input.kind === "dropIn", "Choose a call type.");
        const target = house.members.find(m => m.id === input.targetID && !m.revoked && m.role !== me.role);
        requireValue(target, "This person is not paired with your device.", 403);
        requireValue(!house.call || house.call.state === "ended", "Another call is already in progress.", 409);
        if (!online(target, now)) throw new FamilyError("Their Porch app is not ready. Ask them to open it and keep it unlocked.", 409, "offline");
        if (input.kind === "dropIn") requireValue(me.role === "family" && target.role === "bedside" && house.dropInEnabled && me.permissions[input.mode === "voice" ? "audio" : "video"], "You are not approved for this type of drop-in.", 403);
        const wait = me.role === "bedside" && input.waitSeconds !== undefined ? input.waitSeconds : 45;
        requireValue(typeof wait === "number" && Number.isInteger(wait) && wait >= 5 && wait <= 120, "Choose a waiting time from 5 to 120 seconds.");
        me.seenAt = now;
        house.call = { id: randomUUID(), from: me.id, to: target.id, mode: input.mode, kind: input.kind, state: "pending", createdAt: now, expiresAt: now + wait + 30 };
        return undefined;
      }
      if (action === "acceptCall" || action === "endCall" || action === "joinCall" || action === "fallback") {
        const call = house.call;
        requireValue(call && call.id === input.callID && [call.from, call.to].includes(me.id), "This call is no longer available.", 404);
        if (action === "fallback") {
          requireValue(me.role === "bedside" && call.from === me.id && call.kind === "call", "Phone fallback is only available to the bedside caller.", 403);
          if (call.state === "accepted") throw new FamilyError("They answered on Porch. Phone fallback was cancelled.", 409, "answered");
          requireValue(call.state === "pending", "This call already ended.", 410);
          call.state = "ended"; call.reason = "Trying their regular phone."; cleanupID = call.id;
        } else if (action === "endCall") {
          call.state = "ended"; call.reason = "Call ended."; cleanupID = call.id;
        } else {
          requireValue(call.state !== "ended" && call.expiresAt > now, "This call ended or expired.", 410);
          if (call.kind === "dropIn") {
            const caller = house.members.find(m => m.id === call.from)!;
            requireValue(house.dropInEnabled && caller.permissions[call.mode === "voice" ? "audio" : "video"] && !caller.revoked, "Drop-in access was removed.", 403);
          }
          if (action === "acceptCall") {
            requireValue(call.to === me.id && input.available === true, "Open Porch to answer this call.", 409);
            requireValue(call.state === "pending", "This call was already answered.", 409);
            if (call.kind === "dropIn") requireValue(call.announcedAt && now >= call.announcedAt + 5, "Wait for the drop-in announcement to finish.", 409);
            call.state = "accepted"; call.acceptedAt = now; call.expiresAt = now + 1800;
            me.available = false; me.seenAt = now;
          } else requireValue(call.from === me.id || call.state === "accepted", "Answer this call before joining.", 403);
        }
        return undefined;
      }
      throw new FamilyError("Unknown family action.");
    });
    const me = memberFor(house, auth);
    if (issuedCode && result) await store.create(`invite:${hash(issuedCode)}`, JSON.stringify({ householdID: house.id, inviteID: result.inviteID }), 900);
    if (cleanupID) {
      try { await endRoom(cleanupID, dependencies); }
      catch { return callJSON({ error: "Access is updated. Couldn't confirm media disconnected; keep this device offline until the call ends.", state: snapshot(house, me, now) }, 502); }
    }
    if (action === "joinCall") {
      const call = house.call!;
      const configuration = config();
      const roomName = `porch-paired-${call.id}`;
      const token = new AccessToken(configuration.apiKey, configuration.apiSecret, { identity: me.id, name: me.name, ttl: "1m" });
      token.roomConfig = new RoomConfiguration({ maxParticipants: 2, emptyTimeout: 60, departureTimeout: 5 });
      token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true, canPublishData: false, canUpdateOwnMetadata: false,
        canPublishSources: call.mode === "voice" ? [TrackSource.MICROPHONE] : [TrackSource.MICROPHONE, TrackSource.CAMERA] });
      return callJSON({ token: await token.toJwt(), serverUrl: configuration.serverUrl, room: roomName });
    }
    return callJSON({ state: snapshot(house, me, now), ...(issuedCode && result ? { code: issuedCode, expiresAt: result.expiresAt } : {}) });
  } catch (error) {
    if (error instanceof FamilyError || error instanceof CaregiverAuthError) return callJSON({ error: error.message, ...(error instanceof FamilyError && error.code ? { errorCode: error.code } : {}) }, error.status);
    return callJSON({ error: "Family calling is unavailable. Check the connection and shared storage setup." }, 503);
  }
}

// Device credentials are sufficient for a paired bedside iPad's phone fallback.
// Family devices cannot authorize destinations or use the SIP trunk.
export async function authorizeBedsideCalling(request: Request): Promise<CallServer | Response> {
  try {
    const store = familyStore();
    const auth = await authenticate(request, store);
    const raw = await store.get(`house:${auth.householdID}`);
    requireValue(raw, "This household was not found.", 401);
    const member = memberFor(JSON.parse(raw), auth);
    requireValue(member.role === "bedside", "Only a bedside device can use phone fallback.", 403);
    return config();
  } catch (error) {
    return callJSON({ error: error instanceof FamilyError ? error.message : "Couldn't verify this device." }, error instanceof FamilyError ? error.status : 503);
  }
}
