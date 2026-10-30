import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import PilotGuide from "./PilotGuide";
import styles from "./pilot.module.css";

export const metadata: Metadata = {
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "What the Porch pilot asks of families, and the form to join it: your email, how your family member will call, and whether you have an iPad that will work.",
};

export default function PilotPage() {
  return (
    <WaitlistProvider>
      <div className={`page ${styles.page}`}>
        <SiteNav current="pilot" />

        <main>
          <header className={styles.hero}>
            <div className="hero__badge">For families in our pilot program</div>
            <h1 className={styles.title}>
              Getting ready for <em>the Porch pilot.</em>
            </h1>
            <p className={styles.lede}>
              Thank you for helping me test Porch. Here’s what the pilot asks of you, then a short form to join
              and see what you’ll need.
            </p>
          </header>

          <section className={`${styles.section} ${styles.first}`} aria-labelledby="involves-title">
            <div className={styles.sectionIntro}>
              <h2 id="involves-title">What the pilot asks of you</h2>
              <p>
                Porch is still a prototype, and the pilot is how I learn what to fix. By joining, you agree to
                share how it’s going.
              </p>
            </div>
            <ul className={styles.involves}>
              <li>
                <h3>Answer my emails and surveys.</h3>
                <p>Quick check-ins about what works, what doesn’t, and what you wish it did.</p>
              </li>
              <li>
                <h3>Talk with me face to face.</h3>
                <p>Now and then, a conversation about how Porch is working for your family.</p>
              </li>
              <li>
                <h3>Be patient with rough edges.</h3>
                <p>Some things will break, and updates will come often.</p>
              </li>
            </ul>
          </section>

          <PilotGuide />

          <section id="join" className={styles.join} aria-labelledby="join-title">
            <h2 id="join-title">
              Know a family who <em>could use Porch?</em>
            </h2>
            <p className={styles.joinBody}>
              They can join the waitlist here, and I’ll email them when Porch is ready for more families.
            </p>
            <div className={styles.signup}>
              <JoinWaitlist />
            </div>
          </section>
        </main>

        <SiteFooter />
      </div>
    </WaitlistProvider>
  );
}
