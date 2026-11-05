import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import StoryVideo from "@/components/StoryVideo";
import { JoinSection } from "@/components/PilotJoin";
import { WaitlistProvider } from "@/components/Waitlist";
import { introduction, chapters } from "./films";
import styles from "./story.module.css";

export const metadata: Metadata = {
  title: "Our Story | HelloPorch",
  description:
    "My mom has Parkinson’s and dementia, and her phone got too hard for her to use. These short videos explain why I’m building HelloPorch for her.",
  openGraph: {
    title: "I’m building HelloPorch for my mom.",
    description: "My mom’s phone got too hard for her to use, so I’m building something simpler.",
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
      <div className={`page ${styles.page}`}>
        <a href="#story" className={styles.skip}>Skip to our story</a>
        <SiteNav current="story" />

        <main id="story">
          <header className={styles.hero}>
            <h1 className={styles.title}>
              <span>I’m building HelloPorch</span>{" "}
              <em>for my mom.</em>
            </h1>
            <p className={styles.lede}>
              My mom can’t really use her phone anymore, so people who call her can’t reach her. I’m
              building something simple enough for her to use.
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
              <p className={styles.kicker}>The full video · 2 min 09 sec</p>
              <h2 id="intro-title">The whole story.</h2>
              <p>
                I’m Ethan. My mom is 78 and lives in assisted living. She has advanced Parkinson’s and
                dementia, and she can’t really use her phone anymore. In this video I explain why I’m
                building HelloPorch and show what I’ve made so far.
              </p>
              <Transcript text={introduction.transcript} />
            </div>
          </section>

          <section id="chapters" className={styles.chapters} aria-labelledby="chapters-title">
            <div className={styles.chaptersIntro}>
              <h2 id="chapters-title">In four short clips.</h2>
              <p>The same story, in four parts of about 30 seconds each.</p>
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

          <JoinSection />
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
