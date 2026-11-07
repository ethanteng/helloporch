import type { Metadata } from "next";
import Link from "next/link";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinSection } from "@/components/PilotJoin";
import { WaitlistProvider } from "@/components/Waitlist";
import PricingPlans from "./PricingPlans";
import styles from "./pricing.module.css";

export const metadata: Metadata = {
  title: "Pricing Preview | HelloPorch",
  description: "One HelloPorch software plan: $39 a month for one loved one’s tablet, with unlimited family members, Porch calls, drop-ins and regular phone calls. Add another tablet for $30 a month.",
  robots: { index: false, follow: false },
};

const questions = [
  {
    question: "What does one subscription cover?",
    answer: "The $39 monthly subscription covers one loved one’s tablet and every Porch feature. Invite as many family members as you like. They use the Porch app on iPhone or Android at no extra charge.",
  },
  {
    question: "Do family members pay separately?",
    answer: "No. Family members use the Porch app on their own iPhone or Android phone at no extra charge. There are no per-person fees or paid feature upgrades.",
  },
  {
    question: "Is there a calling-minute limit?",
    answer: "No. The proposed plan includes unlimited Porch audio and video calls, approved drop-ins, and regular phone calls, with no monthly minute allowance or automatic call-length cutoff.",
  },
  {
    question: "What if I have more than one loved one?",
    answer: "Add another tablet for $30 a month, or $330 a year with annual billing. Two tablets are $69 a month or $759 a year, and three are $99 a month or $1,089 a year. Every tablet gets the same features, and your family gets one bill.",
  },
  {
    question: "Does the price include the tablet or the phone?",
    answer: "No. This is a software subscription. You’ll need an iPad or Android tablet, home Wi-Fi, a big-button corded phone and a Cell2Jack to connect it. With an iPad, the phone also goes through a small Porch phone adapter, which we provide. Our pilot page lists the equipment, with links to the ones we use.",
  },
  {
    question: "What happens if we replace the tablet?",
    answer: "Move the subscription to the new tablet. Replacing a loved one’s tablet doesn’t mean buying another subscription.",
  },
  {
    question: "How does annual billing work?",
    answer: "Annual billing gives you twelve months for the price of eleven. One tablet is $429 a year, paid once a year, and each additional tablet is $330 a year. Monthly billing is $39, plus $30 for each additional tablet.",
  },
  {
    question: "Can I subscribe today?",
    answer: "Not yet. This is a preview of the pricing we’re considering while Porch is in its pilot. You can try Porch now by joining the pilot, or join the waitlist for launch updates. Neither one starts a subscription, and final pricing and availability may change.",
  },
];

export default function PricingPage() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav />
        <main id="main-content" className={styles.main}>
          <header className={styles.hero}>
            <h1 className={styles.title}>Porch for <em>your family.</em></h1>
            <p className={styles.lede}>One subscription for your loved one’s tablet. Family members call from the Porch app on iPhone or Android at no extra charge.</p>
            <p className={styles.previewNote}>Proposed software pricing · Porch is currently in its pilot</p>
          </header>

          <PricingPlans />

          <section className={styles.included} aria-labelledby="included-title">
            <h2 id="included-title">Calling and <em>privacy.</em></h2>
            <div className={styles.promises}>
              <div><span className={styles.promiseNumber} aria-hidden="true">1</span><h3>One-press calling</h3><p>They press a photo on a big-button corded phone to call.</p></div>
              <div><span className={styles.promiseNumber} aria-hidden="true">2</span><h3>Control who can connect</h3><p>Manage contacts and choose who may start an audio or video drop-in.</p></div>
              <div><span className={styles.promiseNumber} aria-hidden="true">3</span><h3>No call-length limits</h3><p>Talk for as long as you like, with no monthly minute allowance or automatic cutoff.</p></div>
            </div>
          </section>

          <section className={styles.faq} aria-labelledby="faq-title">
            <div className={styles.faqIntro}>
              <h2 id="faq-title">About the <em>subscription.</em></h2>
              <p>To see the equipment you’ll need, read the pilot page.</p>
              <Link href="/pilot">See what you’ll need <Arrow /></Link>
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

          <JoinSection />
        </main>
        <SiteFooter />
      </div>
    </WaitlistProvider>
  );
}

function Arrow() {
  return <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
