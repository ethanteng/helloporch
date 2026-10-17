import { callingHealth } from "../../../../lib/calls/health.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 15;
export async function GET() { return callingHealth(); }
