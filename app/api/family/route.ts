import { after } from "next/server";
import { handleFamily } from "../../../lib/family/service.ts";
export const runtime = "nodejs";
// Setting up a Porch number makes several Twilio and LiveKit requests, each allowed up to 15 seconds.
export const maxDuration = 60;
// A number that couldn't be set up yet is tried again after the bedside's poll is answered.
export async function POST(request: Request) { return handleFamily(request, { afterResponse: after }); }
