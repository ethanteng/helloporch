"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import PorchLogo from "@/components/PorchLogo";
import { androidDevice, appLink, codeFromHash, inviteLink, type InviteKind } from "@/lib/invite-links";
import styles from "./InviteLanding.module.css";

// Set on the website project. Without it, the page asks for the link from whoever sent the invitation.
const testFlight = process.env.NEXT_PUBLIC_TESTFLIGHT_URL;
// Porch's Google Play testing page, once Porch for Android is in testing. Until then, Android visitors are told it isn't ready.
const playTesting = process.env.NEXT_PUBLIC_PLAY_TESTING_URL;

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
    paste: "In Porch, tap Set up Porch for someone and paste it into Setup link.",
    copyLabel: "Copy setup link",
  },
} as const;
const androidBedside = {
  lede: "Open this page on the tablet that will stay with them. This link sets up one tablet.",
  needs: ["A tablet with Android 15 or later, and Wi-Fi.",
    "A Cell2Jack, and a corded phone set to tone dialing, such as a big-button picture phone. A USB hub keeps the tablet charging with it plugged in. You can connect the phone later."],
};

/** The page an invitation link opens when Porch isn't installed yet, or isn't opened by the link. */
export default function InviteLanding({ kind }: { kind: InviteKind }) {
  const text = copy[kind];
  // Unknown until the page has read its link; null when the link has no code.
  const [code, setCode] = useState<string | null>();
  const [copied, setCopied] = useState(false);
  // Read after the page loads, so the page first shows what it shows on an iPhone or iPad.
  const [android, setAndroid] = useState<"phone" | "tablet">();
  useEffect(() => {
    // Read after paint. Chrome's reduced user agent says "Mobile" on tablets; the client hint does not.
    // The DOM lib this repo typechecks with does not declare userAgentData.
    const hints = navigator as Navigator & { userAgentData?: { mobile: boolean } };
    const form = androidDevice(navigator.userAgent, hints.userAgentData?.mobile);
    if (form) setAndroid(form);
  }, []);
  // Until Porch for Android is in testing, an Android visitor reads what an iPhone or iPad does, and that it isn't ready.
  const androidReady = !!android && !!playTesting;
  const device = !androidReady ? text.device : kind === "bedside" ? "tablet" : android;
  useEffect(() => {
    const hash = window.location.hash;
    // Without a hash, keep a code already read: React can run this twice, after the first run cleared it.
    if (!hash) { setCode(current => current ?? null); return; }
    setCode(codeFromHash(hash) ?? null);
    // The code stays in this page only: off the address bar and out of the history.
    history.replaceState(null, "", window.location.pathname);
  }, []);
  const link = code ? appLink(kind, code) : undefined;
  // The page's own address no longer has the code, so this is how the link moves to another device.
  const webLink = code ? inviteLink(kind, code) : undefined;
  const copyLink = async (value = link) => {
    if (!value) return;
    try { await navigator.clipboard.writeText(value); setCopied(true); } catch { setCopied(false); }
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
        <p className={styles.lede}>{androidReady && kind === "bedside" ? androidBedside.lede : text.lede}</p>

        {kind === "bedside" && (
          <section className={styles.needs} aria-labelledby="needs-title">
            <h2 id="needs-title">What you need</h2>
            <ul>
              {androidReady ? androidBedside.needs.map(need => <li key={need}>{need}</li>) : <>
                <li>An iPad with an M-series chip (M1 or later), and Wi-Fi.</li>
                <li>A Cell2Jack, and a corded phone set to tone dialing, such as a big-button picture phone. You can connect the phone later.</li>
              </>}
            </ul>
          </section>
        )}

        {code === null ? (
          <p className={styles.problem} role="alert">This link is incomplete. Ask whoever sent it for a new one.</p>
        ) : android && !playTesting ? (
          <>
            <p className={styles.problem} role="alert">Porch isn&rsquo;t on Android yet. Open this link on {kind === "bedside" ? "an iPad" : "an iPhone or iPad"} instead, or ask whoever sent it.</p>
            <button type="button" className={`${styles.secondary} ${styles.afterProblem}`} onClick={() => copyLink(webLink)} disabled={!webLink}>{copied ? "Copied" : "Copy this link"}</button>
          </>
        ) : (
          <ol className={styles.steps}>
            <li>
              <h2>Get Porch</h2>
              {androidReady ? <>
                <p>Porch for Android is in testing on Google Play. On this {device}, join the test, then install Porch.</p>
                <a className={styles.primary} href={playTesting}>Get Porch on Google Play</a>
              </> : <>
                <p>Porch is in beta through Apple&rsquo;s TestFlight app. On this {device}, install TestFlight, then Porch.</p>
                {testFlight ? <a className={styles.primary} href={testFlight}>Get Porch on TestFlight</a>
                  : <p className={styles.note}>Ask whoever sent this link for the link to get Porch.</p>}
              </>}
            </li>
            <li>
              <h2>Open it in Porch</h2>
              <p>If Porch is already on this {device}, the link you tapped opens it. Once Porch is installed, tap here.</p>
              <a className={styles.primary} href={link} aria-disabled={!link}>{text.open}</a>
            </li>
            <li>
              <h2>Or paste it</h2>
              <p>{text.paste}</p>
              <button type="button" className={styles.secondary} onClick={() => copyLink()} disabled={!link}>{copied ? "Copied" : text.copyLabel}</button>
            </li>
          </ol>
        )}
      </main>
    </div>
  );
}
