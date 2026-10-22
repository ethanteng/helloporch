import { Fragment } from "react";
import type { Metadata } from "next";
import Image from "next/image";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import { JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";
import { numberPad, phoneKit, shared, type Part } from "./parts";
import styles from "./pilot.module.css";

export const metadata: Metadata = {
  title: "Join the Porch Pilot | HelloPorch",
  description:
    "What a pilot family needs for Porch: an iPad, a stand, a USB hub and a keypad, the two ways to get set up, and how to install the app with TestFlight.",
};

type Option = {
  id: string;
  kicker: string;
  title: string;
  facts: [label: string, detail: string][];
  pros: string[];
  cons: string[];
};

// The two setups. The big-button phone needs a USB driver Apple hasn't approved for TestFlight yet,
// so I install that version on each iPad myself until it does.
const options: Option[] = [
  {
    id: "number-pad",
    kicker: "Set it up yourself",
    title: "Touchscreen and number pad",
    facts: [
      ["iPad", "Any iPad with iPadOS 15 or later. If it has a Lightning port instead of USB-C, let me know and I’ll suggest an adapter."],
      ["Setup", "You install Porch with TestFlight, using an invitation from me."],
      ["Updates", "Arrive on their own through TestFlight."],
      ["Cost", "About $79 for the stand, hub and number pad."],
    ],
    pros: [
      "Works with almost any spare iPad, including older ones.",
      "You can start right away, with nothing to ship.",
      "Costs less, with fewer cables.",
    ],
    cons: [
      "The keys show numbers, not faces, so they need to know who each number calls.",
      "It looks like a computer accessory, not a phone, and has extra keys that don’t call anyone.",
      "The keys are small for shaky hands.",
    ],
  },
  {
    id: "big-button-phone",
    kicker: "I set it up for you",
    title: "Big-button phone",
    facts: [
      ["iPad", "One with an M-series chip and iPadOS 16 or later: an iPad Pro from 2021 or later, or an iPad Air from 2022 or later."],
      ["Setup", "I install a special version of Porch that works with the phone. In the Bay Area, I’ll come to you. Elsewhere, mail me the iPad and I’ll send it back ready to go."],
      ["Updates", "Come from me until Apple approves our app. After that, they arrive on their own."],
      ["Cost", "About $114 for the stand, hub, Cell2Jack and phone."],
    ],
    pros: [
      "Feels like the phone they’ve used for years.",
      "Each button has a photo, so they can see who they’re calling.",
      "Big buttons are easier to press with shaky hands.",
    ],
    cons: [
      "Needs a newer iPad, and my help to set it up.",
      "The handset carries no sound. If they pick it up out of habit, they still talk and listen through the iPad.",
      "More parts and cables, for about $35 more.",
    ],
  },
];

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
              Thank you for helping me test Porch. Here’s how it fits together, the two ways to set it up, and
              what you’ll need.
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
              <figcaption>The working prototype, with a big-button phone as its keypad.</figcaption>
            </figure>
            <div className={styles.fitCopy}>
              <h2 id="fit-title">How it fits together</h2>
              <p className={styles.fitIntro}>
                Porch is an app on an iPad. The rest of the equipment lets your family member use it without
                swiping or tapping through menus.
              </p>
              <ol className={styles.fitSteps}>
                <li>
                  <h3>The iPad runs Porch.</h3>
                  <p>It shows a big clock until someone calls. The stand holds it at eye level by their chair or bed.</p>
                </li>
                <li>
                  <h3>The hub keeps it charged.</h3>
                  <p>It plugs into the iPad’s charging port. The charger plugs into the hub, leaving a port for the keypad.</p>
                </li>
                <li>
                  <h3>The keypad starts calls.</h3>
                  <p>Each key calls someone you choose, whether it’s a photo button on a big-button phone or a number on a number pad.</p>
                </li>
                <li>
                  <h3>You talk on the iPad.</h3>
                  <p>
                    They see and hear you on its screen and speaker. Family with the Porch app on their iPhone get
                    a video call. Anyone else gets a voice call on their regular phone, with no app needed.
                  </p>
                </li>
                <li>
                  <h3>It has its own phone number.</h3>
                  <p>
                    Your family member’s Porch gets a new phone number. Family and friends can call it from any
                    phone, and it rings on the iPad as a voice call.
                  </p>
                </li>
              </ol>
            </div>
          </section>

          <section className={styles.section} aria-labelledby="options-title">
            <div className={styles.sectionIntro}>
              <h2 id="options-title">Two ways to set it up</h2>
              <p>
                Calls, drop-ins and messages work the same either way. The difference is what your family
                member presses, and who installs Porch on the iPad.
              </p>
            </div>
            <div className={styles.options}>
              {options.map((option, index) => (
                <Fragment key={option.id}>
                  {index > 0 && <p className={styles.or}>Or</p>}
                  <article className={styles.option} aria-labelledby={`${option.id}-title`}>
                    <div className={styles.optionHeading}>
                      <p className={styles.kicker}>{option.kicker}</p>
                      <h3 id={`${option.id}-title`}>{option.title}</h3>
                    </div>
                    <dl className={styles.facts}>
                      {option.facts.map(([label, detail]) => (
                        <div key={label}>
                          <dt>{label}</dt>
                          <dd>{detail}</dd>
                        </div>
                      ))}
                    </dl>
                    <div className={styles.tradeoffs}>
                      <div>
                        <h4>Why choose it</h4>
                        <ul className={styles.pros}>
                          {option.pros.map((pro) => (
                            <li key={pro}>{pro}</li>
                          ))}
                        </ul>
                      </div>
                      <div>
                        <h4>Keep in mind</h4>
                        <ul className={styles.cons}>
                          {option.cons.map((con) => (
                            <li key={con}>{con}</li>
                          ))}
                        </ul>
                      </div>
                    </div>
                  </article>
                </Fragment>
              ))}
            </div>
            <p className={styles.note}>
              To find your iPad’s model, open <strong>Settings → General → About</strong>.
            </p>
          </section>

          <section className={styles.section} aria-labelledby="kit-title">
            <div className={styles.sectionIntro}>
              <h2 id="kit-title">What you’ll need</h2>
              <p>Everyone needs an iPad, a stand and a hub. Then add the keypad you chose.</p>
            </div>
            <div className={styles.parts}>
              {shared.map((part) => (
                <PartCard key={part.id} part={part} />
              ))}
            </div>
            <div className={styles.keypads}>
              <section className={styles.keypadGroup} aria-labelledby="number-pad-kit">
                <h3 id="number-pad-kit">
                  Number pad <span>· $30</span>
                </h3>
                <p>Plugs straight into the hub.</p>
                <div className={styles.groupParts}>
                  {numberPad.map((part) => (
                    <PartCard key={part.id} part={part} nested />
                  ))}
                </div>
              </section>
              <section className={styles.keypadGroup} aria-labelledby="phone-kit">
                <h3 id="phone-kit">
                  Or the big-button phone <span>· $65 for both</span>
                </h3>
                <p>You need both: the phone plugs into the Cell2Jack, and the Cell2Jack plugs into the hub.</p>
                <div className={`${styles.groupParts} ${styles.groupPartsTwo}`}>
                  {phoneKit.map((part) => (
                    <PartCard key={part.id} part={part} nested />
                  ))}
                </div>
              </section>
            </div>
            <p className={styles.note}>Prices are from Amazon in October 2026 and may change.</p>
          </section>

          <section className={styles.section} aria-labelledby="install-title">
            <div className={styles.sectionIntro}>
              <h2 id="install-title">Installing the app</h2>
              <p>
                Porch isn’t on the App Store yet, so it installs with{" "}
                <a href="https://apps.apple.com/app/testflight/id899247664">TestFlight</a>, Apple’s free app for
                trying apps before they’re released. Family members who want the Porch app on their iPhone use
                it, and so does the iPad if you’re setting it up yourself.
              </p>
            </div>
            <ol className={styles.install}>
              <li>
                <h3>Get TestFlight.</h3>
                <p>
                  Install it from the App Store on the iPhone of each family member who wants the Porch app, and
                  on the iPad if you’re setting it up yourself.
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
                <h3>Set up the bedside.</h3>
                <p>
                  I’ll send a private link that makes the iPad your family’s Porch. Then you choose a caregiver
                  PIN and invite each person from inside the app. If I’m setting up your iPad, we’ll do this
                  part together.
                </p>
              </li>
            </ol>
            <p className={styles.note}>
              Turn on automatic updates in TestFlight, because each test version stops working after 90 days.
            </p>
          </section>

          <section className={styles.reach} aria-labelledby="reach-title">
            <h2 id="reach-title">
              Staying in touch, <em>app or no app.</em>
            </h2>
            <div className={styles.reachWays}>
              <div>
                <h3>The Porch app</h3>
                <p>
                  For video calls, drop-ins and messages. It’s iPhone and iPad only for now, with no Android app
                  yet.
                </p>
              </div>
              <div>
                <h3>Any phone</h3>
                <p>
                  Porch can call anyone’s regular phone number for a voice call, so family on Android or a
                  landline can still pick up. No app needed.
                </p>
              </div>
              <div>
                <h3>Their own Porch number</h3>
                <p>
                  Your family member gets a new phone number for their Porch. Share it with family and friends
                  so they can save it in their contacts and call any time. You can block callers you haven’t
                  approved.
                </p>
              </div>
            </div>
          </section>

          <section className={styles.section} aria-labelledby="involves-title">
            <div className={styles.sectionIntro}>
              <h2 id="involves-title">What the pilot asks of you</h2>
            </div>
            <ul className={styles.involves}>
              <li>
                <h3>A spare iPad and $79 to $114 of equipment.</h3>
                <p>Depending on the keypad you choose.</p>
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

// Cards inside a keypad group sit under that group's h3, so their names drop to h4.
function PartCard({ part, nested = false }: { part: Part; nested?: boolean }) {
  const Heading = nested ? "h4" : "h3";
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
          <Heading id={`${part.id}-title`}>{part.name}</Heading>
          <span className={styles.price}>{part.price}</span>
        </div>
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
