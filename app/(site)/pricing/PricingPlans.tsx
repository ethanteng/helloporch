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
  "One-press calling with a big-button corded phone",
  "Caregiver controls and privacy settings",
];
const dollars = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

export default function PricingPlans() {
  const [annual, setAnnual] = useState(false);
  const [tablets, setTablets] = useState(1);
  const monthly = 39 + (tablets - 1) * 30;
  const yearly = monthly * 11;
  const scope = tablets === 1 ? "1 tablet for your loved one" : `${tablets} tablets for your loved ones`;

  return (
    <>
      <div className={styles.billingToggle} role="group" aria-label="Billing frequency">
        <button type="button" aria-pressed={!annual} onClick={() => setAnnual(false)}>Monthly</button>
        <button type="button" aria-pressed={annual} onClick={() => setAnnual(true)}>Annually <span>1 month free</span></button>
      </div>
      <section className={styles.plans} aria-label="Proposed Porch software subscription">
        <article className={styles.plan} aria-labelledby="porch-title">
          <div className={styles.planSummary}>
            <p className={styles.planLabel}>One plan, all features</p>
            <h2 id="porch-title">Porch</h2>
            <p className={styles.planDescription}>Calling, drop-ins and messages for your loved one’s tablet.</p>
            <p className={styles.price} aria-live="polite" aria-atomic="true"><span>{dollars.format(annual ? yearly : monthly)}</span><span className={styles.period}>/ {annual ? "year" : "month"}</span></p>
            <p className={styles.billing}>{annual ? `${dollars.format(yearly)} billed annually · Save ${dollars.format(monthly)} a year` : `${dollars.format(monthly)} billed monthly`}</p>
            <p className={styles.scope}><strong>{scope}</strong><br />Unlimited family members and their devices</p>
            <div className={styles.quantity} role="group" aria-label="Number of tablets">
              <button type="button" onClick={() => setTablets((count) => count - 1)} disabled={tablets === 1} aria-label="Remove one tablet">−</button>
              <output aria-live="polite">{tablets} {tablets === 1 ? "tablet" : "tablets"}</output>
              <button type="button" onClick={() => setTablets((count) => count + 1)} aria-label="Add one tablet">+</button>
            </div>
            <p className={styles.bundleNote}>Each additional tablet for a loved one is {annual ? "$330/year" : "$30/month"}.<br />All tablets share one bill and include the same features.</p>
            <a className={styles.button} href="/pilot">Join the pilot <Arrow /></a>
            <p className={styles.noPayment}>No payment today</p>
          </div>
          <div className={styles.featureBlock}>
            <h3 className={styles.featureHeading}>Included with every tablet</h3>
            <ul className={styles.features}>{features.map((feature) => <li key={feature}><span aria-hidden="true" className={styles.check}>✓</span><span>{feature}</span></li>)}</ul>
            <p className={styles.planFootnote}>Family members use the Porch app free on iPhone or Android. You choose who can call and who may drop in.</p>
          </div>
        </article>
      </section>
      <p className={styles.belowPlans}>Use your own iPad or Android tablet and home Wi-Fi. Hardware isn’t included.</p>
    </>
  );
}

function Arrow() {
  return <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
