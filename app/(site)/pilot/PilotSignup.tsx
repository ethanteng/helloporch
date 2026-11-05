"use client";

import { useId, useState, type FormEvent } from "react";
import { Honeypot } from "@/components/Honeypot";
import styles from "./pilot.module.css";

type Tablet = "ipad" | "android" | "unsure";

const TABLETS: { value: Tablet; label: string }[] = [
  { value: "ipad", label: "iPad" },
  { value: "android", label: "Android tablet" },
  { value: "unsure", label: "Not sure yet" },
];

// The pilot sign-up: an email and which tablet their family member will use. /api/pilot saves it to MailerLite.
export default function PilotSignup() {
  const id = useId();
  const [tablet, setTablet] = useState<Tablet>("ipad");
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
        body: JSON.stringify({ email, tablet, website: form.get("website") ?? "" }),
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
          I’ll email you at <strong>{joined}</strong> to check your tablet and send everything you need to set it up.
        </p>
      </div>
    );
  }

  return (
    <form className={styles.form} onSubmit={onSubmit}>
      <fieldset className={styles.choice}>
        <legend>Their tablet</legend>
        {TABLETS.map((t) => (
          <label key={t.value}>
            <input
              type="radio"
              name={`${id}-tablet`}
              value={t.value}
              checked={tablet === t.value}
              onChange={() => setTablet(t.value)}
            />
            <span>{t.label}</span>
          </label>
        ))}
      </fieldset>
      <div className={styles.emailRow}>
        <input id={`${id}-email`} name="email" type="email" required placeholder="Your email address" aria-label="Your email address" autoComplete="email" />
        <Honeypot />
        <button type="submit" disabled={pending}>
          {pending ? "Joining…" : "Join the pilot"}
        </button>
      </div>
      {error ? (
        <p className={styles.error} role="alert">
          {error}
        </p>
      ) : null}
    </form>
  );
}
