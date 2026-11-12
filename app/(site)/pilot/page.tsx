import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";
import SiteFooter from "@/components/SiteFooter";
import SiteNav from "@/components/SiteNav";
import { pageMetadata } from "@/lib/site-metadata";
import { KitTag } from "./_guide/parts";
import PilotSignup from "./PilotSignup";
import { shopping } from "./shopping";
import styles from "./pilot.module.css";

export const metadata: Metadata = pageMetadata({
  path: "/pilot",
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "Try the Porch video calling app at home on your own iPad or Android tablet, with a big-button corded phone. See what you’ll need, then request an invite.",
  shareTitle: "Join the Porch pilot",
  image: { url: "/og/pilot.jpg", alt: "HelloPorch: Join the Porch pilot. Beside the Porch prototype, a tablet and a big-button phone." },
});

// What a family needs. The big-button corded phone, through a Cell2Jack, is the only way to call. On an iPad it also
// goes through the Porch phone adapter (phone-adapter/), which I flash and test, then mail or drop off, so it is free and
// has no link. Every iPad family gets one, whatever the iPad, so the pages don't ask families which iPad they have; an
// iPad with an M chip could take the Cell2Jack straight in, and Porch and the iPad guide mention that. The tablet has
// no price: most families use one they have. The links are the ones I use, on Amazon, and the prices are roughly what
// they cost there.
const KIT: { name: string; rule: string; price?: string; optional?: boolean; photo: string; href?: string }[] = [
  { name: "A tablet", rule: "iPad or Android", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", rule: "Any brand", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Must be a Cell2Jack", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "A Porch phone adapter", rule: "For iPads. I will mail it to you.", ...shopping.adapter, photo: "/pilot/adapter.jpg" },
  { name: "A USB-C hub", rule: "Any brand", ...shopping.hub, photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Any brand", ...shopping.stand, optional: true, photo: "/pilot/stand.jpg" },
];

// Each step's text, one paragraph per entry.
const STEPS: { title: string; text: string[] }[] = [
  {
    title: "Sign up with your email.",
    text: ["I’ll reach out with an invitation and instructions for getting started."],
  },
  {
    title: "Install Porch on your tablet and family phones.",
    text: ["Porch isn’t in the app stores yet. You’ll get it through Apple’s TestFlight or Google Play’s testing program."],
  },
  {
    title: "Set it up for your family.",
    text: [
      "Connect the tablet and phone, and add the people your loved one calls most.",
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
    q: "Do I need to buy a tablet from HelloPorch?",
    a: "No. Porch is an app you install on a compatible tablet you already own or purchase yourself. For the current pilot, you’ll also need a big-button phone, a Cell2Jack and a USB-C hub. With an iPad, you’ll also use one more small adapter, which I’ll provide.",
  },
  {
    q: "Can I use a tablet I already own?",
    a: "Probably. Any iPad with iPadOS 15 or later works, and so does an Android tablet with Android 15 or later.",
  },
  {
    q: "Do I need a special phone?",
    a: "No. A corded phone with big buttons works best, especially one with room for photos on the keys. You’ll need a Cell2Jack adapter to connect it. With an iPad, it also goes through a Porch phone adapter, which I’ll provide.",
  },
  {
    q: "How do I put photos on the phone buttons?",
    a: <>Use the <Link href="/labels">phone button label maker</Link> to add photos and names, set the size of your buttons, and download a PDF to print.</>,
  },
  {
    q: "What is the Porch phone adapter?",
    a: "A small board that lets an iPad read the buttons on the phone through the Cell2Jack. I’ll provide it, already set up and tested. I’ll mail it to you, or drop it off if you live nearby. Every iPad family gets one. Android tablets don’t need it.",
  },
  {
    q: "How do family members call?",
    a: "Through the Porch app on their iPhone or Android phone. If they miss a video call, Porch can ring their regular phone number instead.",
  },
  {
    q: "Can Porch speak another language?",
    a: "Yes! Porch supports English, Mandarin, Cantonese, Spanish, Tagalog, and Korean, with more languages on the way. Let me know if there’s another language your family needs.",
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
              <p>I’m inviting families to try the HelloPorch app at home with their loved ones.</p>
              <p>
                You’ll install Porch on your own compatible iPad or Android tablet and connect a big-button corded phone.
                Family and friends install the Porch app on their iPhones or Android phones to stay connected.
              </p>
              <p>
                I’ll provide access to the app and setup instructions. All I ask in return is your honest feedback on what
                works, what doesn’t, and what could be better.
              </p>
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
          <article className={`${styles.glanceCard} ${styles.kitCard}`}>
            <div className={styles.kitIntro}>
              <h2 className={styles.glanceLabel}>What you’ll need.</h2>
              <h3>You’ll provide most of the hardware. I’ll provide the app.</h3>
              <p className={styles.glanceText}>
                Porch works with a compatible iPad or Android tablet and a big-button corded phone. You’ll also need a
                Cell2Jack adapter and a USB-C hub. A sturdy tablet stand is helpful, but optional.
              </p>
              <p className={styles.glanceText}>
                With an iPad, the phone also goes through a Porch phone adapter. I’ll provide this, already set up and
                tested, and mail it to you, or drop it off if you live nearby.
              </p>
              <p className={styles.glanceText}>
                You may already have some of what you need. Here’s the hardware for the current pilot.
              </p>
            </div>
            <ul className={styles.kitGrid}>
              {KIT.map((part) => (
                <li key={part.name}>
                  <span className={styles.kitPhoto}>
                    <Image src={part.photo} alt="" fill sizes="(max-width: 760px) 45vw, (max-width: 1140px) 30vw, 220px" />
                    <KitTag part={part} />
                  </span>
                  <strong className={styles.kitName}>
                    {part.name}
                    {part.optional ? <em> (optional)</em> : null}
                  </strong>
                  <span className={styles.kitRule}>{part.rule}</span>
                </li>
              ))}
            </ul>
          </article>
          <article className={`${styles.glanceCard} ${styles.askCard}`}>
            <div className={styles.askHead}>
              <h2 className={styles.glanceLabel}>What I’ll ask of you.</h2>
              <h3>Just tell me how it’s going.</h3>
            </div>
            <div className={styles.askText}>
              <p className={styles.glanceText}>
                Try Porch with your loved one and let me know what works and what doesn’t. I’ll check in occasionally by
                email or a quick conversation.
              </p>
              <p className={styles.glanceText}>And if something breaks or gets confusing, I definitely want to know about it.</p>
            </div>
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
