import type { ReactNode } from "react";
import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import StoryVideo from "@/components/StoryVideo";
import { JoinSection, PilotButton } from "@/components/PilotJoin";
import { WaitlistProvider } from "@/components/Waitlist";
import FeatureTabs from "./FeatureTabs";
import { accessibility, calling, clip, safety, type Clip, type Screenshot } from "./clips";
import styles from "./features.module.css";
import Story from "./Story";
import story from "./story.module.css";
import ThreeWayCalling from "./ThreeWayCalling";
import WatchClip from "./WatchClip";

export const metadata: Metadata = {
  title: "See How It Works | HelloPorch",
  description:
    "Porch is for people who find phones hard: they press a face to call, big buttons work with shaky hands, Porch answers approved callers for them, messages play on their own, it speaks Mandarin, Cantonese and Spanish, and you can bring family onto a call. Watch short clips of each.",
};

export default function FeaturesPage() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav current="features" />

        <main>
          <header className={story.hero}>
            <div className={story.heroCopy}>
              <div className="hero__badge">See how it works</div>
              <h1 className={story.title}>
                They press a face. <em>You pick up.</em>
              </h1>
              <p className={story.lede}>
                Porch is for people who find phones hard. It’s a tablet that stays on one simple screen, beside a big-button
                corded phone with photos of friends and loved ones on its buttons.
              </p>
              <ul className={story.forList} aria-label="Who Porch is for">
                <li>Parkinson’s and tremors</li>
                <li>Dementia and memory loss</li>
                <li>Not comfortable with technology</li>
                <li>Mandarin, Cantonese, Spanish, and more soon</li>
              </ul>
              <div className={story.heroActions}>
                <PilotButton />
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
                  <span className={story.callout} style={{ left: "47%", top: "16%" }}>
                    Always on, never locked
                  </span>
                  <span className={story.callout} style={{ left: "6%", top: "86%" }}>
                    Real buttons with faces and names
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
                Watch it <em>all.</em>
              </h2>
              <p className={styles.lede}>
                Short clips of real calls on the Porch prototype, from the button they press to the phone in your hand.
              </p>
            </div>

            <FeatureTabs
              tabs={[
                {
                  id: "calling",
                  label: "Calling",
                  content: (
                    <Clips clips={calling}>
                      <ThreeWayCalling />
                    </Clips>
                  ),
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

// `children` follow the clips, such as an entry shown with screens instead of a clip.
function Clips({ clips, children }: { clips: Clip[]; children?: ReactNode }) {
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
      {children}
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
