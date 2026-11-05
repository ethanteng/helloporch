import { blockedSignup } from "../../../lib/signup-guard.ts";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Which tablet the family member will use, as it reads in MailerLite.
const TABLETS = { ipad: "ipad", android: "android", unsure: "not sure" } as const;

// Signs a family up for the pilot from the pilot page: their email and which tablet their family member will use.
// Adds them to MailerLite when MAILERLITE_API_KEY is set, in MAILERLITE_PILOT_GROUP_ID if given. The big-button
// corded phone is the only way to call now, so porch_pilot_interface is always "big-button phone", and the tablet
// goes in the existing porch_pilot_ipad field ("ipad", "android" or "not sure"); families who signed up with the
// old survey keep its answers there ("yes" or "no" for a compatible iPad). MailerLite upserts by email, so signing up
// again updates the answer. Every request is also logged, as the waitlist does, but function logs expire quickly, so
// MailerLite is the real record. Bots are logged and kept out of MailerLite (lib/signup-guard.ts), so nobody whose
// email a bot typed in hears from us.
export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  const tablet: keyof typeof TABLETS | undefined =
    typeof body?.tablet === "string" && Object.hasOwn(TABLETS, body.tablet) ? body.tablet : undefined;

  if (!EMAIL_RE.test(email) || email.length > 254) {
    return Response.json({ error: "Please enter a valid email address." }, { status: 400 });
  }
  if (!tablet) {
    return Response.json({ error: "Please choose the tablet they'll use." }, { status: 400 });
  }
  const fields = { porch_pilot_interface: "big-button phone", porch_pilot_ipad: TABLETS[tablet] };

  const blocked = await blockedSignup(body?.website);
  if (blocked) {
    console.log(JSON.stringify({ event: "pilot_blocked", reason: blocked, email, at: new Date().toISOString() }));
    return blocked === "bot"
      ? Response.json({ error: "We couldn't sign you up just now. Please try again." }, { status: 403 })
      : Response.json({ ok: true });
  }

  console.log(JSON.stringify({ event: "pilot_signup", email, ...fields, at: new Date().toISOString() }));

  const apiKey = process.env.MAILERLITE_API_KEY;
  if (apiKey) {
    const groupId = process.env.MAILERLITE_PILOT_GROUP_ID;
    const res = await fetch("https://connect.mailerlite.com/api/subscribers", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({ email, fields, ...(groupId ? { groups: [groupId] } : {}) }),
    });
    if (!res.ok) {
      console.error("MailerLite error", res.status, await res.text().catch(() => ""));
      return Response.json({ error: "We couldn't sign you up just now. Please try again." }, { status: 502 });
    }
  }

  return Response.json({ ok: true });
}
