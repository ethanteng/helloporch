"use client";

import { useId, useState, type FormEvent } from "react";
import { Honeypot } from "@/components/Honeypot";
import styles from "./pilot.module.css";

// The pilot sign-up: just an email. /api/pilot saves it to MailerLite.
export default function PilotSignup() {
  const id = useId();
  const [joined, setJoined] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    setPending(true);
    setError(null);
    try {
      const res = await fetch("/api/pilot", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, website: form.get("website") ?? "" }),
      });
      if (!res.ok) throw new Error((await res.json().catch(() => null))?.error || "Something went wrong. Please try again.");
      setJoined(email);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong. Please try again.");
    } finally {
      setPending(false);
    }
  }

  if (joined) {
    return (
      <div className={styles.thanks} role="status">
        <p className={styles.thanksTitle}>Thank you. You’re in the pilot.</p>
        <p>
          I’ll email you at <strong>{joined}</strong> with an invitation and everything you need to set it up.
        </p>
      </div>
    );
  }

  return (
    <form className={styles.form} onSubmit={onSubmit}>
      <div className={styles.emailRow}>
        <input id={`${id}-email`} name="email" type="email" required placeholder="Your email address" aria-label="Your email address" autoComplete="email" />
        <Honeypot />
        <button type="submit" disabled={pending}>
          {pending ? "Sending…" : "Request a pilot invite"}
        </button>
      </div>
      <p className={styles.formNote}>Just your email for now. I’ll be in touch with next steps.</p>
      {error ? (
        <p className={styles.error} role="alert">
          {error}
        </p>
      ) : null}
    </form>
  );
}
