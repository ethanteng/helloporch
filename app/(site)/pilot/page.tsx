import type { Metadata } from "next";
import Image from "next/image";
import type { ReactNode } from "react";
import SiteFooter from "@/components/SiteFooter";
import SiteNav from "@/components/SiteNav";
import { pageMetadata } from "@/lib/site-metadata";
import PilotSignup from "./PilotSignup";
import styles from "./pilot.module.css";

export const metadata: Metadata = pageMetadata({
  path: "/pilot",
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "Try the Porch prototype at home on an iPad or Android tablet with a big-button corded phone. See what you’ll need, then sign up with your email.",
  shareTitle: "Join the Porch pilot",
  image: { url: "/og/pilot.jpg", alt: "HelloPorch: Join the Porch pilot. Beside the Porch prototype, a tablet and a big-button phone." },
});

// What a family needs. The big-button corded phone, through a Cell2Jack, is the only way to call.
// The links are the ones I use, on Amazon.
const KIT: { name: string; rule: string; optional?: boolean; photo: string; href?: string }[] = [
  { name: "A tablet", rule: "iPad or Android", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", rule: "Any brand", photo: "/pilot/phone.jpg", href: "https://www.amazon.com/dp/B0FZ99J2QG" },
  { name: "A Cell2Jack", rule: "Must be a Cell2Jack", photo: "/pilot/cell2jack.jpg", href: "https://www.amazon.com/dp/B089984QRT" },
  { name: "A USB-C hub", rule: "Any brand, with a charging port", photo: "/pilot/hub.jpg", href: "https://www.amazon.com/dp/B0BQLLB61B" },
  { name: "A sturdy stand", rule: "Any brand", optional: true, photo: "/pilot/stand.jpg", href: "https://www.amazon.com/dp/B0H3N2YPKJ" },
];

const ASKS = ["Respond to my emails and surveys.", "Talk with me now and then.", "Tell me when things break."];

const STEPS: { title: string; text?: string }[] = [
  { title: "Sign up with your email." },
  {
    title: "I send you an invitation via email.",
    text: "Porch isn’t in the app stores yet, so it comes through Apple’s TestFlight or Google Play’s testing program.",
  },
  {
    title: "You set it up (under 5 minutes).",
    text: "Install the Porch app on the tablet, plug in the phone and the Cell2Jack, and add the people they call most. Family and friends also install the Porch app on their phones.",
  },
  {
    title: "They press your photo to call.",
    text: "They see and hear you on the tablet, just like a regular video call.",
  },
];

const QUESTIONS: { q: string; a: ReactNode }[] = [
  {
    q: "Which tablets work?",
    a: "Most recent iPads and Android tablets work.",
  },
  {
    q: "Which phone should I get?",
    a: "Any corded home phone with big number keys. Photo slots on the keys make it easiest. The adapter that connects it has to be a Cell2Jack.",
  },
  {
    q: "How does the family call?",
    a: "With the Porch app on an iPhone or Android phone. If they miss a call in the app, Porch rings their regular number instead.",
  },
  {
    q: "Does Porch speak their language?",
    a: "Porch speaks English, Mandarin, Cantonese and Spanish, and more languages are coming. Tell me if your family needs another.",
  },
];

// What the pilot is, what it needs and asks, with the sign-up in the first screen.
export default function PilotPage() {
  return (
    <div className="page">
      <SiteNav current="pilot" />

      <main>
        <header className={styles.hero}>
          <div className={styles.heroCopy}>
            <h1 className={styles.title}>
              Join the <em>Porch pilot.</em>
            </h1>
            <p className={styles.lede}>
              Try the prototype at home on an iPad or Android tablet, with a big-button corded phone. Family and friends call
              from the Porch app on iPhone or Android. Then tell me what works and what doesn’t.
            </p>
            <div className={styles.signup}>
              <h2 className={styles.srOnly}>Sign up for the pilot</h2>
              <PilotSignup />
            </div>
          </div>
          <figure className={styles.photo}>
            <Image
              src="/pilot/setup.jpg"
              alt="The Porch prototype on a wooden table: a tablet on a stand showing a large clock, beside a big-button corded phone with photos on its keys."
              fill
              preload
              sizes="(max-width: 900px) 100vw, 520px"
            />
          </figure>
        </header>

        <section className={styles.glance} aria-label="The pilot at a glance">
          <article className={styles.glanceCard}>
            <p className={styles.glanceLabel}>You’ll need</p>
            <h3>A tablet and a corded phone</h3>
            <ul className={styles.kitList}>
              {KIT.map((part) => (
                <li key={part.name}>
                  <span className={styles.kitThumb}>
                    <Image src={part.photo} alt="" fill sizes="56px" />
                  </span>
                  <span>
                    <strong>{part.name}</strong>
                    {part.optional ? <em> (optional)</em> : null}
                    <span className={styles.kitRule}>
                      {part.rule}
                      {part.href ? (
                        <>
                          {" · "}
                          <a href={part.href} target="_blank" rel="noopener noreferrer">
                            See it on Amazon
                          </a>
                        </>
                      ) : null}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </article>
          <article className={styles.glanceCard}>
            <p className={styles.glanceLabel}>I’ll ask you to</p>
            <h3>Tell me how it goes</h3>
            <ul className={styles.glanceList}>
              {ASKS.map((ask) => (
                <li key={ask}>{ask}</li>
              ))}
            </ul>
          </article>
        </section>

        <section className={styles.band} aria-labelledby="how-title">
          <h2 id="how-title" className={styles.h2}>
            How it <em>works.</em>
          </h2>
          <ol className={styles.stepRow}>
            {STEPS.map((step, i) => (
              <li key={step.title}>
                <span className={styles.stepNum} aria-hidden="true">
                  {i + 1}
                </span>
                <h3>{step.title}</h3>
                {step.text ? <p>{step.text}</p> : null}
              </li>
            ))}
          </ol>
        </section>

        <section className={`${styles.band} ${styles.lastBand}`} aria-labelledby="faq-title">
          <h2 id="faq-title" className={styles.h2}>
            A few <em>questions.</em>
          </h2>
          <div className={styles.faq}>
            {QUESTIONS.map(({ q, a }) => (
              <details key={q} className={styles.faqItem}>
                <summary>
                  {q}
                  <span aria-hidden="true">+</span>
                </summary>
                <p>{a}</p>
              </details>
            ))}
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
