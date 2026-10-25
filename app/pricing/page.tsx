import type { Metadata } from "next";
import Link from "next/link";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import PricingPlans from "./PricingPlans";
import styles from "./pricing.module.css";

export const metadata: Metadata = {
  title: "Pricing Preview | HelloPorch",
  description: "A first look at HelloPorch software plans. Unlimited Porch calls and drop-ins, starting at $9.99 a month for one bedside iPad and two contacts.",
  robots: { index: false, follow: false },
};

const questions = [
  {
    question: "What counts as a Porch contact?",
    answer: "A Porch contact is someone you invite to connect with the bedside iPad through the Porch app on their iPhone or iPad. Starter includes two contacts; Family and Family + Phone include up to ten. The bedside iPad doesn’t count toward that limit.",
  },
  {
    question: "Do family members pay separately?",
    answer: "No. One subscription covers the bedside iPad and the contacts included in your plan. Invited family members use the Porch app at no extra charge.",
  },
  {
    question: "Is there a calling-minute limit?",
    answer: "All three proposed plans include unlimited Porch app calls and drop-ins, with no monthly minute allowance or per-minute charges. Family + Phone also includes 200 telephone minutes each month for calls to and from regular phone numbers. Additional telephone usage pricing is still being worked out.",
  },
  {
    question: "What does Family + Phone include?",
    answer: "Everything in Family, plus a household phone number, incoming calls from regular phones, phone fallback when a Porch call isn’t answered, and telephone voicemail. The 200 telephone minutes are shared across incoming and outgoing calls each month, including when you pay annually. Unlimited Porch app calls and drop-ins don’t use that allowance.",
  },
  {
    question: "Does the price include an iPad or a keypad?",
    answer: "These are software subscriptions. You bring a compatible iPad, home Wi-Fi and, if you want one, a keypad. The touchscreen works too. Our pilot guide explains the equipment options and which iPads work with them.",
  },
  {
    question: "Can I change my two contacts?",
    answer: "Yes. Starter is designed for two active contacts, not two people you choose forever. A caregiver can remove a contact and invite someone else in their place.",
  },
  {
    question: "How does annual billing work?",
    answer: "The proposed annual Starter plan is $108 a year, equivalent to $9 a month. Family is $420 a year, equivalent to $35 a month. Family + Phone is $528 a year, equivalent to $44 a month. The full annual amount would be charged once a year. Monthly billing remains available.",
  },
  {
    question: "Can I subscribe today?",
    answer: "Not yet. This is a preview of the plans we’re considering while Porch is in its pilot. Join the waitlist for launch updates. There’s no payment or subscription when you join, and final plans and availability may change.",
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
            <p className={styles.previewNote}>Proposed software plans · Porch is currently in its pilot</p>
          </header>

          <PricingPlans />

          <section className={styles.included} aria-labelledby="included-title">
            <p className={styles.eyebrow}>On every plan</p>
            <h2 id="included-title">Easy to use.<br /><em>Yours to control.</em></h2>
            <div className={styles.promises}>
              <div><span className={styles.promiseNumber}>01</span><h3>A simpler way to call</h3><p>One press starts a call. Use the touchscreen or add a compatible keypad.</p></div>
              <div><span className={styles.promiseNumber}>02</span><h3>Your family, your say</h3><p>You choose who can connect and which contacts may drop in with audio or video.</p></div>
              <div><span className={styles.promiseNumber}>03</span><h3>Room for real conversations</h3><p>Unlimited Porch calls and drop-ins. Stay for another story.</p></div>
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
