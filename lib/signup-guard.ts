import { checkBotId } from "botid/server";

/** Why the pilot and waitlist routes turn a sign-up away. `honeypot`: something filled in the hidden field
 * (components/Honeypot.tsx), as bots that fill in every field do. The route answers as if it worked, so the bot learns
 * nothing. `bot`: BotID says the request didn't come from a person in a real browser, which catches headless browsers
 * and scripts posting straight to the route. A route has to be listed in instrumentation-client.ts for the browser to
 * send BotID its proof. */
export type Blocked = "honeypot" | "bot";

export async function blockedSignup(honeypot: unknown): Promise<Blocked | null> {
  if (typeof honeypot === "string" && honeypot.trim()) return "honeypot";
  try {
    if ((await checkBotId()).isBot) return "bot";
  } catch (error) {
    // BotID couldn't decide, say without an OIDC token. Losing a real family is worse than letting a bot through.
    console.error("BotID check failed", error);
  }
  return null;
}
