import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { authorizeCalls, callInput, callJSON, type CallServer } from "./server.ts";

const numberPattern = /^\+[1-9][0-9]{6,14}$/;
const lifetime = 30 * 24 * 60 * 60;
type Approval = { phoneNumber: string; audience: string; exp: number };

function setupCode(): string | undefined {
  const code = process.env.PORCH_CONTACT_SETUP_CODE;
  // Keep contact management separate from the code shared with call recipients.
  if (code && /^[\x21-\x7e]{16,256}$/.test(code) && code !== process.env.PORCH_CALL_ACCESS_CODE) return code;
}

function signature(body: string, config: CallServer, code: string) {
  return createHmac("sha256", config.apiSecret).update(`porch-contact-v1.${code}.${body}`).digest();
}

export function verifyContactApproval(value: unknown, phoneNumber: string, audience: string, config: CallServer, now: number): boolean {
  const code = setupCode();
  if (!code || typeof value !== "string" || value.length > 1000) return false;
  const [body, supplied, extra] = value.split(".");
  if (!body || !supplied || extra !== undefined) return false;
  const expected = signature(body, config, code);
  const actual = Buffer.from(supplied, "base64url");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return false;
  try {
    const approval: Approval = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
    return approval.phoneNumber === phoneNumber && approval.audience === audience &&
      Number.isInteger(approval.exp) && approval.exp > now && approval.exp <= now + lifetime;
  } catch { return false; }
}

export async function authorizeContact(request: Request, now = Math.floor(Date.now() / 1000)) {
  const config = authorizeCalls(request);
  if (config instanceof Response) return config;
  const code = setupCode();
  if (!code || !process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID) {
    return callJSON({ error: "A caregiver needs to configure a separate contact setup code and outbound phone trunk on this server." }, 503);
  }
  const digest = (value: string) => createHash("sha256").update(value).digest();
  if (!timingSafeEqual(digest(request.headers.get("x-porch-setup-code") ?? ""), digest(code))) {
    return callJSON({ error: "Check the caregiver setup code in Calling connection." }, 403);
  }
  const input = await callInput(request);
  if (input instanceof Response) return input;
  if (typeof input.phoneNumber !== "string" || !numberPattern.test(input.phoneNumber)) {
    return callJSON({ error: "Enter a phone number with + and its country code." }, 400);
  }
  const approval: Approval = { phoneNumber: input.phoneNumber, audience: new URL(request.url).origin, exp: now + lifetime };
  const body = Buffer.from(JSON.stringify(approval)).toString("base64url");
  // No dial, room creation, or third-party request occurs when a contact is saved.
  return callJSON({ authorization: `${body}.${signature(body, config, code).toString("base64url")}`, expiresAt: approval.exp });
}
