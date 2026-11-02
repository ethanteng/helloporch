import { handleTwilioText } from "../../../../../lib/family/texts.ts";

export const runtime = "nodejs";
export async function POST(request: Request) { return handleTwilioText(request); }
