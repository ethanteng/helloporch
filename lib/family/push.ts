import { createPrivateKey, sign } from "node:crypto";
import { connect } from "node:http2";

/** A device's push token. iPhones and iPads use APNs, in its sandbox or production environment. Android devices use
 * Firebase Cloud Messaging, which has no environments. Registrations stored before Android existed have no platform: iOS. */
export type VoIPRegistration = { token: string; environment?: "sandbox" | "production"; platform?: "android" };
export type IncomingCallPush = { callID: string; recipientID: string; callerName: string; mode: "voice" | "video"; expiresAt: number };
export type PushResult = { delivered: boolean; invalidToken?: boolean };

export function apnsConfigured() {
  return !!(process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_PRIVATE_KEY && process.env.APNS_BUNDLE_ID);
}
export function fcmConfigured() {
  return !!(process.env.FCM_PROJECT_ID && process.env.FCM_CLIENT_EMAIL && process.env.FCM_PRIVATE_KEY);
}
/** Whether this server can push to this device: each platform has its own sender, set up separately. */
export function pushConfigured(device?: VoIPRegistration): device is VoIPRegistration {
  return !!device && (device.platform === "android" ? fcmConfigured() : apnsConfigured());
}
/** The same token for the same push service, so a cleanup never removes a registration that replaced a failed one. */
export function sameRegistration(current: VoIPRegistration | undefined, sent: VoIPRegistration) {
  return !!current && current.token === sent.token && current.environment === sent.environment && current.platform === sent.platform;
}
/** Forgets a token its push service rejected, wherever the device keeps it. An Android device registers its one FCM token
 * for both calls and alerts, so a token rejected for one is gone for the other too. An iPhone's two tokens differ. */
export function forgetRegistration(member: { voip?: VoIPRegistration; alerts?: VoIPRegistration }, rejected: VoIPRegistration) {
  if (sameRegistration(member.voip, rejected)) delete member.voip;
  if (sameRegistration(member.alerts, rejected)) delete member.alerts;
}

// Cache only the provider JWT, never device credentials or call payloads.
let providerToken: { key: string; jwt: string; issuedAt: number } | undefined;
export function apnsAuthorization(now = Math.floor(Date.now() / 1000)) {
  const { APNS_KEY_ID: kid, APNS_TEAM_ID: iss, APNS_PRIVATE_KEY: pem } = process.env;
  if (!kid || !iss || !pem) throw new Error("APNs not configured");
  const key = `${kid}:${iss}:${pem}`;
  if (providerToken?.key === key && now >= providerToken.issuedAt && now - providerToken.issuedAt < 3000) return providerToken.jwt;
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid })}.${encode({ iss, iat: now })}`;
  const signature = sign("sha256", Buffer.from(unsigned), { key: createPrivateKey(pem.replace(/\\n/g, "\n")), dsaEncoding: "ieee-p1363" });
  const jwt = `${unsigned}.${signature.toString("base64url")}`;
  providerToken = { key, jwt, issuedAt: now };
  return jwt;
}

type APNsRequest = { topic: string; pushType: "voip" | "alert"; id: string; expiration: number; payload: object };
function sendAPNs(device: VoIPRegistration, push: APNsRequest, createSession: typeof connect): Promise<PushResult> {
  const authorization = apnsAuthorization();
  return new Promise(resolve => {
    const client = createSession(device.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com");
    let finished = false;
    const finish = (result: PushResult) => {
      if (finished) return;
      finished = true; clearTimeout(timer); client.destroy(); resolve(result);
    };
    const timer = setTimeout(() => finish({ delivered: false }), 5000);
    client.on("error", () => finish({ delivered: false }));
    const request = client.request({ ":method": "POST", ":path": `/3/device/${device.token}`,
      authorization: `bearer ${authorization}`, "apns-topic": push.topic,
      "apns-push-type": push.pushType, "apns-priority": "10", "apns-expiration": String(push.expiration), "apns-id": push.id });
    let status = 0, body = "";
    request.on("response", headers => { status = Number(headers[":status"]); });
    request.on("data", chunk => { body += chunk; });
    request.on("error", () => finish({ delivered: false }));
    request.on("end", () => {
      let reason: string | undefined;
      try { reason = JSON.parse(body).reason; } catch { /* success has no body */ }
      finish({ delivered: status === 200, invalidToken: status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic" });
    });
    request.end(JSON.stringify(push.payload));
  });
}

const fcmScope = "https://www.googleapis.com/auth/firebase.messaging";
const googleTokenURL = "https://oauth2.googleapis.com/token";
/** The signed service-account assertion Google trades for an access token. Signing it also checks the key. */
export function fcmAssertion(now = Math.floor(Date.now() / 1000)) {
  const { FCM_CLIENT_EMAIL: iss, FCM_PRIVATE_KEY: pem } = process.env;
  if (!iss || !pem) throw new Error("FCM not configured");
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({ iss, scope: fcmScope, aud: googleTokenURL, iat: now, exp: now + 3600 })}`;
  return `${unsigned}.${sign("sha256", Buffer.from(unsigned), createPrivateKey(pem.replace(/\\n/g, "\n"))).toString("base64url")}`;
}
// Like the APNs JWT: only the short-lived access token is cached, and refreshed well before Google expires it.
let fcmAccess: { key: string; token: string; expiresAt: number } | undefined;
async function fcmAuthorization(request: typeof fetch, now: number) {
  const key = `${process.env.FCM_CLIENT_EMAIL}:${process.env.FCM_PRIVATE_KEY}`;
  if (fcmAccess?.key === key && now < fcmAccess.expiresAt - 300) return fcmAccess.token;
  const response = await request(googleTokenURL, { method: "POST", signal: AbortSignal.timeout(5000),
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: fcmAssertion(now) }) });
  if (!response.ok) throw new Error("FCM authorization failed");
  const { access_token: token, expires_in: lifetime } = await response.json();
  if (typeof token !== "string" || typeof lifetime !== "number") throw new Error("FCM authorization failed");
  fcmAccess = { key, token, expiresAt: now + lifetime };
  return token;
}
type FCMError = { error?: { status?: string; message?: string; details?: { errorCode?: string; fieldViolations?: { field?: string }[] }[] } };
/** Firebase's documented invalid-token response is INVALID_ARGUMENT with this message and no field violation. */
const invalidFcmTokenMessage = "The registration token is not a valid FCM registration token";
// FCM HTTP v1. Data values must be strings. Never throws: a failed push is reported like an APNs one.
async function sendFCM(device: VoIPRegistration, message: object, request: typeof fetch, now: number): Promise<PushResult> {
  try {
    const send = async () => request(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(process.env.FCM_PROJECT_ID!)}/messages:send`, {
      method: "POST", signal: AbortSignal.timeout(5000),
      headers: { authorization: `Bearer ${await fcmAuthorization(request, now)}`, "content-type": "application/json" },
      body: JSON.stringify({ message: { token: device.token, ...message } }) });
    let response = await send();
    // Google can revoke a cached access token early, such as when the key is rotated: sign in again, once.
    if (response.status === 401) { await response.body?.cancel(); fcmAccess = undefined; response = await send(); }
    if (response.ok) return { delivered: true, invalidToken: false };
    let error: FCMError["error"];
    try { error = ((await response.json()) as FCMError).error; } catch { /* no detail */ }
    const codes = error?.details?.map(detail => detail.errorCode) ?? [];
    // Only FCM's own verdict on the token counts. A bare 404 can be a mistyped project, which must not forget every
    // Android device. Other INVALID_ARGUMENT failures are our payload, so those count only when FCM names the token.
    const namesToken = error?.details?.some(detail => detail.fieldViolations?.some(violation => violation.field === "message.token"));
    return { delivered: false, invalidToken: codes.includes("UNREGISTERED") || codes.includes("SENDER_ID_MISMATCH") || !!namesToken || error?.message === invalidFcmTokenMessage };
  } catch {
    return { delivered: false };
  }
}

export async function sendVoIPPush(device: VoIPRegistration, call: IncomingCallPush, createSession: typeof connect = connect, now = Math.floor(Date.now() / 1000), request: typeof fetch = fetch): Promise<PushResult> {
  if (!pushConfigured(device)) return { delivered: false };
  // VoIP pushes only announce real incoming calls. Cancellation uses the live
  // signaling poll; never send a second VoIP push to cancel or update a call.
  if (device.platform === "android") {
    // Data only, so the app shows the call itself, at once even in Doze. Nothing is left to ring after the call stops ringing.
    return sendFCM(device, { data: { type: "call", callID: call.callID, recipientID: call.recipientID, callerName: call.callerName, mode: call.mode, expiresAt: String(call.expiresAt) },
      android: { priority: "HIGH", ttl: `${Math.max(0, call.expiresAt - now)}s` } }, request, now);
  }
  return sendAPNs(device, { topic: `${process.env.APNS_BUNDLE_ID}.voip`, pushType: "voip", id: call.callID, expiration: 0, payload: { aps: {}, ...call } }, createSession);
}

/** A visible notification on a family phone. APNs and FCM keep it for a week if the phone is off.
 * `recipientID` is the member it's for. A phone in several families is a different member in each, so this says which
 * family's thread to open, and keeps each family's notifications in their own group. */
export type MessageAlert = { messageID: string; recipientID: string; title: string; body: string; badge: number };
export async function sendAlertPush(device: VoIPRegistration, alert: MessageAlert, createSession: typeof connect = connect, now = Math.floor(Date.now() / 1000), request: typeof fetch = fetch): Promise<PushResult> {
  if (!pushConfigured(device)) return { delivered: false };
  if (device.platform === "android") {
    // Android has no badge field: launchers count notifications. Each family's newest message replaces its last one.
    return sendFCM(device, { data: { type: "message", messageID: alert.messageID, recipientID: alert.recipientID, badge: String(alert.badge) },
      android: { priority: "HIGH", ttl: `${7 * 86400}s`, notification: { title: alert.title, body: alert.body, channel_id: "messages", sound: "default",
        tag: `porch-messages-${alert.recipientID}`, notification_count: alert.badge } } }, request, now);
  }
  return sendAPNs(device, { topic: process.env.APNS_BUNDLE_ID!, pushType: "alert", id: alert.messageID, expiration: now + 7 * 86400,
    payload: { aps: { alert: { title: alert.title, body: alert.body }, sound: "default", badge: alert.badge, "thread-id": `porch-messages-${alert.recipientID}` }, messageID: alert.messageID, recipientID: alert.recipientID } }, createSession);
}
