import type { Metadata } from "next";
import Link from "next/link";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import PricingPlans from "./PricingPlans";
import styles from "./pricing.module.css";

export const metadata: Metadata = {
  title: "Pricing Preview | HelloPorch",
  description: "One HelloPorch software plan: $39 a month for one loved-one iPad, with unlimited family members, Porch calls, drop-ins and regular phone calls. Add another loved-one iPad for $30 a month.",
  robots: { index: false, follow: false },
};

const questions = [
  {
    question: "What does one subscription cover?",
    answer: "The $39 monthly subscription covers one loved one’s iPad and every Porch feature. Invite as many family members as you like; they can connect from their own devices at no extra charge.",
  },
  {
    question: "Do family members pay separately?",
    answer: "No. Family members connect from their own devices at no extra charge. There are no per-person fees or paid feature upgrades.",
  },
  {
    question: "Is there a calling-minute limit?",
    answer: "No. The proposed plan includes unlimited Porch audio and video calls, approved drop-ins, and regular phone calls, with no monthly minute allowance or automatic call-length cutoff.",
  },
  {
    question: "What if I have more than one loved one?",
    answer: "Add another loved-one iPad for $30 a month, or $330 a year with annual billing. Two iPads are $69 a month or $759 a year; three are $99 a month or $1,089 a year. Every iPad gets the same features, and your family receives one bill.",
  },
  {
    question: "Does the price include an iPad or a keypad?",
    answer: "No. This is a software subscription. You’ll need a compatible iPad, home Wi-Fi and a USB number pad, or a big-button phone once Apple approves it. Our pilot guide lists the equipment and which iPads work with it.",
  },
  {
    question: "What happens if we replace the iPad?",
    answer: "Move the existing subscription to the replacement iPad. Replacing a loved one’s device doesn’t mean buying another subscription.",
  },
  {
    question: "How does annual billing work?",
    answer: "Annual billing includes twelve months of service for the price of eleven. One loved-one iPad is $429 a year, paid once annually. Each additional loved-one iPad is $330 a year. The monthly option starts at $39, plus $30 for each additional iPad.",
  },
  {
    question: "Can I subscribe today?",
    answer: "Not yet. This is a preview of the pricing we’re considering while Porch is in its pilot. Join the waitlist for launch updates. There’s no payment or subscription when you join, and final pricing and availability may change.",
  },
];

export default function PricingPage() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav />
        <main id="main-content" className={styles.main}>
          <header className={styles.hero}>
            <span className="hero__badge">Pricing preview</span>
            <h1 className={styles.title}>Porch for <em>your family.</em></h1>
            <p className={styles.lede}>One subscription for your loved one’s iPad. Family members can call from their own devices at no extra charge.</p>
            <p className={styles.previewNote}>Proposed software pricing · Porch is currently in its pilot</p>
          </header>

          <PricingPlans />

          <section className={styles.included} aria-labelledby="included-title">
            <h2 id="included-title">Calling and <em>privacy.</em></h2>
            <div className={styles.promises}>
              <div><span className={styles.promiseNumber} aria-hidden="true">1</span><h3>One-press calling</h3><p>Start a call with a USB number pad or a big-button phone.</p></div>
              <div><span className={styles.promiseNumber} aria-hidden="true">2</span><h3>Control who can connect</h3><p>Manage contacts and choose who may start an audio or video drop-in.</p></div>
              <div><span className={styles.promiseNumber} aria-hidden="true">3</span><h3>No call-length limits</h3><p>Talk for as long as you like, with no monthly minute allowance or automatic cutoff.</p></div>
            </div>
          </section>

          <section className={styles.faq} aria-labelledby="faq-title">
            <div className={styles.faqIntro}>
              <h2 id="faq-title">About the <em>subscription.</em></h2>
              <p>For help choosing an iPad or keypad, read our setup guide.</p>
              <Link href="/pilot">See the setup guide <Arrow /></Link>
            </div>
            <div className={styles.questions}>
              {questions.map(({ question, answer }) => (
                <details key={question} className={styles.question}>
                  <summary>{question}<span aria-hidden="true" className={styles.plus}>+</span></summary>
                  <p>{answer}</p>
                </details>
              ))}
            </div>
          </section>

          <section id="join" className={styles.join} aria-labelledby="join-title">
            <h2 id="join-title">Get <em>launch updates.</em></h2>
            <p>Leave your email and we’ll let you know when subscriptions are available.</p>
            <div className={styles.signup}><JoinWaitlist /></div>
            <p className={styles.joinNote}>Porch is currently in its pilot. Joining the waitlist is free and doesn’t start a subscription.</p>
          </section>
        </main>
        <SiteFooter />
      </div>
    </WaitlistProvider>
  );
}

function Arrow() {
  return <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
