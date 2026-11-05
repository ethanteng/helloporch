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
              The video phone for people who <em>find phones hard.</em>
            </h1>
            <div className={styles.ledeGroup}>
              <p className={styles.splitLede}>
                Porch is a tablet and big-button keypad with photos of friends &amp; loved ones on the buttons.{" "}
                <strong>One button press immediately starts a video call.</strong>
              </p>
              <p className={styles.splitLede}>
                It’s made for people with Parkinson’s, dementia, or shaky hands, and for anyone who isn’t comfortable with
                technology.
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
              <p>Unknown numbers are blocked from day one. Porch only picks up for family you’ve approved.</p>
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
              <h3>Messages play on their own</h3>
              <p>Send a video or a text. When she sits down in front of the tablet, Porch plays it or reads it aloud.</p>
            </article>
            <article>
              <span className={styles.moreIcon}>
                <AddPersonIcon />
              </span>
              <h3>Add someone to the call</h3>
              <p>Bring your brother onto the call, or the bank when they need to hear her say it’s OK.</p>
            </article>
            <article>
              <span className={styles.moreIcon}>
                <PhoneIcon />
              </span>
              <h3>It still reaches you</h3>
              <p>Porch tries a video call in the app first. If you don’t answer, it rings your regular phone.</p>
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
