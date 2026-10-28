import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import StoryVideo from "@/components/StoryVideo";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import FeatureTabs from "./FeatureTabs";
import { accessibility, calling, safety, type Clip, type Screenshot } from "./clips";
import styles from "./features.module.css";

export const metadata: Metadata = {
  title: "See Porch in Action | HelloPorch",
  description:
    "Short clips of the Porch prototype: one press starts a video call, calls fall back to your phone, family can drop in, messages play on their own, it speaks their language, and unknown callers are blocked.",
};

export default function FeaturesPage() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav current="features" />

        <main>
          <header className={styles.hero}>
            <h1 className={styles.title}>
              See Porch <em>in action.</em>
            </h1>
            <p className={styles.lede}>
              Short clips of real calls on the Porch prototype, from the button they press to the phone in your hand.
            </p>
          </header>

          <FeatureTabs
            tabs={[
              { id: "calling", label: "Calling", content: <Clips clips={calling} /> },
              { id: "accessibility", label: "Accessibility", content: <Clips clips={accessibility} /> },
              { id: "safety", label: "Safety", content: <Screenshots shots={safety} /> },
            ]}
          />

          <section id="join" className={styles.join} aria-labelledby="join-title">
            <h2 id="join-title">
              Want Porch for <em>your family?</em>
            </h2>
            <p className={styles.joinBody}>
              We’re building early units now. Join the waitlist and we’ll email you when one can be yours.
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

function Clips({ clips }: { clips: Clip[] }) {
  return (
    <div className={styles.clips}>
      {clips.map((clip) => (
        <article key={clip.id} id={clip.id} className={styles.clip} aria-labelledby={`${clip.id}-title`}>
          <StoryVideo
            src={clip.src}
            poster={clip.poster}
            title={clip.title}
            width={1080}
            height={1920}
            className={styles.player}
          />
          <div className={styles.clipCopy}>
            <p className={styles.duration}>{clip.duration}</p>
            <h2 id={`${clip.id}-title`}>{clip.title}</h2>
            <p>{clip.description}</p>
          </div>
        </article>
      ))}
    </div>
  );
}

function Screenshots({ shots }: { shots: Screenshot[] }) {
  return (
    <div className={styles.clips}>
      {shots.map((shot) => (
        <article key={shot.id} id={shot.id} className={`${styles.clip} ${styles.textFirst}`} aria-labelledby={`${shot.id}-title`}>
          <div className={styles.clipCopy}>
            <p className={styles.duration}>{shot.label}</p>
            <h2 id={`${shot.id}-title`}>{shot.title}</h2>
            <p>{shot.description}</p>
          </div>
          <Image
            src={shot.image}
            alt={shot.alt}
            width={1080}
            height={1200}
            sizes="(max-width: 900px) min(100vw, 440px), 400px"
            className={styles.screenshot}
          />
        </article>
      ))}
    </div>
  );
}
