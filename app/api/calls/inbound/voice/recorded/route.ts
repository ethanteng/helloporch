import { after } from "next/server";
import { handleTwilioVoice } from "../../../../../../lib/family/voicemail.ts";

export const runtime = "nodejs";
// A greeting that isn't ready in time finishes recording after Twilio has its answer.
export async function POST(request: Request) { return handleTwilioVoice(request, "recorded", { afterResponse: after }); }
