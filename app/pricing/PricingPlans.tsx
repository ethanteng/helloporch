"use client";

import { useState } from "react";
import styles from "./pricing.module.css";

const features = [
  "Unlimited family members, at no extra charge",
  "Unlimited Porch audio and video calls",
  "Unlimited approved audio and video drop-ins",
  "Regular phone calls and a phone number included",
  "No minute allowances or call-length limits",
  "Audio and video messages, plus telephone voicemail",
  "One-press calling with touch or a compatible keypad",
  "Caregiver controls and privacy settings",
];
const dollars = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

export default function PricingPlans() {
  const [annual, setAnnual] = useState(false);
  const [ipads, setIpads] = useState(1);
  const monthly = 39 + (ipads - 1) * 30;
  const yearly = monthly * 11;
  const scope = `${ipads} loved-one ${ipads === 1 ? "iPad" : "iPads"}`;

  return (
    <>
      <div className={styles.billingToggle} role="group" aria-label="Billing frequency">
        <button type="button" aria-pressed={!annual} onClick={() => setAnnual(false)}>Pay monthly</button>
        <button type="button" aria-pressed={annual} onClick={() => setAnnual(true)}>Pay annually <span>1 month free</span></button>
      </div>
      <section className={styles.plans} aria-label="Proposed Porch software subscription">
        <article className={styles.plan} aria-labelledby="porch-title">
          <div className={styles.planSummary}>
            <span className={styles.planLabel}>One plan. The whole family.</span>
            <h2 id="porch-title">Porch</h2>
            <p className={styles.planDescription}>For the iPad beside someone you love.<br />Every way to stay close, included.</p>
            <p className={styles.price} aria-live="polite" aria-atomic="true"><span>{dollars.format(annual ? yearly : monthly)}</span><span className={styles.period}>/ {annual ? "year" : "month"}</span></p>
            <p className={styles.billing}>{annual ? `${dollars.format(yearly)} billed annually · Save ${dollars.format(monthly)} a year` : `${dollars.format(monthly)} billed monthly`}</p>
            <p className={styles.scope}><strong>{scope}</strong><br />Unlimited family members and their devices</p>
            <div className={styles.quantity} role="group" aria-label="Number of loved-one iPads">
              <button type="button" onClick={() => setIpads((count) => count - 1)} disabled={ipads === 1} aria-label="Remove one loved-one iPad">−</button>
              <output aria-live="polite">{ipads} {ipads === 1 ? "iPad" : "iPads"}</output>
              <button type="button" onClick={() => setIpads((count) => count + 1)} aria-label="Add one loved-one iPad">+</button>
            </div>
            <p className={styles.bundleNote}>Another loved one? Add an iPad for {annual ? "$330/year" : "$30/month"}.<br />Same plan. Every feature. One bill.</p>
            <a className={`${styles.button} ${styles.primaryButton}`} href="#join">Join the waitlist <Arrow /></a>
            <p className={styles.noPayment}>No payment today</p>
          </div>
          <div className={styles.featureBlock}>
            <p className={styles.featureHeading}>Everything is included</p>
            <ul className={styles.features}>{features.map((feature) => <li key={feature}><span aria-hidden="true" className={styles.check}>✓</span><span>{feature}</span></li>)}</ul>
            <p className={styles.planFootnote}>Family members connect free from their own devices. You choose who can call and who may drop in.</p>
          </div>
        </article>
      </section>
      <p className={styles.belowPlans}>Software only. Bring your own compatible iPad and Wi-Fi. iPads and accessories are sold separately.</p>
    </>
  );
}

function Arrow() {
  return <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
