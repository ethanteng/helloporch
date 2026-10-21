import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import StoryVideo from "@/components/StoryVideo";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import { introduction, chapters } from "./films";
import styles from "./story.module.css";

export const metadata: Metadata = {
  title: "Our Story | HelloPorch",
  description:
    "I’m building HelloPorch for my mom: one-press video calling that feels familiar. Watch our story, see the prototype, and tell me about your family.",
  openGraph: {
    title: "I’m building HelloPorch for my mom.",
    description: "How a phone became a barrier to family, and why I’m trying something simpler.",
    type: "website",
    images: [{ url: introduction.poster, width: 1920, height: 1080, alt: "HelloPorch: Built for my mom. One-press video calling." }],
  },
  twitter: {
    card: "summary_large_image",
    title: "I’m building HelloPorch for my mom.",
    images: [introduction.poster],
  },
};

export default function StoryPage() {
  return (
    <WaitlistProvider>
      <div className={`page ${styles.page}`} data-story-page>
        <a href="#story" className={styles.skip}>Skip to our story</a>
        <SiteNav story />

        <main id="story">
          <header className={styles.hero}>
            <div className="hero__badge">Our story</div>
            <h1 className={styles.title}>
              <span>I’m building HelloPorch</span>{" "}
              <em>for my mom.</em>
            </h1>
            <p className={styles.lede}>
              Using a phone has become really hard for my mom. I’m trying to make it easier for her to
              stay in touch with the people she loves, with something that feels familiar.
            </p>
          </header>

          <section id="introduction" className={styles.introduction} aria-labelledby="intro-title">
            <StoryVideo
              src={introduction.src}
              poster={introduction.poster}
              captions={introduction.captions}
              title="Why I’m building HelloPorch for my mom"
              className={`${styles.player} ${styles.introPlayer}`}
            />
            <div className={styles.introCopy}>
              <p className={styles.kicker}>Start here · 2 min 09 sec</p>
              <h2 id="intro-title">It started with my mom.</h2>
              <p>
                I’m Ethan. My mom is 78 and lives in assisted living. She has advanced Parkinson’s and
                dementia, and the phone she used to rely on has become difficult to use. This is why
                I’m building HelloPorch, and a look at what I’m trying.
              </p>
              <Transcript text={introduction.transcript} />
            </div>
          </section>

          <section id="chapters" className={styles.chapters} aria-labelledby="chapters-title">
            <div className={styles.chaptersIntro}>
              <h2 id="chapters-title">A little at a time.</h2>
              <p>Prefer the short version? Here’s the same story in four clips.</p>
            </div>
            {chapters.map((chapter, index) => (
              <article key={chapter.id} id={chapter.id} className={styles.chapter} aria-labelledby={`${chapter.id}-title`}>
                <div className={styles.chapterHeading}>
                  <span className={styles.number} aria-hidden="true">{index + 1}</span>
                  <div className={styles.chapterCopy}>
                    <p className={styles.duration}>Chapter {index + 1} · {chapter.duration}</p>
                    <h3 id={`${chapter.id}-title`}>{chapter.title}</h3>
                    <p>{chapter.description}</p>
                  </div>
                </div>
                <StoryVideo
                  src={chapter.src}
                  poster={chapter.poster}
                  captions={chapter.captions}
                  title={`Chapter ${index + 1}: ${chapter.title}`}
                  className={styles.player}
                />
                <Transcript text={chapter.transcript} />
              </article>
            ))}
          </section>

          <section id="join" className={styles.join} aria-labelledby="join-title">
            <h2 id="join-title">Does this sound <em>familiar?</em></h2>
            <p className={styles.joinBody}>
              I know we’re not the only family facing this. If someone in your family is having a hard
              time using a phone, join the waitlist.
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

function Transcript({ text }: { text: string }) {
  return (
    <details className={styles.transcript}>
      <summary>Read transcript</summary>
      <p>{text}</p>
    </details>
  );
}
