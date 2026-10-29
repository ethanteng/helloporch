"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import PorchLogo from "@/components/PorchLogo";
import { appLink, codeFromHash, type InviteKind } from "@/lib/invite-links";
import styles from "./InviteLanding.module.css";

// Set on the website project. Without it, the page asks for the link from whoever sent the invitation.
const testFlight = process.env.NEXT_PUBLIC_TESTFLIGHT_URL;

const copy = {
  family: {
    title: "You're invited to a family's Porch",
    lede: "Porch lets you call your loved one's bedside iPad, and drop in when their caregiver allows it. This invitation works once, for 24 hours.",
    device: "phone",
    open: "Open invitation in Porch",
    paste: "In Porch, choose Join a family and paste it.",
    copyLabel: "Copy invitation",
  },
  bedside: {
    title: "Set up Porch for someone you love",
    lede: "Open this page on the iPad that will stay with them. This link sets up one iPad.",
    device: "iPad",
    open: "Open setup in Porch",
    paste: "In Porch, tap the gear and paste it into Bedside activation link.",
    copyLabel: "Copy setup link",
  },
} as const;

/** The page an invitation link opens when Porch isn't installed yet, or isn't opened by the link. */
export default function InviteLanding({ kind }: { kind: InviteKind }) {
  const text = copy[kind];
  // Unknown until the page has read its link; null when the link has no code.
  const [code, setCode] = useState<string | null>();
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    const hash = window.location.hash;
    // Without a hash, keep a code already read: React can run this twice, after the first run cleared it.
    if (!hash) { setCode(current => current ?? null); return; }
    setCode(codeFromHash(hash) ?? null);
    // The code stays in this page only: off the address bar and out of the history.
    history.replaceState(null, "", window.location.pathname);
  }, []);
  const link = code ? appLink(kind, code) : undefined;
  const copyLink = async () => {
    if (!link) return;
    try { await navigator.clipboard.writeText(link); setCopied(true); } catch { setCopied(false); }
  };

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link href="/" className="logo" aria-label="HelloPorch home">
          <PorchLogo />
        </Link>
      </header>
      <main className={styles.card}>
        <h1 className={styles.title}>{text.title}</h1>
        <p className={styles.lede}>{text.lede}</p>

        {kind === "bedside" && (
          <section className={styles.needs} aria-labelledby="needs-title">
            <h2 id="needs-title">What you need</h2>
            <ul>
              <li>An iPad with an M-series chip (M1 or later), and Wi-Fi.</li>
              <li>A Cell2Jack, and a corded phone set to tone dialing, such as a big-button picture phone. You can connect the phone later.</li>
            </ul>
          </section>
        )}

        {code === null ? (
          <p className={styles.problem} role="alert">This link is incomplete. Ask whoever sent it for a new one.</p>
        ) : (
          <ol className={styles.steps}>
            <li>
              <h2>Get Porch</h2>
              <p>Porch is in beta through Apple&rsquo;s TestFlight app. On this {text.device}, install TestFlight, then Porch.</p>
              {testFlight ? <a className={styles.primary} href={testFlight}>Get Porch on TestFlight</a>
                : <p className={styles.note}>Ask whoever sent this link for the link to get Porch.</p>}
            </li>
            <li>
              <h2>Open it in Porch</h2>
              <p>If Porch is already on this {text.device}, the link you tapped opens it. Once Porch is installed, tap here.</p>
              <a className={styles.primary} href={link} aria-disabled={!link}>{text.open}</a>
            </li>
            <li>
              <h2>Or paste it</h2>
              <p>{text.paste}</p>
              <button type="button" className={styles.secondary} onClick={copyLink} disabled={!link}>{copied ? "Copied" : text.copyLabel}</button>
            </li>
          </ol>
        )}
      </main>
    </div>
  );
}
