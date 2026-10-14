import { NextResponse } from "next/server";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Adds the email to MailerLite when MAILERLITE_API_KEY is set (and to MAILERLITE_GROUP_ID if given).
// Every signup is also logged, so nothing is lost before a provider is configured.
export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
  const who = typeof body?.who === "string" ? body.who.slice(0, 100) : undefined;

  if (!EMAIL_RE.test(email) || email.length > 254) {
    return NextResponse.json({ error: "Please enter a valid email address." }, { status: 400 });
  }

  console.log(JSON.stringify({ event: who ? "waitlist_who" : "waitlist_signup", email, who, at: new Date().toISOString() }));

  const apiKey = process.env.MAILERLITE_API_KEY;
  if (apiKey && !who) {
    const groupId = process.env.MAILERLITE_GROUP_ID;
    const res = await fetch("https://connect.mailerlite.com/api/subscribers", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({ email, ...(groupId ? { groups: [groupId] } : {}) }),
    });
    if (!res.ok) {
      console.error("MailerLite error", res.status, await res.text().catch(() => ""));
      return NextResponse.json({ error: "We couldn't add you just now. Please try again." }, { status: 502 });
    }
  }

  return NextResponse.json({ ok: true });
}
