import { after } from "next/server";
import { handleInboundWebhook } from "../../../../../lib/family/inbound.ts";

export const runtime = "nodejs";
// The previous call's history is saved after the bedside has been rung.
export async function POST(request: Request) { return handleInboundWebhook(request, { afterResponse: after }); }
