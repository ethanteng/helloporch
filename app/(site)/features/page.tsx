import type { ReactNode } from "react";
import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import StoryVideo from "@/components/StoryVideo";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import FeatureTabs from "./FeatureTabs";
import { accessibility, calling, clip, safety, type Clip, type Screenshot } from "./clips";
import styles from "./features.module.css";
import Story from "./Story";
import story from "./story.module.css";
import ThreeWayCalling from "./ThreeWayCalling";
import WatchClip from "./WatchClip";

export const metadata: Metadata = {
  title: "See Porch in Action | HelloPorch",
  description:
    "Nothing to unlock: they press a face to call, Porch answers your calls for them, messages play on their own, it speaks Mandarin, Cantonese and Spanish, and you can bring the whole family onto a call. Watch short clips of each.",
};

export default function FeaturesPage() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav current="features" />

        <main>
          <header className={story.hero}>
            <div className={story.heroCopy}>
              <div className="hero__badge">See Porch in action</div>
              <h1 className={story.title}>
                Nothing to unlock. <em>Just press.</em>
              </h1>
              <p className={story.lede}>
                No apps to open, and no tiny buttons to find on a touchscreen. Porch is an iPad that’s always ready and a
                phone with real buttons, each one labeled with the face and name of someone they love.
              </p>
              <WatchClip clip={clip("first-real-call")} label="Watch Mom’s first real call" hero />
            </div>
            <figure className={story.heroPhoto}>
              <Image
                src="/pilot/setup.jpg"
                alt="Porch on a wooden table: an iPad on a stand showing a large clock and a Call someone button, beside a white corded phone whose big buttons each carry a family photo."
                fill
                preload
                sizes="(max-width: 900px) min(100vw, 480px), 520px"
              />
              <figcaption className={story.callouts}>
                <span className={story.callout} style={{ left: "47%", top: "16%" }}>
                  Always on. No passcode, no apps.
                </span>
                <span className={story.callout} style={{ left: "6%", top: "86%" }}>
                  Real buttons with faces and names
                </span>
              </figcaption>
            </figure>
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
