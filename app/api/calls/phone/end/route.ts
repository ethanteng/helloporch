import { handlePhoneCall } from "../../../../../lib/calls/phone.ts";
export const runtime = "nodejs";
export async function POST(request: Request) { return handlePhoneCall(request, "end"); }
