// While the Porch keypad is being designed, the pilot is the main ask on the site: its button, and the closing section
// that pairs it with a quiet waitlist line for families who'd rather wait for the keypad.
import Image from "next/image";
import Link from "next/link";
import { JoinWaitlist } from "@/components/Waitlist";
import styles from "./PilotJoin.module.css";

export function PilotButton({ size }: { size?: "lg" }) {
  return (
    <Link href="/pilot" className={size === "lg" ? `${styles.ctaPrimary} ${styles.ctaLg}` : styles.ctaPrimary}>
      Join the pilot <Arrow />
    </Link>
  );
}

export function JoinSection() {
  return (
    <section id="join" className="join">
      <div className="join__copy">
        <p className={styles.pilotKicker}>The Porch pilot</p>
        <h2 className="join__title">
          Help us test <em>Porch.</em>
        </h2>
        <p className="join__body">
          The Porch app runs on your own compatible iPad or Android tablet, connected to a big-button phone. We’re inviting
          families to try it and tell us what works and what doesn’t.
        </p>
        <div className={styles.joinActions}>
          <Link href="/pilot" className={styles.ctaHoney}>
            Join the pilot <Arrow />
          </Link>
          <span className={styles.joinNote}>Family members use the Porch app on iPhone or Android.</span>
        </div>
      </div>
      <figure className={styles.joinPhoto}>
        <Image
          src="/pilot/setup.jpg"
          alt="The Porch prototype on a wooden table: a tablet on a stand showing a large clock, beside a corded phone with family photos on its buttons."
          fill
          sizes="(max-width: 1140px) 100vw, 560px"
        />
      </figure>
      {/* The waitlist is for the keypad, which is a long way off, so it's a quiet line under the pilot. */}
      <div className={styles.waitQuiet}>
        <p>
          <strong>Waiting for the Porch keypad?</strong> It’s still a while away. Leave your email and we’ll let you know
          when it’s ready.
        </p>
        <JoinWaitlist />
      </div>
    </section>
  );
}

export function Arrow() {
  return (
    <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none">
      <path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
