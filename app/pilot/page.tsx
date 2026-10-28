import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import { equipmentCost, parts, type Part } from "./parts";
import styles from "./pilot.module.css";

export const metadata: Metadata = {
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "What a pilot family provides for Porch: an iPad, a stand, a USB hub, a big-button phone and a Cell2Jack. Then how to install the Porch app with TestFlight.",
};

export default function PilotPage() {
  return (
    <WaitlistProvider>
      <div className={`page ${styles.page}`}>
        <SiteNav current="pilot" />

        <main>
          <header className={styles.hero}>
            <div className="hero__badge">For families in our pilot program</div>
            <h1 className={styles.title}>
              Getting ready for <em>the Porch pilot.</em>
            </h1>
            <p className={styles.lede}>
              Thank you for helping me test Porch. You provide the equipment: an iPad and a big-button phone,
              plus a few parts to connect them. Porch is the app that runs on it. Here’s what to get and how to
              install the app.
            </p>
          </header>

          <section className={styles.fit} aria-labelledby="fit-title">
            <figure className={styles.setup}>
              <Image
                src="/pilot/setup.jpg"
                alt="The Porch prototype on a coffee table: an iPad on a black stand showing a large clock, beside a white big-button phone with family photos on its keys."
                width={1200}
                height={1600}
                sizes="(max-width: 900px) min(100vw, 560px), 460px"
              />
              <figcaption>The working prototype: an iPad on its stand, and a big-button phone.</figcaption>
            </figure>
            <div className={styles.fitCopy}>
              <h2 id="fit-title">How it fits together</h2>
              <p className={styles.fitIntro}>
                Porch is an app on an iPad. The big-button phone lets your family member use it without
                swiping or tapping through menus.
              </p>
              <ol className={styles.fitSteps}>
                <li>
                  <h3>The iPad runs Porch.</h3>
                  <p>It shows a big clock until someone calls. The stand holds it at eye level by their chair or bed.</p>
                </li>
                <li>
                  <h3>The hub keeps it charged.</h3>
                  <p>It plugs into the iPad’s charging port. The charger plugs into the hub, leaving a port for the phone.</p>
                </li>
                <li>
                  <h3>The phone starts calls.</h3>
                  <p>
                    Each big button has a photo of someone you choose. They lift the receiver and press a photo
                    to call that person. A Cell2Jack connects the phone to the hub.
                  </p>
                </li>
                <li>
                  <h3>They talk on the iPad.</h3>
                  <p>
                    They see and hear you on its screen and speaker, not through the receiver. Family with the
                    Porch app on their iPhone get a video call. Anyone else gets a voice call on their regular
                    phone, with no app needed.
                  </p>
                </li>
                <li>
                  <h3>It has its own phone number.</h3>
                  <p>
                    Your family member’s Porch gets a new phone number. Family and friends can call it from any
                    phone, and it rings on the iPad as a voice call. You can block callers you haven’t approved.
                  </p>
                </li>
              </ol>
            </div>
          </section>

          <section className={styles.section} aria-labelledby="kit-title">
            <div className={styles.sectionIntro}>
              <h2 id="kit-title">The equipment you provide</h2>
              <p>
                You provide all of the hardware, including the iPad. Below is what I use, but you’re free to
                shop around or use what you already have. The one part that has to match is the Cell2Jack.
              </p>
            </div>
            <div className={styles.parts}>
              {parts.map((part) => (
                <PartCard key={part.id} part={part} />
              ))}
              <aside className={styles.total} aria-labelledby="total-title">
                <h3 id="total-title">What mine cost</h3>
                <ul>
                  {parts.map((part) => (
                    <li key={part.id}>
                      <span>{part.name}</span>
                      <span>{part.cost ? `$${part.cost}` : "Your own"}</span>
                    </li>
                  ))}
                </ul>
                <p>
                  <span>Total</span>
                  <span>${equipmentCost} + iPad</span>
                </p>
              </aside>
            </div>
            <p className={styles.note}>
              To find your iPad’s model, open <strong>Settings → General → About</strong>. Prices are from Amazon
              in October 2026 and may change.
            </p>
          </section>

          <section className={styles.section} aria-labelledby="install-title">
            <div className={styles.sectionIntro}>
              <h2 id="install-title">Installing the Porch app</h2>
              <p>
                Porch is an app you install on the iPad. Family members can install it on their iPhones too,
                if they’d like.
              </p>
            </div>
            <div className={styles.devices}>
              <div>
                <p className={`${styles.need} ${styles.required}`}>Required</p>
                <h3>On the iPad</h3>
                <p>
                  This is your family member’s Porch. It shows the clock, rings when someone calls, and calls
                  whoever they press on the phone.
                </p>
              </div>
              <div>
                <p className={styles.need}>Optional</p>
                <h3>On family iPhones</h3>
                <p>
                  For video calls, drop-ins and messages with your family member. There’s no Android app yet,
                  but Porch can still call any phone number for a voice call.
                </p>
              </div>
            </div>
            <p className={styles.note}>
              Porch isn’t on the App Store yet, so it installs with{" "}
              <a href="https://apps.apple.com/app/testflight/id899247664">TestFlight</a>, Apple’s free app for
              trying apps before they’re released.
            </p>
            <ol className={styles.install}>
              <li>
                <h3>Get TestFlight.</h3>
                <p>
                  Install it from the App Store on the iPad, and on the iPhone of each family member who wants
                  the Porch app.
                </p>
              </li>
              <li>
                <h3>Send me email addresses.</h3>
                <p>
                  I need the Apple Account email for each of those devices. I’ll send each one an invitation
                  to the Porch pilot.
                </p>
              </li>
              <li>
                <h3>Accept the invitation.</h3>
                <p>
                  Open the email on that device and tap <strong>View in TestFlight</strong>, then{" "}
                  <strong>Accept</strong> and <strong>Install</strong>.
                </p>
              </li>
              <li>
                <h3>Set up the iPad.</h3>
                <p>
                  I’ll send a private link that makes the iPad your family’s Porch. Then you choose a caregiver
                  PIN and invite each person from inside the app.
                </p>
              </li>
            </ol>
            <p className={styles.note}>
              Turn on automatic updates in TestFlight, because each test version stops working after 90 days.
            </p>
          </section>

          <section className={styles.section} aria-labelledby="involves-title">
            <div className={styles.sectionIntro}>
              <h2 id="involves-title">What the pilot asks of you</h2>
            </div>
            <ul className={styles.involves}>
              <li>
                <h3>All the equipment, including the iPad.</h3>
                <p>A newer iPad, plus a stand, hub, phone and Cell2Jack. Mine cost about ${equipmentCost}.</p>
              </li>
              <li>
                <h3>A spot with Wi-Fi and an outlet.</h3>
                <p>Somewhere your family member spends their day, with the iPad left on and open to Porch.</p>
              </li>
              <li>
                <h3>Patience with rough edges.</h3>
                <p>Porch is a prototype. Some things will break, and updates will come often.</p>
              </li>
              <li>
                <h3>Your honest feedback.</h3>
                <p>Tell me what works, what doesn’t, and what you wish it did.</p>
              </li>
            </ul>
          </section>

          <section id="join" className={styles.join} aria-labelledby="join-title">
            <h2 id="join-title">
              Know a family who <em>could use Porch?</em>
            </h2>
            <p className={styles.joinBody}>
              They can join the waitlist here, and I’ll email them when Porch is ready for more families.
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

function PartCard({ part }: { part: Part }) {
  return (
    <article className={styles.part} aria-labelledby={`${part.id}-title`}>
      <Image
        src={part.photo.src}
        alt={part.photo.alt}
        width={900}
        height={900}
        sizes="(max-width: 900px) min(100vw, 440px), 380px"
        className={styles.partPhoto}
      />
      <div className={styles.partCopy}>
        <div className={styles.partHeading}>
          <h3 id={`${part.id}-title`}>{part.name}</h3>
          <span className={styles.price}>{part.cost ? `$${part.cost}` : "Your own"}</span>
        </div>
        <p className={`${styles.rule} ${part.rule.exact ? styles.exact : ""}`}>
          <strong>{part.rule.label}.</strong> {part.rule.text}
        </p>
        <p>{part.description}</p>
        {part.href && (
          <a href={part.href} className={styles.buy} target="_blank" rel="noopener noreferrer">
            View on Amazon<span className={styles.visuallyHidden}> (opens in a new tab)</span>
          </a>
        )}
      </div>
    </article>
  );
}
