import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { AccessToken, RoomConfiguration, RoomServiceClient, TrackSource } from "livekit-server-sdk";
import { callInput, callJSON, type CallServer } from "../calls/server.ts";
import { familyStore, type FamilyStore } from "./store.ts";
import { checkCaregiverCode, configureCaregiverPIN, initializeCaregiverPIN, caregiverPINKey, CaregiverAuthError } from "./caregiver.ts";

import { callRoom, config, expire, FamilyError, mutate, requireValue, type Auth, type Call, type Household, type Invite, type Member, type Permissions } from "./household.ts";
import { cleanupInboundCall, reconcileInboundCall, type InboundDependencies } from "./inbound.ts";

export type FamilyDependencies = InboundDependencies;

import { sendVoIPPush, voipConfigured, type PushResult } from "./push.ts";

const hash = (value: string) => createHash("sha256").update(value).digest("hex");
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const codePattern = /^[a-f0-9]{64}$/;
const equal = (a: string, b: string) => timingSafeEqual(Buffer.from(hash(a), "hex"), Buffer.from(hash(b), "hex"));
function name(value: unknown): string { requireValue(typeof value === "string" && value.trim().length > 0 && value.trim().length <= 80, "Enter a name with 1–80 characters."); return value.trim(); }
function permissions(value: unknown): Permissions {
  requireValue(value !== null && typeof value === "object" && "audio" in value && "video" in value && typeof value.audio === "boolean" && typeof value.video === "boolean", "Choose audio and video permissions.");
  return { audio: value.audio, video: value.video };
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
// The bedside device is always a caregiver; family devices need the caregiver's approval (and the PIN).
function isCaregiver(member: Member) { return member.role === "bedside" || member.caregiver === true; }
const caregiverActions = ["createInvite", "setPermissions", "setDropIn", "revoke", "cancelInvites", "verifyPIN", "setHouseholdName", "setCaregiver"];
function publicCall(call: Call) { const { phone: _phone, ...result } = call; return result; }
function publicPerson(m: Member, now: number, pushEnabled: boolean) {
  return { id: m.id, name: m.name, role: m.role, permissions: m.permissions, online: online(m, now), canReceiveCalls: online(m, now) || (!!m.voip && pushEnabled), ...(m.role === "family" ? { caregiver: !!m.caregiver } : {}) };
}
// Family devices only see the bedside in their snapshot, so caregiver screens get every
// family device here. It is returned only after a PIN check.
function adminState(house: Household, now: number, pushEnabled: boolean) {
  return { householdName: house.name, dropInEnabled: house.dropInEnabled, people: house.members.filter(m => !m.revoked && m.role === "family").map(m => publicPerson(m, now, pushEnabled)) };
}
function snapshot(house: Household, me: Member, now: number, pushEnabled = voipConfigured()) {
  const publicMember = (m: Member) => ({ ...publicPerson(m, now, pushEnabled), ...(me.role === "bedside" && m.invitationID ? { invitationID: m.invitationID } : {}) });
  const call = house.call;
  return { householdID: house.id, householdName: house.name, dropInEnabled: house.dropInEnabled, me: publicMember(me),
    invitations: me.role === "bedside" ? house.invites.filter(i => !i.claimedBy && i.expiresAt > now).map(i => ({ id: i.id, expiresAt: i.expiresAt })) : [],
    people: house.members.filter(m => !m.revoked && m.role !== me.role).map(publicMember),
    call: call && (call.from === me.id || call.to === me.id) ? { ...publicCall(call), source: call.phone ? "phone" : "porch", callerName: call.phone ? call.phone.callerNumber ?? "Phone caller" : house.members.find(m => m.id === call.from)?.name ?? "Family" } : null,
    busy: !!call && call.state !== "ended", serverTime: now };
}
async function endRoom(room: string, dependencies: FamilyDependencies) {
  const configuration = config();
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
    const pushEnabled = !!dependencies.sendPush || voipConfigured();
    if (action === "createBedsideInvite") {
      requireValue((request.headers.get("X-Porch-Setup-Code") ?? "").length >= 16, "A server operator must authorize a new bedside device.", 403);
      await checkCaregiverCode(request, store, now);
      const code = randomBytes(32).toString("hex"), expiresAt = now + 86400;
      await store.create(`activation:${hash(code)}`, JSON.stringify({ expiresAt }), 86400);
      return callJSON({ code, expiresAt });
    }
    if (action === "setCaregiverPIN") {
      let householdID: string | undefined;
      if (request.headers.has("authorization") || (request.headers.get("X-Porch-Setup-Code") ?? "").length < 16) {
        const auth = await authenticate(request, store);
        const raw = await store.get(`house:${auth.householdID}`);
        requireValue(raw && memberFor(JSON.parse(raw), auth).role === "bedside", "Only a bedside caregiver can change the PIN.", 403);
        householdID = auth.householdID;
      }
      await configureCaregiverPIN(request, input.pin, store, now, householdID);
      return callJSON({ saved: true });
    }
    if (action === "createHousehold" || action === "enrollBedside") {
      config();
      const enrolling = action === "enrollBedside";
      if (enrolling) requireValue(typeof input.pin === "string" && /^\d{6}$/.test(input.pin), "Choose a six-digit caregiver PIN.");
      const { deviceID, secret } = registration(input);
      const id = deviceID;
      const bedsideName = name(input.name ?? "Your loved one");
      if (enrolling && input.activation !== undefined) {
        requireValue(typeof input.activation === "string" && codePattern.test(input.activation), "Open a valid bedside activation link.");
        const key = `activation:${hash(input.activation)}`;
        let claimed = false;
        for (let n = 0; n < 12; n++) {
          const raw = await store.get(key);
          requireValue(raw, "This activation link expired. Request a new one.", 410);
          const activation = JSON.parse(raw);
          requireValue(activation.expiresAt > now, "This activation link expired. Request a new one.", 410);
          if (activation.claimedBy) {
            requireValue(activation.claimedBy === deviceID && activation.claimHash === hash(secret), "This activation link was already used.", 410);
            claimed = true; break;
          }
          if (await store.compareAndSet(key, raw, JSON.stringify({ ...activation, claimedBy: deviceID, claimHash: hash(secret) }))) { claimed = true; break; }
        }
        requireValue(claimed, "Activation is busy. Try again.", 409);
      } else await checkCaregiverCode(request, store, now);
      await reserveDevice(store, deviceID, secret, id, "bedside");
      const me: Member = { id: deviceID, name: bedsideName, role: "bedside", secretHash: hash(secret), permissions: { audio: false, video: false }, revoked: false, seenAt: now, available: false };
      const house: Household = { id, name: me.name, dropInEnabled: false, members: [me], invites: [] };
      if (!await store.create(`house:${id}`, JSON.stringify(house))) {
        const existing: Household = JSON.parse((await store.get(`house:${id}`))!);
        const owner = memberFor(existing, { householdID: id, deviceID, hash: hash(secret) });
        if (enrolling) {
          if (!await initializeCaregiverPIN(input.pin, store, id)) {
            const headers = new Headers(request.headers); headers.set("X-Porch-Setup-Code", String(input.pin));
            await checkCaregiverCode(new Request(request.url, { headers }), store, now, id);
          }
        }
        await store.create(`device:${deviceID}`, JSON.stringify({ householdID: id }));
        return callJSON({ credential: `${deviceID}.${secret}`, role: "bedside", state: snapshot(existing, owner, now, pushEnabled) });
      }
      if (enrolling) await initializeCaregiverPIN(input.pin, store, id);
      await store.create(`device:${deviceID}`, JSON.stringify({ householdID: id }));
      return callJSON({ credential: `${deviceID}.${secret}`, role: "bedside", state: snapshot(house, me, now, pushEnabled) });
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
        const me: Member = { invitationID: invite.id, id: deviceID, name: invite.name, role: "family", secretHash: hash(secret), permissions: invite.permissions, ...(invite.caregiver ? { caregiver: true } : {}), revoked: false, seenAt: now, available: false };
        house.members.push(me); invite.claimedBy = deviceID;
      });
      await store.create(`device:${deviceID}`, JSON.stringify({ householdID }));
      return callJSON({ credential: `${deviceID}.${secret}`, role: "family", state: snapshot(house, house.members.find(m => m.id === deviceID)!, now, pushEnabled) });
    }
    const auth = await authenticate(request, store);
    if (action === "caregiverStatus" || action === "initializeCaregiverPIN") {
      const raw = await store.get(`house:${auth.householdID}`);
      requireValue(raw && memberFor(JSON.parse(raw), auth).role === "bedside", "Only the bedside caregiver can set a PIN.", 403);
      if (action === "caregiverStatus") return callJSON({ pinConfigured: !!await store.get(caregiverPINKey(auth.householdID)) });
      requireValue(await initializeCaregiverPIN(input.pin, store, auth.householdID), "A PIN is already set. Enter your current PIN to change it.", 409);
      return callJSON({ saved: true });
    }
    const caregiverAction = caregiverActions.includes(String(action));
    if (caregiverAction) {
      const raw = await store.get(`house:${auth.householdID}`);
      const member = raw ? memberFor(JSON.parse(raw), auth) : undefined;
      requireValue(member && isCaregiver(member), "Only an approved caregiver can change access.", 403);
      await checkCaregiverCode(request, store, now, auth.householdID, member.role === "bedside" ? undefined : member.id);
    }
    if (["poll", "acceptCall", "joinCall", "startCall"].includes(String(action))) {
      const raw = await store.get(`house:${auth.householdID}`);
      requireValue(raw, "This household was not found.", 404);
      memberFor(JSON.parse(raw), auth);
      await reconcileInboundCall(store, auth.householdID, now, dependencies, action === "acceptCall" || action === "joinCall");
    }
    let cleanupRoom: string | undefined;
    let issuedCode: string | undefined;
    if (action === "createInvite") issuedCode = randomBytes(32).toString("hex");
    const { house, result } = await mutate(store, auth.householdID, house => {
      const me = memberFor(house, auth);
      expire(house, now);
      if (house.call?.phone && house.call.state === "ended" && !house.call.phone.cleanedUp) cleanupRoom = callRoom(house.call);
      // Rechecked inside the update: approval may have been withdrawn since the PIN check.
      if (caregiverAction) requireValue(isCaregiver(me), "Only an approved caregiver can change access.", 403);
      if (action === "verifyPIN") return undefined;
      if (action === "setHouseholdName") {
        house.name = name(input.name);
        const bedside = house.members.find(m => m.role === "bedside");
        if (bedside) bedside.name = house.name;
        return undefined;
      }
      if (action === "leaveHousehold") {
        requireValue(me.role === "family", "A bedside device can't leave its household.", 403);
        me.revoked = true; delete me.voip; delete me.caregiver;
        const call = house.call;
        if (call && call.state !== "ended" && [call.from, call.to].includes(me.id)) { call.state = "ended"; call.reason = "Call ended."; cleanupRoom = callRoom(call); }
        return undefined;
      }
      if (action === "registerVoIP") {
        if (input.token === null) { delete me.voip; return undefined; }
        requireValue(typeof input.token === "string" && /^[a-f0-9]{32,512}$/.test(input.token) && input.token.length % 2 === 0, "Invalid VoIP token.");
        requireValue(input.environment === "sandbox" || input.environment === "production", "Invalid push environment.");
        me.voip = { token: input.token, environment: input.environment };
        return undefined;
      }
      if (action === "poll") {
        requireValue(typeof input.available === "boolean", "Send this device's availability.");
        me.seenAt = now; me.available = input.available;
        const call = house.call;
        // Receipt is scoped to the authenticated recipient and exact pending
        // ordinary call; it never grants foreground readiness or drop-in consent.
        if (call?.to === me.id && call.kind === "call" && call.state === "pending" && input.receivedCallID === call.id) call.receivedAt ??= now;
        if (input.available && house.call?.to === me.id && house.call.state === "pending" && !house.call.announcedAt) house.call.announcedAt = now;
        return undefined;
      }
      if (action === "createInvite" || action === "setPermissions" || action === "setDropIn" || action === "revoke" || action === "cancelInvites" || action === "setCaregiver") {
        if (action === "createInvite") {
          house.invites = house.invites.filter(i => !i.claimedBy && i.expiresAt > now);
          requireValue(house.invites.length < 10, "Cancel an unused invitation before creating another.");
          requireValue(input.caregiver === undefined || typeof input.caregiver === "boolean", "Choose whether they can use caregiver mode.");
          const invite: Invite = { id: randomUUID(), secretHash: hash(issuedCode!), name: name(input.name), permissions: permissions(input.permissions), ...(input.caregiver ? { caregiver: true } : {}), expiresAt: now + 900 };
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
          if (action === "revoke") {
            requireValue(target.id !== me.id, "To remove this device, choose Join a different family.", 403);
            target.revoked = true; delete target.voip; delete target.caregiver;
          } else if (action === "setCaregiver") {
            requireValue(target.id !== me.id, "Another caregiver must change your caregiver access.", 403);
            requireValue(typeof input.enabled === "boolean", "Choose whether they can use caregiver mode.");
            if (input.enabled) target.caregiver = true; else delete target.caregiver;
          } else target.permissions = permissions(input.permissions);
        }
        const call = house.call;
        if (call && call.state !== "ended" && (house.members.some(m => m.revoked && [call.from, call.to].includes(m.id)) || (call.kind === "dropIn" && (!house.dropInEnabled || !house.members.find(m => m.id === call.from)?.permissions[call.mode === "voice" ? "audio" : "video"])))) {
          call.state = "ended"; call.reason = "Drop-in access was changed."; cleanupRoom = callRoom(call);
        }
        return undefined;
      }
      if (action === "startCall") {
        requireValue(input.mode === "voice" || input.mode === "video", "Choose audio or video.");
        requireValue(input.kind === "call" || input.kind === "dropIn", "Choose a call type.");
        if (me.role === "bedside" && input.unlinked === true && input.kind === "call") {
          requireValue(!house.call || house.call.state === "ended", "Another call is already in progress.", 409);
          throw new FamilyError("This person hasn't paired a Porch app yet.", 409, "offline");
        }
        const target = house.members.find(m => m.id === input.targetID && !m.revoked && m.role !== me.role);
        requireValue(target, "This person is not paired with your device.", 403);
        requireValue(!house.call || house.call.state === "ended", "Another call is already in progress.", 409);
        if (!online(target, now) && !(input.kind === "call" && target.voip && pushEnabled)) throw new FamilyError("Their Porch app is not ready. Ask them to open it and keep it unlocked.", 409, "offline");
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
          call.state = "ended"; call.reason = "Trying their regular phone."; cleanupRoom = callRoom(call);
        } else if (action === "endCall") {
          call.state = "ended"; call.reason = "Call ended."; cleanupRoom = callRoom(call);
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
          } else { requireValue(call.from === me.id || call.state === "accepted", "Answer this call before joining.", 403); me.seenAt = now; }
        }
        return undefined;
      }
      throw new FamilyError("Unknown family action.");
    });
    const releaseRoom = async (room: string) => {
      if (house.call?.phone && callRoom(house.call) === room) await cleanupInboundCall(store, house.id, house.call, dependencies);
      else await endRoom(room, dependencies);
    };
    if (action === "leaveHousehold") {
      // The call already ended in storage; LiveKit's empty-room timeout covers a failed delete.
      if (cleanupRoom) { try { await releaseRoom(cleanupRoom); } catch { /* see above */ } }
      return callJSON({ left: true });
    }
    const me = memberFor(house, auth);
    if (action === "startCall" && house.call?.kind === "call") {
      const call = house.call;
      const target = house.members.find(m => m.id === call.to)!;
      if (target.voip && pushEnabled) {
        // Outside the CAS mutation: concurrent callers/retries cannot send pushes
        // for a call that never won the household reservation.
        const registration = target.voip;
        let delivery: PushResult;
        try { delivery = await (dependencies.sendPush ?? sendVoIPPush)(registration, {
          callID: call.id, recipientID: target.id, callerName: me.name, mode: call.mode, expiresAt: call.expiresAt,
        }); } catch { delivery = { delivered: false }; }
        if (!delivery.delivered) {
          const updated = await mutate(store, house.id, current => {
            const recipient = current.members.find(m => m.id === target.id);
            if (delivery.invalidToken && recipient?.voip?.token === registration.token && recipient.voip.environment === registration.environment) delete recipient.voip;
            const active = current.call;
            // A call-specific recipient receipt or answer outweighs a missing
            // APNs acknowledgment, even while the recipient is backgrounded.
            if (recipient && !online(recipient, now) && active?.id === call.id && active.state === "pending" && active.receivedAt === undefined) {
              active.state = "ended"; active.reason = "Incoming call delivery unavailable.";
              return true;
            }
            return false;
          });
          Object.assign(house, updated.house);
          if (updated.result) {
            try { await endRoom(callRoom(call), dependencies); } catch { /* no recipient joined */ }
            throw new FamilyError("Couldn't reach their Porch app. Try their phone.", 409, "offline");
          }
        }
      }
    }
    if (issuedCode && result) await store.create(`invite:${hash(issuedCode)}`, JSON.stringify({ householdID: house.id, inviteID: result.inviteID }), 900);
    if (cleanupRoom) {
      try { await releaseRoom(cleanupRoom); }
      catch { return callJSON({ error: "Access is updated. Couldn't confirm media disconnected; keep this device offline until the call ends.", state: snapshot(house, me, now, pushEnabled) }, 502); }
    }
    if (action === "joinCall") {
      const call = house.call!;
      const configuration = config();
      const roomName = callRoom(call);
      const token = new AccessToken(configuration.apiKey, configuration.apiSecret, { identity: me.id, name: me.name, ttl: "1m" });
      token.roomConfig = new RoomConfiguration({ maxParticipants: 2, emptyTimeout: 60, departureTimeout: 5 });
      token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true, canPublishData: false, canUpdateOwnMetadata: false,
        canPublishSources: call.mode === "voice" ? [TrackSource.MICROPHONE] : [TrackSource.MICROPHONE, TrackSource.CAMERA] });
      return callJSON({ token: await token.toJwt(), serverUrl: configuration.serverUrl, room: roomName });
    }
    return callJSON({ state: snapshot(house, me, now, pushEnabled), ...(caregiverAction ? { admin: adminState(house, now, pushEnabled) } : {}), ...(action === "registerVoIP" ? { pushReady: !!me.voip && pushEnabled } : {}), ...(issuedCode && result ? { code: issuedCode, invitationID: result.inviteID, expiresAt: result.expiresAt } : {}) });
  } catch (error) {
    if (error instanceof FamilyError || error instanceof CaregiverAuthError) return callJSON({ error: error.message, ...(error instanceof FamilyError && error.code ? { errorCode: error.code } : {}) }, error.status);
    return callJSON({ error: "Family calling is unavailable. Check the connection and shared storage setup." }, 503);
  }
}

// Device credentials are sufficient for a paired bedside iPad's phone fallback.
// Family devices cannot authorize destinations or use the SIP trunk.
export async function authorizeBedsideCalling(request: Request): Promise<CallServer | Response> {
  try {
    const origin = request.headers.get("origin");
    requireValue(!origin || origin === new URL(request.url).origin, "Use your Porch app to place calls.", 403);
    const store = familyStore();
    const auth = await authenticate(request, store);
    const raw = await store.get(`house:${auth.householdID}`);
    requireValue(raw, "This household was not found.", 401);
    const member = memberFor(JSON.parse(raw), auth);
    requireValue(member.role === "bedside", "Only a bedside device can use phone fallback.", 403);
    return { ...config(), householdID: auth.householdID };
  } catch (error) {
    return callJSON({ error: error instanceof FamilyError ? error.message : "Couldn't verify this device." }, error instanceof FamilyError ? error.status : 503);
  }
}
