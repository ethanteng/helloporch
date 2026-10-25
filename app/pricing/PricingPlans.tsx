"use client";

import { useState } from "react";
import styles from "./pricing.module.css";

const sharedFeatures = [
  "Unlimited Porch audio and video calls",
  "Unlimited approved audio and video drop-ins",
  "One-press calling with touch or a keypad",
  "Caregiver controls and privacy settings",
  "Bedside clock and built-in announcement voices",
];

export default function PricingPlans() {
  const [annual, setAnnual] = useState(false);
  return (
    <>
      <div className={styles.billingToggle} role="group" aria-label="Billing frequency">
        <button type="button" aria-pressed={!annual} onClick={() => setAnnual(false)}>Pay monthly</button>
        <button type="button" aria-pressed={annual} onClick={() => setAnnual(true)}>Pay annually <span>Save about 10%</span></button>
      </div>
      <p className={styles.screenReaderOnly} role="status">{annual ? "Annual billing selected. Starter is 108 dollars per year; Family is 420 dollars per year; Family plus Phone is 528 dollars per year." : "Monthly billing selected. Starter is 9 dollars and 99 cents per month; Family is 39 dollars per month; Family plus Phone is 49 dollars per month."}</p>
      <section className={styles.plans} aria-label="Proposed software plans">
        <article className={`${styles.plan} ${styles.starter}`} aria-labelledby="starter-title">
          <div className={styles.planTop}>
            <span className={styles.planLabel}>A close circle</span>
            <h2 id="starter-title">Porch Starter</h2>
            <p className={styles.price}><span>{annual ? "$9" : "$9.99"}</span><span className={styles.period}>/ month</span></p>
            <p className={styles.billing}>{annual ? "$108 billed annually · Save $11.88 a year" : "$9.99 billed monthly"}</p>
            <p className={styles.planDescription}>For your loved one, you, and one more familiar face.</p>
            <p className={styles.scope}>1 bedside iPad<br /><strong>2 Porch contacts</strong></p>
          </div>
          <a className={`${styles.button} ${styles.primaryButton}`} href="#join">Join the waitlist <Arrow /></a>
          <p className={styles.noPayment}>No payment today</p>
          <div className={styles.featureBlock}>
            <p className={styles.featureHeading}>The everyday essentials</p>
            <FeatureList features={sharedFeatures} />
          </div>
          <p className={styles.planFootnote}>The two contacts you choose can change whenever you need.</p>
        </article>

        <article className={`${styles.plan} ${styles.family}`} aria-labelledby="family-title">
          <div className={styles.planTop}>
            <span className={styles.planLabel}>Bring everyone closer</span>
            <h2 id="family-title">Porch Family</h2>
            <p className={styles.price}><span>{annual ? "$35" : "$39"}</span><span className={styles.period}>/ month</span></p>
            <p className={styles.billing}>{annual ? "$420 billed annually · Save $48 a year" : "$39 billed monthly"}</p>
            <p className={styles.planDescription}>More familiar faces. Little messages between the calls.</p>
            <p className={styles.scope}>1 bedside iPad<br /><strong>Up to 10 Porch contacts</strong></p>
          </div>
          <a className={`${styles.button} ${styles.secondaryButton}`} href="#join">Join the waitlist <Arrow /></a>
          <p className={styles.noPayment}>No payment today</p>
          <div className={styles.featureBlock}>
            <p className={styles.featureHeading}>Everything in Starter, plus</p>
            <FeatureList features={[
              "Room for up to 10 Porch contacts",
              "Recorded audio and video messages",
              "Messages from the bedside when a call is missed",
              "Caregiver-approved message autoplay",
            ]} />
          </div>
          <p className={styles.planFootnote}>Family members use the Porch app at no extra charge.</p>
        </article>

        <article className={`${styles.plan} ${styles.withPhone}`} aria-labelledby="phone-title">
          <div className={styles.planTop}>
            <span className={styles.planLabel}>Porch and regular phones</span>
            <h2 id="phone-title">Family + Phone</h2>
            <p className={styles.price}><span>{annual ? "$44" : "$49"}</span><span className={styles.period}>/ month</span></p>
            <p className={styles.billing}>{annual ? "$528 billed annually · Save $60 a year" : "$49 billed monthly"}</p>
            <p className={styles.planDescription}>The whole family on Porch, with regular phone calls included.</p>
            <p className={styles.scope}>1 bedside iPad<br /><strong>Up to 10 Porch contacts</strong></p>
          </div>
          <a className={`${styles.button} ${styles.secondaryButton}`} href="#join">Join the waitlist <Arrow /></a>
          <p className={styles.noPayment}>No payment today</p>
          <div className={styles.featureBlock}>
            <p className={styles.featureHeading}>Everything in Family, plus</p>
            <FeatureList features={[
              "A household phone number",
              "Incoming calls from regular phones",
              "Phone fallback when Porch isn’t answered",
              "Telephone voicemail",
              "200 telephone minutes each month",
            ]} />
          </div>
          <p className={styles.planFootnote}>Telephone minutes are shared across incoming and outgoing calls. Additional usage pricing is still being worked out.</p>
        </article>
      </section>

      <p className={styles.belowPlans}>Unlimited Porch app calls and drop-ins on all three plans. Regular-phone calls use the telephone allowance. Your iPad and accessories are separate.</p>
    </>
  );
}

function FeatureList({ features }: { features: string[] }) {
  return <ul className={styles.features}>{features.map((feature) => <li key={feature}><span aria-hidden="true" className={styles.check}>✓</span><span>{feature}</span></li>)}</ul>;
}

function Arrow() {
  return <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
