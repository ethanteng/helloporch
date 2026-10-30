const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// How the family member will call, as it reads in MailerLite.
const INTERFACES = { touch: "touchscreen", phone: "big-button phone" } as const;

// Signs a family up for the pilot from the pilot page. Adds them to MailerLite when MAILERLITE_API_KEY is set,
// in MAILERLITE_PILOT_GROUP_ID if given, with their answers in the porch_pilot_interface and porch_pilot_ipad
// fields, so the families waiting for the big-button phone can be emailed together once Apple approves it.
// MailerLite upserts by email, so sending changed answers updates them. Every request is also logged, as the
// waitlist does, but function logs expire quickly, so MailerLite is the real record.
export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  const choice: keyof typeof INTERFACES | undefined =
    typeof body?.interface === "string" && Object.hasOwn(INTERFACES, body.interface) ? body.interface : undefined;
  const ipad = typeof body?.ipad === "boolean" ? body.ipad : undefined;

  if (!EMAIL_RE.test(email) || email.length > 254) {
    return Response.json({ error: "Please enter a valid email address." }, { status: 400 });
  }
  if (!choice || ipad === undefined || body?.agreed !== true) {
    return Response.json({ error: "Please answer every step and agree to the pilot." }, { status: 400 });
  }

  const fields = { porch_pilot_interface: INTERFACES[choice], porch_pilot_ipad: ipad ? "yes" : "no" };
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
