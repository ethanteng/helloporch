import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import StoryVideo from "@/components/StoryVideo";
import { JoinSection, PilotButton } from "@/components/PilotJoin";
import { WaitlistProvider } from "@/components/Waitlist";
import { pageMetadata } from "@/lib/site-metadata";
import FeatureTabs from "./FeatureTabs";
import { accessibility, calling, clip, safety, type Clip, type Screenshot } from "./clips";
import styles from "./features.module.css";
import Story from "./Story";
import story from "./story.module.css";
import WatchClip from "./WatchClip";

export const metadata: Metadata = pageMetadata({
  path: "/features",
  title: "See How It Works | HelloPorch",
  description:
    "See how the Porch video calling app works on an iPad or Android tablet: one press starts a call, Porch answers family for them, messages play on their own, and it speaks their language.",
  shareTitle: "Video calls, at the press of a button.",
  image: { url: "/og/features.jpg", alt: "HelloPorch: Video calls, at the press of a button. Beside the Porch prototype, a tablet and a big-button phone." },
});

export default function FeaturesPage() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav current="features" />

        <main>
          <header className={story.hero}>
            <div className={story.heroCopy}>
              <h1 className={story.title}>
                Video calls, <em>at the press of a button.</em>
              </h1>
              <div className={story.lede}>
                <p>
                  Porch is a video calling app that runs on your own iPad or Android tablet, paired with a big-button phone.
                  Each button has a photo of someone they love. <strong>One press starts a video call.</strong>
                </p>
                <p>
                  Family and friends use the Porch app on their iPhones or Android phones to call, answer, and send messages.
                </p>
              </div>
              <ul className={story.forList} aria-label="Who Porch is for">
                <li>Parkinson’s &amp; limited dexterity</li>
                <li>Dementia &amp; memory loss</li>
                <li>Anyone who struggles with phones</li>
              </ul>
              <div className={story.heroActions}>
                <PilotButton size="lg" />
              </div>
            </div>
            <div className={story.heroMedia}>
              <figure className={story.heroPhoto}>
                <Image
                  src="/pilot/setup.jpg"
                  alt="Porch on a wooden table: a tablet on a stand showing a large clock and a Call someone button, beside a white corded phone whose big buttons each carry a family photo."
                  fill
                  preload
                  sizes="(max-width: 900px) min(100vw, 480px), 520px"
                />
                <figcaption className={story.callouts}>
                  <span className={story.callout} style={{ right: "4%", top: "16%" }}>
                    Your tablet, running Porch
                  </span>
                  <span className={story.callout} style={{ left: "6%", top: "86%" }}>
                    Big-button phone with family photos
                  </span>
                </figcaption>
              </figure>
              <WatchClip clip={clip("first-real-call")} label="Watch Mom’s first real call" />
            </div>
          </header>

          <Story />

          <section id="clips" className={styles.library} aria-labelledby="clips-title">
            <div className={styles.libraryHead}>
              <h2 id="clips-title" className={styles.libraryTitle}>
                See it for <em>yourself.</em>
              </h2>
              <p className={styles.lede}>
                These are real clips from the Porch prototype, including my mom’s first call and some of the key features we’ve
                built since.
              </p>
            </div>

            <FeatureTabs
              tabs={[
                {
                  id: "calling",
                  label: "Calling",
                  content: <Clips clips={calling} />,
                },
                { id: "accessibility", label: "Accessibility", content: <Clips clips={accessibility} /> },
                { id: "safety", label: "Safety", content: <Screenshots shots={safety} /> },
              ]}
            />
          </section>

          <JoinSection />
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
