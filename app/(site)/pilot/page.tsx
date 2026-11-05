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

// Each step's text, one paragraph per entry.
const STEPS: { title: string; text: string[] }[] = [
  {
    title: "Leave your email.",
    text: ["I’ll reach out with an invitation and instructions for getting started."],
  },
  {
    title: "Install Porch.",
    text: ["Porch isn’t in the app stores yet. You’ll get it through Apple’s TestFlight or Google Play’s testing program."],
  },
  {
    title: "Set it up for your family.",
    text: [
      "Connect the tablet and phone, add the people your loved one calls most, and have family members install the Porch app.",
    ],
  },
  {
    title: "Start calling.",
    text: [
      "They press your photo to call. They see and hear you on the tablet, and can use the familiar phone receiver if they prefer.",
      "When you call them, Porch can even answer automatically.",
    ],
  },
];

const QUESTIONS: { q: string; a: ReactNode }[] = [
  {
    q: "Can I use a tablet I already own?",
    a: "Most recent iPads and Android tablets should work, but compatibility depends on the model and accessories.",
  },
  {
    q: "Do I need a special phone?",
    a: "No. A corded phone with big buttons works best, especially one with room for photos on the keys. You’ll need a Cell2Jack adapter to connect it.",
  },
  {
    q: "How do family members call?",
    a: "Through the Porch app on their iPhone or Android phone. If they miss a video call, Porch can ring their regular phone number instead.",
  },
  {
    q: "Can Porch speak another language?",
    a: "Yes! Porch supports English, Mandarin, Cantonese, and Spanish, with more languages on the way. Let me know if there’s another language your family needs.",
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
            <div className={styles.lede}>
              <p>I’m inviting families to try Porch at home with their loved ones.</p>
              <p>
                The prototype runs on an iPad or Android tablet, paired with a big-button corded phone. Family and friends use
                the Porch app on their own phones to make video calls.
              </p>
              <p>All I ask in return is your honest feedback. What’s working, what’s confusing, and what could be better.</p>
            </div>
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
            <h2 className={styles.glanceLabel}>What you’ll need.</h2>
            <h3>A tablet, a phone, and a couple of adapters.</h3>
            <p className={styles.glanceText}>
              Porch works with a compatible iPad or Android tablet and a big-button corded phone. You’ll also need a Cell2Jack
              adapter and a USB-C hub. A sturdy tablet stand is helpful, but optional.
            </p>
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
            <h2 className={styles.glanceLabel}>What I’ll ask of you.</h2>
            <h3>Just tell me how it’s going.</h3>
            <p className={styles.glanceText}>
              Try Porch with your loved one and let me know what works and what doesn’t. I’ll check in occasionally by email or
              a quick conversation.
            </p>
            <p className={styles.glanceText}>And if something breaks or gets confusing, I definitely want to know about it.</p>
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
                {step.text.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </li>
            ))}
          </ol>
        </section>

        <section className={`${styles.band} ${styles.lastBand}`} aria-labelledby="faq-title">
          <h2 id="faq-title" className={styles.h2}>
            A few common <em>questions.</em>
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
