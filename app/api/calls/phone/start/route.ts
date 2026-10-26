import { after } from "next/server";
import { handlePhoneCall } from "../../../../../lib/calls/phone.ts";
export const runtime = "nodejs";
// The call's history is saved once the iPad has its answer.
export async function POST(request: Request) { return handlePhoneCall(request, "start", { afterResponse: after }); }
