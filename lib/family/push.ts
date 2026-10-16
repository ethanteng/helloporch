import { createPrivateKey, sign } from "node:crypto";
import { connect } from "node:http2";

export type VoIPRegistration = { token: string; environment: "sandbox" | "production" };
export type IncomingCallPush = { callID: string; recipientID: string; callerName: string; mode: "voice" | "video"; expiresAt: number };
export type PushResult = { delivered: boolean; invalidToken?: boolean };

export function voipConfigured() {
  return !!(process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_PRIVATE_KEY && process.env.APNS_BUNDLE_ID);
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

export async function sendVoIPPush(device: VoIPRegistration, call: IncomingCallPush, createSession: typeof connect = connect): Promise<PushResult> {
  if (!voipConfigured()) return { delivered: false };
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
      authorization: `bearer ${authorization}`, "apns-topic": `${process.env.APNS_BUNDLE_ID}.voip`,
      "apns-push-type": "voip", "apns-priority": "10", "apns-expiration": "0", "apns-id": call.callID });
    let status = 0, body = "";
    request.on("response", headers => { status = Number(headers[":status"]); });
    request.on("data", chunk => { body += chunk; });
    request.on("error", () => finish({ delivered: false }));
    request.on("end", () => {
      let reason: string | undefined;
      try { reason = JSON.parse(body).reason; } catch { /* success has no body */ }
      finish({ delivered: status === 200, invalidToken: status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic" });
    });
    // VoIP pushes only announce real incoming calls. Cancellation uses the live
    // signaling poll; never send a second VoIP push to cancel or update a call.
    request.end(JSON.stringify({ aps: {}, ...call }));
  });
}
