import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";
import type { ReactNode } from "react";
import SiteFooter from "@/components/SiteFooter";
import SiteNav from "@/components/SiteNav";
import styles from "./guide.module.css";

// The pilot's getting-started guides. Nothing links to them: I send each invited family the one for their tablet, so
// they stay out of search and the sitemap, like the pricing preview.
export function guideMetadata(title: string, description: string): Metadata {
  return { title, description, robots: { index: false, follow: false } };
}

export type KitPart = { name: string; rule: string; photo: string };
export type GuidePart = { id: string; title: string; body: ReactNode };

type GuideProps = {
  eyebrow: string;
  title: ReactNode;
  lede: ReactNode;
  other: { href: string; label: string };
  kit: KitPart[];
  kitIntro: ReactNode;
  ready: ReactNode[];
  parts: GuidePart[];
};

/** A whole guide: the hero, what to have ready, a contents list and the numbered parts. */
export function Guide({ eyebrow, title, lede, other, kit, kitIntro, ready, parts }: GuideProps) {
  return (
    <div className={`page ${styles.page}`}>
      <a href="#guide" className={styles.skip}>Skip to the guide</a>
      <SiteNav />

      <main id="guide">
        <header className={styles.hero}>
          <p className={styles.eyebrow}>{eyebrow}</p>
          <h1 className={styles.title}>{title}</h1>
          <div className={styles.lede}>{lede}</div>
          <p className={styles.other}>
            Using the other kind? <Link href={other.href}>{other.label}</Link>
          </p>
        </header>

        <section className={styles.card} aria-labelledby="kit-title">
          <h2 id="kit-title">What you’ll need</h2>
          <p>{kitIntro}</p>
          <ul className={styles.kit}>
            {kit.map((part) => (
              <li key={part.name}>
                <span className={styles.kitPhoto}>
                  <Image src={part.photo} alt="" fill sizes="(max-width: 700px) 45vw, 230px" />
                </span>
                <strong className={styles.kitName}>{part.name}</strong>
                <span className={styles.kitRule}>{part.rule}</span>
              </li>
            ))}
          </ul>
          <h3 className={styles.readyTitle}>Have these ready, too</h3>
          <ul className={styles.ready}>
            {ready.map((item, i) => <li key={i}>{item}</li>)}
          </ul>
        </section>

        <nav className={`${styles.column} ${styles.contents}`} aria-labelledby="contents-title">
          <h2 id="contents-title">In this guide</h2>
          <ol>
            {parts.map((part) => (
              <li key={part.id}>
                <a href={`#${part.id}`}>{part.title}</a>
              </li>
            ))}
          </ol>
        </nav>

        <div className={`${styles.column} ${styles.body}`}>
          {parts.map((part, i) => (
            <section key={part.id} id={part.id} className={styles.part} aria-labelledby={`${part.id}-title`}>
              <div className={styles.partHead}>
                <span className={styles.partNum} aria-hidden="true">{i + 1}</span>
                <h2 id={`${part.id}-title`}>{part.title}</h2>
              </div>
              {part.body}
            </section>
          ))}
        </div>
      </main>

      <SiteFooter />
    </div>
  );
}

// How families reach me during the pilot.
const email = "ethan@helloporch.store";
const phone = { shown: "415-867-6937", dial: "+14158676937" };

/** My email address and phone number, as links: "email me at …, or call or text me at …". */
export function Contact() {
  return (
    <>
      email me at <a href={`mailto:${email}`}>{email}</a>, or call or text me at{" "}
      <a href={`tel:${phone.dial}`}>{phone.shown}</a>
    </>
  );
}

/** My email address, as a link. */
export function Email() {
  return <a href={`mailto:${email}`}>{email}</a>;
}

/** A button, screen title or switch, written exactly as Porch shows it. */
export function UI({ children }: { children: ReactNode }) {
  return <span className={styles.ui}>{children}</span>;
}

/** Something Porch says or shows back, such as "Porch heard 3." */
export function Says({ children }: { children: ReactNode }) {
  return <span className={styles.says}>“{children}”</span>;
}

export function Tip({ label = "Tip", children }: { label?: string; children: ReactNode }) {
  return (
    <aside className={styles.tip}>
      <span className={styles.tipLabel}>{label}</span>
      {children}
    </aside>
  );
}

export function Warn({ label = "Important", children }: { label?: string; children: ReactNode }) {
  return (
    <aside className={styles.warn}>
      <span className={styles.tipLabel}>{label}</span>
      {children}
    </aside>
  );
}

/** What plugs into what, left to right. */
export function Chain({ label, items }: { label: string; items: string[] }) {
  return (
    <ol className={styles.chain} aria-label={label}>
      {items.map((item) => <li key={item}><span>{item}</span></li>)}
    </ol>
  );
}

/** Questions that open in place. */
export function Questions({ items }: { items: { q: string; a: ReactNode }[] }) {
  return (
    <div className={styles.faq}>
      {items.map(({ q, a }) => (
        <details key={q}>
          <summary>
            {q}
            <span aria-hidden="true">+</span>
          </summary>
          {a}
        </details>
      ))}
    </div>
  );
}
