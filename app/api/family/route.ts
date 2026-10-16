import { handleFamily } from "../../../lib/family/service.ts";
export const runtime = "nodejs";
export async function POST(request: Request) { return handleFamily(request); }
