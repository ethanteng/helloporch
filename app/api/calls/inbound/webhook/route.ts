import { handleInboundWebhook } from "../../../../../lib/family/inbound.ts";

export const runtime = "nodejs";
export async function POST(request: Request) { return handleInboundWebhook(request); }
