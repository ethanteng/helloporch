import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import PorchFace from "@/components/PorchFace";
import SiteFooter from "@/components/SiteFooter";
import SiteNav from "@/components/SiteNav";
import { WaitlistProvider } from "@/components/Waitlist";
import { Arrow, JoinSection, PilotButton } from "@/components/PilotJoin";
import { CallLog, Compare, DeviceIllustration, FounderNote, KeysCloseUp, SafetySection } from "./_home/parts";
import styles from "./_home/home.module.css";
import { clip } from "./features/clips";
import { AddPersonIcon, PhoneIcon, TextIcon } from "./features/icons";
import WatchClip from "./features/WatchClip";
import { pageMetadata } from "@/lib/site-metadata";

export const metadata: Metadata = pageMetadata({
  path: "/",
  title: "HelloPorch | A video phone for people with dementia, Parkinson’s or shaky hands",
  description: "Porch is a tablet and a big-button keypad with photos of loved ones on the buttons. One press starts a video call. Made for Parkinson’s, dementia and shaky hands.",
  shareTitle: "Video calling for people who struggle with phones",
  image: { url: "/og/home.jpg", alt: "HelloPorch: video calling for people who struggle with phones, beside Ethan’s mom on her first Porch call." },
});

// Who Porch is for and what it is, beside Mom's first real call; what's hard for them; who can call; and the pilot as
// the way to try it now, with the keypad we're designing and its waitlist after.
export default function Home() {
  return (
    <WaitlistProvider>
      <div className="page">
        <SiteNav />

        <header className={styles.splitHero}>
          <div className={styles.splitCopy}>
            <h1 className={`${styles.splitTitle} ${styles.splitTitleLong}`}>
              Video calling for people who <em>struggle with phones.</em>
            </h1>
            <div className={styles.ledeGroup}>
              <p className={styles.splitLede}>
                Porch pairs a tablet with a big-button keypad, with photos of friends and loved ones on each button.{" "}
                <strong>One press starts a video call.</strong>
              </p>
              <p className={styles.splitLede}>
                It’s made for people with Parkinson’s, dementia, unsteady hands, or anyone who finds today’s phones too
                difficult to use.
              </p>
            </div>
            <div className={styles.heroActions}>
              <PilotButton size="lg" />
            </div>
          </div>
          <div className={styles.heroMedia}>
            <figure className={styles.momPhoto}>
              <Image
                src="/features/first-real-call.jpg"
                alt="Ethan's mom at her desk, holding the handset of a big-button phone, talking to her son on the tablet beside it."
                fill
                preload
                sizes="(max-width: 900px) 100vw, 460px"
              />
            </figure>
            <WatchClip clip={clip("first-real-call")} label="Watch my mom’s first real Porch call" />
          </div>
        </header>

        <section className={styles.needs} aria-labelledby="needs-title">
          <h2 id="needs-title" className={styles.centerTitle}>
            What’s hard <em>for them?</em>
          </h2>
          <div className={styles.needsGrid}>
            <article className={styles.need}>
              <div className={styles.needArt}>
                <div style={{ zoom: 0.62 }}>
                  <KeysCloseUp />
                </div>
              </div>
              <p className={styles.needIf}>If their hands shake</p>
              <h3>Big, firm buttons.</h3>
              <p>A light tap works, and so does a heavy press. They never have to hit a tiny icon on glass.</p>
            </article>
            <article className={styles.need}>
              <div className={styles.needArt}>
                <div className="incoming" style={{ zoom: 0.8 }}>
                  <div className="incoming__screen">
                    <div className="incoming__face">
                      <PorchFace who="mike" size={58} />
                    </div>
                    <div className="incoming__title">Mike is calling</div>
                    <div className="incoming__pill">Answering automatically</div>
                  </div>
                </div>
              </div>
              <p className={styles.needIf}>If they have memory loss</p>
              <h3>Always where they left it.</h3>
              <p>
                Porch stays plugged in on their table, so it’s never lost or out of charge. They press a face instead of
                remembering a number, and Porch answers your calls for them.
              </p>
            </article>
            <article className={styles.need}>
              <div className={styles.needArt}>
                <div className={styles.langPills} aria-hidden="true">
                  <span>普通话</span>
                  <span>廣東話</span>
                  <span>Español</span>
                  <span>English</span>
                  <span data-soon>More soon</span>
                </div>
              </div>
              <p className={styles.needIf}>If English isn’t their first language</p>
              <h3>Their own language.</h3>
              <p>Porch shows and speaks Mandarin, Cantonese, or Spanish, and translates your texts before reading them aloud. More languages are coming soon.</p>
            </article>
            <article className={styles.need}>
              <div className={styles.needArt}>
                <div style={{ zoom: 0.46 }}>
                  <CallLog compact />
                </div>
              </div>
              <p className={styles.needIf}>If you worry about scams</p>
              <h3>Only people you choose.</h3>
              <p>Unknown numbers are blocked by default. Porch only picks up for family you’ve approved.</p>
            </article>
          </div>
        </section>

        <Compare />

        <SafetySection
          title={
            <>
              Only the people you choose <em>get through.</em>
            </>
          }
        >
          Call any time and Porch picks up for them, but only for family you’ve approved. It says who’s calling out loud,
          and counts down before answering. Numbers you haven’t approved are blocked by default so scam calls never reach
          them.
        </SafetySection>

        <section className={styles.more} aria-labelledby="more-title">
          <h2 id="more-title" className={styles.centerTitle}>
            A few more things <em>it does.</em>
          </h2>
          <div className={styles.moreGrid}>
            <article>
              <span className={styles.moreIcon}>
                <TextIcon />
              </span>
              <h3>Messages that play themselves</h3>
              <p>
                Send your loved one a video or text message. When they sit down in front of Porch, it plays the video or
                reads the message aloud. No tapping or navigating required.
              </p>
            </article>
            <article>
              <span className={styles.moreIcon}>
                <AddPersonIcon />
              </span>
              <h3>Bring others into the call</h3>
              <p>
                Add a friend or family member to the conversation. You can even bring in a bank representative when they
                need to speak with your loved one directly.
              </p>
            </article>
            <article>
              <span className={styles.moreIcon}>
                <PhoneIcon />
              </span>
              <h3>Video first. Regular phone if needed.</h3>
              <p>Porch calls you on video first. If you don’t pick up, it automatically tries your regular phone instead.</p>
            </article>
          </div>
          <Link href="/features" className={styles.textLink}>
            Watch each one in action <Arrow />
          </Link>
        </section>

        <FounderNote />

        <section className={styles.next} aria-labelledby="next-title">
          <p className={styles.kicker}>What we’re building next</p>
          <h2 id="next-title" className={styles.centerTitle}>
            Our own <em>keypad.</em>
          </h2>
          <p className={styles.centerBody}>
            Photo buttons for the people they call most, and a red button that calls everyone on their list until
            someone picks up.
          </p>
        </section>
        <DeviceIllustration tag="In design" />

        <JoinSection />

        <SiteFooter />
      </div>
    </WaitlistProvider>
  );
}
