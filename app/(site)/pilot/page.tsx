import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import PilotGuide from "./PilotGuide";
import styles from "./pilot.module.css";

export const metadata: Metadata = {
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "Three quick steps to get ready for the Porch pilot: Porch is on iPad and iPhone, you’ll need a recent iPad, and you choose the touchscreen, a number pad or a big-button phone.",
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
              Thank you for helping me test Porch. Go through these three steps, and you’ll see what to get and
              how to start.
            </p>
          </header>

          <PilotGuide />

          <section className={styles.section} aria-labelledby="involves-title">
            <div className={styles.sectionIntro}>
              <h2 id="involves-title">What the pilot asks of you</h2>
            </div>
            <ul className={styles.involves}>
              <li>
                <h3>A spot with Wi-Fi and an outlet.</h3>
                <p>Somewhere your family member spends their day, with the iPad left on and open to Porch.</p>
              </li>
              <li>
                <h3>Patience with rough edges.</h3>
                <p>Porch is a prototype. Some things will break, and updates will come often.</p>
              </li>
              <li>
                <h3>Your honest feedback.</h3>
                <p>Tell me what works, what doesn’t, and what you wish it did.</p>
              </li>
            </ul>
          </section>

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
