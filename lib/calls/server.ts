import { createHash, timingSafeEqual } from "node:crypto";

/** `fromNumber`: the caller ID for a household's calls to regular phones, its own Porch number when it has one. */
export type CallServer = { apiKey: string; apiSecret: string; serverUrl: string; householdID?: string; fromNumber?: string };

export function callJSON(body: object, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } });
}

export function authorizeCalls(request: Request): CallServer | Response {
  const code = process.env.PORCH_CALL_ACCESS_CODE ?? "";
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;
  const serverUrl = process.env.LIVEKIT_URL;
  if (!/^[\x21-\x7e]{16,256}$/.test(code) || !apiKey || !apiSecret || !serverUrl) {
    return callJSON({ error: "Native calling isn't configured on this server yet." }, 503);
  }
  try {
    const url = new URL(serverUrl);
    if (url.protocol !== "wss:" || !url.hostname || url.username || url.password || url.search || url.hash) throw new Error();
  } catch {
    return callJSON({ error: "The server's LiveKit address must be a valid wss:// URL." }, 503);
  }
  const digest = (value: string) => createHash("sha256").update(value).digest();
  if (!timingSafeEqual(digest(request.headers.get("authorization") ?? ""), digest(`Bearer ${code}`))) {
    return callJSON({ error: "The prototype access code is incorrect." }, 401);
  }
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return callJSON({ error: "Join calls from the Porch website." }, 403);
  return { apiKey, apiSecret, serverUrl };
}

export async function callInput(request: Request): Promise<Record<string, unknown> | Response> {
  try {
    const text = await request.text();
    if (text.length > 2048) return callJSON({ error: "Call details are too long." }, 413);
    const input: unknown = JSON.parse(text);
    if (input && typeof input === "object" && !Array.isArray(input)) return input as Record<string, unknown>;
  } catch { /* Report invalid JSON without logging the request or phone number. */ }
  return callJSON({ error: "Send valid call details." }, 400);
}
