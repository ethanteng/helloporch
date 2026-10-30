"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { accessories, ipadNeeds, phoneCost, phoneParts, priceLabel, type Part } from "./parts";
import styles from "./pilot.module.css";

type Choice = "touch" | "phone";

// Three steps every family goes through, then a plan for the way their family member will call.
// The touchscreen and number pads ship through TestFlight today; the big-button phone needs Apple's
// DriverKit approval for the Cell2Jack driver first.
export default function PilotGuide() {
  const [hasIpad, setHasIpad] = useState<boolean | null>(null);
  const [choice, setChoice] = useState<Choice | null>(null);
  const plan = useRef<HTMLDivElement>(null);

  // Bring the plan into view each time the choice changes.
  useEffect(() => {
    if (choice) plan.current?.scrollIntoView({ block: "start" });
  }, [choice]);

  return (
    <>
      <ol className={styles.steps}>
        <li className={styles.step}>
          <h2>Porch is only on iPad and iPhone for now.</h2>
          <p>
            There’s no Android app yet. Family without an iPhone can still talk with your family member by
            voice, from any phone.
          </p>
          <ul className={styles.platforms}>
            <li>
              <strong>Their iPad</strong> runs Porch by their chair or bed.
            </li>
            <li>
              <strong>Family iPhones</strong> get the Porch app for video calls, drop-ins and messages.
            </li>
            <li>
              <strong>Any other phone</strong> can call Porch’s own phone number, and Porch can call it.
            </li>
          </ul>
        </li>

        <li className={styles.step}>
          <h2 id="ipad-question">Do you have a recent iPad?</h2>
          <p>Porch runs on an iPad that stays plugged in and on your Wi-Fi, so a spare one is perfect.</p>
          <div className={styles.answers} role="group" aria-labelledby="ipad-question">
            <button type="button" aria-pressed={hasIpad === true} onClick={() => setHasIpad(true)}>
              Yes, we have one
            </button>
            <button type="button" aria-pressed={hasIpad === false} onClick={() => setHasIpad(false)}>
              No, not yet
            </button>
          </div>
          <div aria-live="polite">
            {hasIpad !== null && (
              <div className={styles.answer}>
                {hasIpad ? (
                  <p>
                    <strong>Check that it’s new enough.</strong> To see its model and iPadOS version, open{" "}
                    <strong>Settings → General → About</strong>.
                  </p>
                ) : (
                  <p>
                    <strong>You’ll need one before you start.</strong> A refurbished or hand-me-down iPad is
                    fine, as long as it’s new enough.
                  </p>
                )}
                <ul>
                  <li>
                    <strong>For the touchscreen or a number pad:</strong> {ipadNeeds.touch}
                  </li>
                  <li>
                    <strong>For a big-button phone:</strong> {ipadNeeds.phone}
                  </li>
                </ul>
              </div>
            )}
          </div>
        </li>

        <li className={styles.step}>
          <h2 id="call-question">How will your family member call?</h2>
          <p>Choose what’s easiest for them. You can start one way and change later.</p>
          <div className={styles.choices} role="group" aria-labelledby="call-question">
            <button type="button" aria-pressed={choice === "touch"} onClick={() => setChoice("touch")}>
              <span className={`${styles.status} ${styles.ready}`}>Ready now</span>
              <span className={styles.choiceTitle}>The touchscreen or a number pad</span>
              <span className={styles.choiceText}>
                They tap the iPad’s screen to call someone, or press a key on a USB or Bluetooth number pad.
              </span>
            </button>
            <button type="button" aria-pressed={choice === "phone"} onClick={() => setChoice("phone")}>
              <span className={styles.status}>Waiting on Apple</span>
              <span className={styles.choiceTitle}>A big-button phone</span>
              <span className={styles.choiceText}>
                They pick up a corded home phone and press someone’s photo to call them.
              </span>
            </button>
          </div>
        </li>
      </ol>

      {choice && (
        <div ref={plan} className={styles.plan}>
          {choice === "touch" ? <TouchPlan /> : <PhonePlan onStartNow={() => setChoice("touch")} />}
        </div>
      )}
    </>
  );
}

function TouchPlan() {
  return (
    <>
      <section className={styles.planCard} aria-labelledby="plan-title">
        <figure className={styles.planPhoto}>
          <Image
            src="/pilot/ipad.jpg"
            alt="An iPad in its stand, showing Porch’s clock and a Call someone button."
            width={900}
            height={900}
            sizes="(max-width: 900px) min(100vw, 560px), 460px"
          />
        </figure>
        <div className={styles.planCopy}>
          <p className={`${styles.status} ${styles.ready}`}>Ready now</p>
          <h2 id="plan-title">You can start right away.</h2>
          <p className={styles.planIntro}>
            All you need is the iPad. Porch isn’t on the App Store yet, so it comes through{" "}
            <a href="https://apps.apple.com/app/testflight/id899247664">TestFlight</a>, Apple’s free app for
            trying apps before they’re released.
          </p>
          <ol className={styles.howSteps}>
            <li>
              <h3>Porch shows a big clock.</h3>
              <p>It stays on screen until someone calls, or until they want to call someone.</p>
            </li>
            <li>
              <h3>They tap to call.</h3>
              <p>
                They tap <strong>Call someone</strong>, then the person they want. Family with the Porch app
                get a video call, and anyone else gets a voice call on their regular phone.
              </p>
            </li>
            <li>
              <h3>Or they press a key.</h3>
              <p>With a number pad, each key can call someone you choose.</p>
            </li>
          </ol>
        </div>
      </section>

      <section className={styles.section} aria-labelledby="extras-title">
        <div className={styles.sectionIntro}>
          <h3 id="extras-title">Extras you might want</h3>
          <p>None of these are required. Below is what I use, but you’re free to shop around.</p>
        </div>
        <div className={styles.parts}>
          {accessories.map((part) => (
            <PartCard key={part.id} part={part} />
          ))}
        </div>
        <p className={styles.note}>
          Prices are from Amazon in October 2026 and may change, and other brands will cost more or less.
        </p>
      </section>

      <section className={styles.section} aria-labelledby="install-title">
        <div className={styles.sectionIntro}>
          <h3 id="install-title">Installing Porch with TestFlight</h3>
          <p>Install it on the iPad, and on the iPhone of each family member who wants the Porch app.</p>
        </div>
        <ol className={styles.install}>
          <li>
            <h4>Get TestFlight.</h4>
            <p>Install it from the App Store on the iPad, and on each of those iPhones.</p>
          </li>
          <li>
            <h4>Send me email addresses.</h4>
            <p>
              I need the Apple Account email for each of those devices. I’ll send each one an invitation to
              the Porch pilot.
            </p>
          </li>
          <li>
            <h4>Accept the invitation.</h4>
            <p>
              Open the email on that device and tap <strong>View in TestFlight</strong>, then{" "}
              <strong>Accept</strong> and <strong>Install</strong>.
            </p>
          </li>
          <li>
            <h4>Set up the iPad.</h4>
            <p>
              I’ll send a private link that makes the iPad your family’s Porch. Then you choose a caregiver PIN
              and invite each person from inside the app.
            </p>
          </li>
        </ol>
        <p className={styles.note}>
          Turn on automatic updates in TestFlight, because each test version stops working after 90 days.
        </p>
      </section>
    </>
  );
}

function PhonePlan({ onStartNow }: { onStartNow: () => void }) {
  return (
    <>
      <section className={styles.planCard} aria-labelledby="plan-title">
        <figure className={styles.planPhoto}>
          <Image
            src="/pilot/setup.jpg"
            alt="The Porch prototype on a coffee table: an iPad on a black stand showing a large clock, beside a white big-button phone with family photos on its keys."
            width={1200}
            height={1600}
            sizes="(max-width: 900px) min(100vw, 560px), 460px"
          />
          <figcaption>The working prototype: an iPad on its stand, and a big-button phone.</figcaption>
        </figure>
        <div className={styles.planCopy}>
          <p className={styles.status}>Waiting on Apple</p>
          <h2 id="plan-title">The phone is waiting on Apple’s approval.</h2>
          <p className={styles.planIntro}>
            The big-button phone connects to the iPad through a small adapter called a Cell2Jack. Porch needs
            Apple’s approval to use it, and I’m still waiting for that to come through. I’ll be in touch as
            soon as it does.
          </p>
          <ol className={styles.howSteps}>
            <li>
              <h3>They press a photo to call.</h3>
              <p>
                Each big button has a photo of someone you choose. They lift the receiver and press a photo to
                call that person.
              </p>
            </li>
            <li>
              <h3>They talk on the iPad.</h3>
              <p>They see and hear you on its screen and speaker, not through the receiver.</p>
            </li>
            <li>
              <h3>They hang up the phone.</h3>
              <p>Putting the receiver back ends the call.</p>
            </li>
          </ol>
          <div className={styles.startNow}>
            <p>
              <strong>Want to start sooner?</strong> Start with the touchscreen now, and add the phone once
              Apple approves it.
            </p>
            <button type="button" onClick={onStartNow}>
              Start with the touchscreen
            </button>
          </div>
        </div>
      </section>

      <section className={styles.section} aria-labelledby="kit-title">
        <div className={styles.sectionIntro}>
          <h3 id="kit-title">What you’ll need for the phone</h3>
          <p>
            There’s no need to buy anything until it’s approved. Below is what I use, and you can shop around
            for everything but the Cell2Jack.
          </p>
        </div>
        <div className={styles.parts}>
          {phoneParts.map((part) => (
            <PartCard key={part.id} part={part} />
          ))}
          <aside className={styles.total} aria-labelledby="total-title">
            <h4 id="total-title">Your shopping list</h4>
            <ul>
              {phoneParts.map((part) => (
                <li key={part.id}>
                  <span>{part.name}</span>
                  <span>{priceLabel(part)}</span>
                </li>
              ))}
            </ul>
            <p>
              <span>Total</span>
              <span>About ${phoneCost} + iPad</span>
            </p>
          </aside>
        </div>
        <p className={styles.note}>
          Prices are from Amazon in October 2026 and may change, and other brands will cost more or less.
        </p>
      </section>
    </>
  );
}

function PartCard({ part }: { part: Part }) {
  const price = priceLabel(part);
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
          <h4 id={`${part.id}-title`}>{part.name}</h4>
          {price && <span className={styles.price}>{price}</span>}
        </div>
        <p className={`${styles.rule} ${part.rule.exact ? styles.exact : ""}`}>
          <strong>{part.rule.label}.</strong> {part.rule.text}
        </p>
        <p>{part.description}</p>
        {part.href && (
          <a href={part.href} className={styles.buy} target="_blank" rel="noopener noreferrer">
            {part.rule.exact ? "Buy on Amazon" : "View on Amazon"}
            <span className={styles.visuallyHidden}> (opens in a new tab)</span>
          </a>
        )}
      </div>
    </article>
  );
}
