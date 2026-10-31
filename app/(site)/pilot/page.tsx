import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import PilotGuide from "./PilotGuide";
import styles from "./pilot.module.css";

export const metadata: Metadata = {
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "What the Porch pilot asks of families, and the form to join it: your email, how your family member will call, and whether you have an iPad that will work.",
};

export default function PilotPage() {
  return (
    <div className={`page ${styles.page}`}>
      <SiteNav current="pilot" joinHref="/#join" />

      <main>
        <header className={styles.hero}>
          <div className="hero__badge">For families interested in our pilot program</div>
          <h1 className={styles.title}>
            Getting ready for <em>the Porch pilot.</em>
          </h1>
          <p className={styles.lede}>
            <span>Porch is still a prototype, and the pilot is how I learn what to improve.</span>
            <span>By joining, you agree to share your feedback with&nbsp;me.</span>
          </p>
        </header>

        <section className={`${styles.section} ${styles.first}`} aria-label="What the pilot asks of you">
          <ul className={styles.involves}>
            <li>
              <h3>Respond to my emails and surveys.</h3>
              <p>Quick check-ins about what works, what doesn’t, and what you wish it did.</p>
            </li>
            <li>
              <h3>Have a conversation with&nbsp;me.</h3>
              <p>Now and then, a conversation about how Porch is working for your&nbsp;family.</p>
            </li>
            <li>
              <h3>Tell me when things&nbsp;break.</h3>
              <p>Let me know when something doesn't work so I can fix it quickly.</p>
            </li>
          </ul>
        </section>

        <PilotGuide />
      </main>

      <SiteFooter />
    </div>
  );
}
