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
    answer: "The $39 monthly subscription covers one loved one’s bedside iPad and every Porch feature. Invite as many family members as you like. Their devices don’t count as extra bedside iPads.",
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
    answer: "These are software subscriptions. You bring a compatible iPad, home Wi-Fi and, if you want one, a keypad. The touchscreen works too. Our pilot guide explains the equipment options and which iPads work with them.",
  },
  {
    question: "What happens if we replace the iPad?",
    answer: "Move the existing subscription to the replacement iPad. Replacing a loved one’s device doesn’t mean buying another subscription.",
  },
  {
    question: "How does annual billing work?",
    answer: "Pay for eleven months and get twelve. One loved-one iPad is $429 a year, paid once annually. Each additional loved-one iPad is $330 a year. The monthly option starts at $39, plus $30 for each additional iPad.",
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
            <span className={styles.preview}>A first look at pricing</span>
            <h1>A little closer.<br />{" "}<em>Every day.</em></h1>
            <p className={styles.lede}>One simple subscription for their bedside iPad.<br className={styles.desktopBreak} /> More ways to be there for someone you love.</p>
            <p className={styles.previewNote}>Proposed software pricing · Porch is currently in its pilot</p>
          </header>

          <PricingPlans />

          <section className={styles.included} aria-labelledby="included-title">
            <p className={styles.eyebrow}>Included for everyone</p>
            <h2 id="included-title">Easy to use.<br /><em>Yours to control.</em></h2>
            <div className={styles.promises}>
              <div><span className={styles.promiseNumber}>01</span><h3>A simpler way to call</h3><p>One press starts a call. Use the touchscreen or add a compatible keypad.</p></div>
              <div><span className={styles.promiseNumber}>02</span><h3>Your family, your say</h3><p>You choose who can connect and which contacts may drop in with audio or video.</p></div>
              <div><span className={styles.promiseNumber}>03</span><h3>Room for real conversations</h3><p>No minute allowances or call-length limits. Stay for another story.</p></div>
            </div>
          </section>

          <section className={styles.faq} aria-labelledby="faq-title">
            <div className={styles.faqIntro}>
              <p className={styles.eyebrow}>A few things to know</p>
              <h2 id="faq-title">Let’s make<br /><em>it simple.</em></h2>
              <p>Wondering about the iPad or keypad?</p>
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
            <p className={styles.joinEyebrow}>A little more connection starts here</p>
            <h2 id="join-title">Be there.<br /><em>Even from here.</em></h2>
            <p>Join the waitlist for Porch updates and news about our launch plans.</p>
            <div className={styles.signup}><JoinWaitlist /></div>
            <p className={styles.joinNote}>No payment. No commitment. Just a place on the list.</p>
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
