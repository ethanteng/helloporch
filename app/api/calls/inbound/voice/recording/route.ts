import { handleTwilioVoice } from "../../../../../../lib/family/voicemail.ts";

export const runtime = "nodejs";
export async function POST(request: Request) { return handleTwilioVoice(request, "recording"); }
