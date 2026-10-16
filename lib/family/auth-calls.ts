import { authorizeCalls } from "../calls/server.ts";
import { authorizeBedsideCalling } from "./service.ts";
export async function authorizeNativeOrBedside(request: Request) {
  if (/^Bearer [a-f0-9-]{36}\.[a-f0-9]{64}$/.test(request.headers.get("authorization") ?? "")) return authorizeBedsideCalling(request);
  return authorizeCalls(request);
}
