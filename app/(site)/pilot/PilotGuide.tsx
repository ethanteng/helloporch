"use client";

import Image from "next/image";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { ipadNeeds, keypadParts, phoneCost, phoneParts, priceLabel, type Part } from "./parts";
import styles from "./pilot.module.css";

type Choice = "keypad" | "phone";
type IosAnswers = { platform: "ios"; email: string; choice: Choice; hasIpad: boolean };
type AndroidAnswers = { platform: "android"; email: string };
type Answers = IosAnswers | AndroidAnswers;

const EMAIL_RE = /\S+@\S+\.\S+/;

async function signUp(body: Record<string, unknown>) {
  const res = await fetch("/api/pilot", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error((await res.json().catch(() => null))?.error || "Something went wrong");
}

// The pilot sign-up form, then a plan for the way their family member will call. Email comes first, then
// whether iOS works for them: HelloPorch is only on iPhone and iPad right now, and someone waiting for
// Android is saved with just their email. How they'll call comes before the iPad, because the big-button
// phone needs a newer iPad. Number pads ship through TestFlight today; the big-button phone needs Apple's
// DriverKit approval for the Cell2Jack driver.
export default function PilotGuide() {
  const [email, setEmail] = useState("");
  const [platform, setPlatform] = useState<"ios" | "android" | null>(null);
  const [choice, setChoice] = useState<Choice | null>(null);
  const [hasIpad, setHasIpad] = useState<boolean | null>(null);
  const [joined, setJoined] = useState<Answers | null>(null);
  const [editing, setEditing] = useState(true);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Set when "Start with a number pad" can't reuse a "no" to the phone's M1 question.
  const [reaskIpad, setReaskIpad] = useState(false);
  const emailInput = useRef<HTMLInputElement>(null);
  const platformGroup = useRef<HTMLDivElement>(null);
  const callGroup = useRef<HTMLDivElement>(null);
  const ipadGroup = useRef<HTMLDivElement>(null);
  const welcome = useRef<HTMLHeadingElement>(null);
  const scrollToIpad = useRef(false);
  const need = choice && ipadNeeds[choice];

  // The iPad they need depends on how they'll call, so a new choice asks about the iPad again.
  const pick = (next: Choice) => {
    if (next !== choice) {
      setHasIpad(null);
      if (next !== "keypad") setReaskIpad(false);
    }
    setChoice(next);
  };

  // A message about a missing step goes away once they change an answer. Platform is left out: choosing
  // Android sets it in the same moment the request starts, and this would wipe a failure from that request.
  useEffect(() => setError(null), [email, choice, hasIpad]);

  // Each sign-up, including a changed answer, brings the welcome and plan into view.
  useEffect(() => {
    if (!joined) return;
    welcome.current?.focus({ preventScroll: true });
    welcome.current?.scrollIntoView({ block: "start" });
  }, [joined]);

  // "Start with a number pad" opens the form again when the phone's iPad answer doesn't apply.
  useEffect(() => {
    if (!scrollToIpad.current || !editing) return;
    scrollToIpad.current = false;
    ipadGroup.current?.closest("li")?.scrollIntoView({ block: "start" });
    ipadGroup.current?.querySelector("button")?.focus({ preventScroll: true });
  }, [editing, choice, hasIpad]);

  const joinIos = async (answers: Omit<IosAnswers, "platform">) => {
    setPending(true);
    setError(null);
    try {
      await signUp({ email: answers.email, interface: answers.choice, ipad: answers.hasIpad });
      setChoice(answers.choice);
      setPlatform("ios");
      setReaskIpad(false);
      setJoined({ platform: "ios", ...answers });
      setEditing(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong");
    } finally {
      setPending(false);
    }
  };

  // Android has nothing else to ask, so this saves their email as soon as they choose it.
  const waitForAndroid = () => {
    if (pending) return;
    const value = email.trim();
    if (!EMAIL_RE.test(value)) {
      setError("Enter your email address.");
      emailInput.current?.focus();
      return;
    }
    setPlatform("android");
    setPending(true);
    setError(null);
    signUp({ email: value, platform: "android" })
      .then(() => {
        setReaskIpad(false);
        setJoined({ platform: "android", email: value });
        setEditing(false);
      })
      .catch((e) => setError(e instanceof Error ? e.message : "Something went wrong"))
      .finally(() => setPending(false));
  };

  // Points to the first step left unanswered, or signs them up.
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const value = email.trim();
    if (EMAIL_RE.test(value) && platform === "android") {
      waitForAndroid();
      return;
    }
    const missing: [string, HTMLElement | null | undefined] | null = !EMAIL_RE.test(value)
      ? ["Enter your email address.", emailInput.current]
      : platform !== "ios"
        ? ["Tell me if iOS works for you.", platformGroup.current?.querySelector("button")]
        : !choice
          ? ["Choose how your family member will call.", callGroup.current?.querySelector("button")]
          : hasIpad === null
            ? ["Tell me whether you have an iPad that will work.", ipadGroup.current?.querySelector("button")]
            : null;
    if (missing) {
      setError(missing[0]);
      missing[1]?.focus();
      return;
    }
    joinIos({ email: value, choice: choice!, hasIpad: hasIpad! });
  };

  if (joined && !editing) {
    if (joined.platform === "android") {
      return (
        <section className={`${styles.section} ${styles.welcomeSection}`} aria-labelledby="welcome-title">
          <div className={styles.welcome}>
            <h2 id="welcome-title" ref={welcome} tabIndex={-1}>
              I’ll email you when Android is ready.
            </h2>
            <p>
              Thank you. I’ll write to <strong>{joined.email}</strong> when HelloPorch is available on Android.
            </p>
            <button type="button" onClick={() => setEditing(true)}>
              Change your answer
            </button>
          </div>
        </section>
      );
    }

    return (
      <>
        <section className={`${styles.section} ${styles.welcomeSection}`} aria-labelledby="welcome-title">
          <div className={styles.welcome}>
            <h2 id="welcome-title" ref={welcome} tabIndex={-1}>
              You’re in the pilot.
            </h2>
            <p>
              Thank you. I’ll be in touch at <strong>{joined.email}</strong>. Here’s what happens next.
            </p>
            <button type="button" onClick={() => setEditing(true)}>
              Change your answers
            </button>
          </div>
        </section>
        {joined.choice === "keypad" ? (
          <KeypadPlan email={joined.email} hasIpad={joined.hasIpad} />
        ) : (
          <PhonePlan
            email={joined.email}
            onStartNow={() => {
              // An M1 iPad can run a number pad, so "yes" still holds. "No" only rules out an M1 iPad,
              // which is a different question than "an iPad from 2015 or later", so ask that before saving.
              if (joined.hasIpad) {
                void joinIos({ email: joined.email, choice: "keypad", hasIpad: true });
                return;
              }
              scrollToIpad.current = true;
              setReaskIpad(true);
              setError(null);
              setChoice("keypad");
              setHasIpad(null);
              setEditing(true);
            }}
            pending={pending}
            error={error}
          />
        )}
      </>
    );
  }

  return (
    <section className={styles.section} aria-labelledby="setup-title">
      <div className={styles.sectionIntro}>
        <h2 id="setup-title">Join the pilot</h2>
        <p>Fill this in, and you’ll see what to get and how to start.</p>
      </div>
      <form className={styles.form} onSubmit={onSubmit} noValidate>
        <ol className={styles.steps}>
          <li className={styles.step}>
            <h3>
              <label htmlFor="pilot-email">What’s your email?</label>
            </h3>
            <p>I’ll use it for your TestFlight invitation and to check in with you during the pilot.</p>
            <input
              ref={emailInput}
              id="pilot-email"
              className={styles.email}
              type="email"
              autoComplete="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </li>

          <li className={styles.step}>
            <h3 id="ios-question">HelloPorch is only available on iOS right now.</h3>
            <p>It runs on iPhone and iPad. There’s no Android app yet.</p>
            <div ref={platformGroup} className={styles.answers} role="group" aria-labelledby="ios-question">
              <button
                type="button"
                aria-pressed={platform === "ios"}
                onClick={() => {
                  setPlatform("ios");
                  setError(null);
                }}
                disabled={pending}
              >
                Sounds good
              </button>
              <button type="button" aria-pressed={platform === "android"} onClick={waitForAndroid} disabled={pending}>
                {pending && platform === "android" ? "Saving…" : "I’ll wait for Android"}
              </button>
            </div>
            {platform !== "ios" && error && (
              <p className="form-error" role="alert">
                {error}
              </p>
            )}
          </li>

          {platform === "ios" && (
          <>
          <li className={styles.step}>
            <h3 id="call-question">How do you want your loved one to make & receive calls?</h3>
            <p>Only the number pad option is available now. But you can start with that option and change to the big-button phone option later.</p>
            <div ref={callGroup} className={styles.choices} role="group" aria-labelledby="call-question">
              <button type="button" aria-pressed={choice === "keypad"} onClick={() => pick("keypad")}>
                <ChoicePhotos photos={[{ src: "/pilot/number-pad.jpg" }, { src: "/pilot/ipad.jpg" }]} />
                <span className={styles.choiceBody}>
                  <span className={`${styles.status} ${styles.ready}`}>Ready now</span>
                  <span className={styles.choiceTitle}>A USB number pad</span>
                  <span className={styles.choiceText}>
                    They press a key on a USB number pad to call someone, and talk on the iPad.
                  </span>
                </span>
              </button>
              <button type="button" aria-pressed={choice === "phone"} onClick={() => pick("phone")}>
                <ChoicePhotos
                  photos={[{ src: "/pilot/phone.jpg" }, { src: "/pilot/setup.jpg", position: "50% 30%" }]}
                />
                <span className={styles.choiceBody}>
                  <span className={styles.status}>Pending approval from Apple</span>
                  <span className={styles.choiceTitle}>A big-button phone</span>
                  <span className={styles.choiceText}>
                    They pick up a corded home phone and press someone’s photo to call them.
                  </span>
                </span>
              </button>
            </div>
          </li>

          {/* The iPad step waits for how they'll call, since that decides which iPad they need. */}
          {need && (
          <li className={styles.step}>
            <h3 id="ipad-question">{need.question}</h3>
            <div className={styles.need} aria-live="polite">
              <p className={styles.needLabel}>{need.label}</p>
              <p>{need.text}</p>
            </div>
            <p>
              Not sure which one you have? Open <strong>Settings → General → About</strong> to see its model name.
            </p>
            {reaskIpad && (
              <p>The phone needs a newer iPad than a number pad does, so your earlier answer doesn’t carry over.</p>
            )}
            <div ref={ipadGroup} className={styles.answers} role="group" aria-labelledby="ipad-question">
              <button type="button" aria-pressed={hasIpad === true} onClick={() => setHasIpad(true)}>
                Yes, we have one
              </button>
              <button type="button" aria-pressed={hasIpad === false} onClick={() => setHasIpad(false)}>
                No, not yet
              </button>
            </div>
            <div className={styles.always}>
              <p>
                <strong>In addition, the iPad will need to be:</strong>
              </p>
              <ul>
                <li>
                  <strong>Always plugged in,</strong> on your Wi-Fi, where your family member spends their day.
                </li>
                <li>
                  <strong>Always unlocked, with Porch open.</strong> Porch keeps the screen awake by itself. If
                  the iPad locks, the keys and drop-ins stop working until someone unlocks it.
                </li>
                <li>
                  <strong>In Guided Access, ideally.</strong> It’s an accessibility setting that keeps the iPad
                  focused on Porch, so your family member only ever sees the Porch app. Turn it on in{" "}
                  <strong>Settings → Accessibility → Guided Access</strong>, then triple-click the top or Home
                  button while Porch is open.{" "}
                  <a href="https://support.apple.com/en-us/111795">Apple’s instructions</a>
                </li>
              </ul>
            </div>
          </li>
          )}
          </>
          )}
        </ol>

        {platform === "ios" && (
        <div className={styles.submit}>
          <button type="submit" disabled={pending}>
            {pending ? "Joining…" : joined?.platform === "ios" ? "Save my answers" : "Join the pilot"}
          </button>
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
        </div>
        )}
      </form>
    </section>
  );
}

function KeypadPlan({ email, hasIpad }: { email: string; hasIpad: boolean }) {
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
            {hasIpad
              ? "All you need is your iPad, a USB number pad and a USB hub."
              : "All you need is a USB number pad, a USB hub and an iPad from 2015 or later. A refurbished or hand-me-down iPad is fine."}{" "}
            Porch isn’t on the App Store yet, so it comes through{" "}
            <a href="https://apps.apple.com/app/testflight/id899247664">TestFlight</a>, Apple’s free app for
            trying apps before they’re released.
          </p>
          <ol className={styles.howSteps}>
            <li>
              <h3>Porch shows a big clock.</h3>
              <p>It stays on screen until someone calls, or until they want to call someone.</p>
            </li>
            <li>
              <h3>They press a key to call.</h3>
              <p>
                Each key can call someone you choose. Family with the Porch app get a video call, and anyone
                else gets a voice call on their regular phone.
              </p>
            </li>
            <li>
              <h3>They talk on the iPad.</h3>
              <p>They see and hear you on its screen and speaker. Another key answers or hangs up.</p>
            </li>
          </ol>
        </div>
      </section>

      <section className={styles.section} aria-labelledby="keypad-kit-title">
        <div className={styles.sectionIntro}>
          <h3 id="keypad-kit-title">What you’ll need</h3>
          <p>
            You’ll need a USB number pad and a USB hub, which keeps the iPad charging while the number pad is
            plugged in. A stand is a good idea too. Below is what I use, but you’re free to shop around.
          </p>
        </div>
        <div className={styles.parts}>
          {keypadParts.map((part) => (
            <PartCard key={part.id} part={part} />
          ))}
        </div>
        <p className={styles.note}>
          Prices are from Amazon in October 2026 and may change, and other brands will cost more or less.
        </p>
      </section>

      <section className={styles.section} aria-labelledby="next-title">
        <div className={styles.sectionIntro}>
          <h3 id="next-title">What happens next</h3>
          <p>
            More detailed setup instructions will come to <strong>{email}</strong> soon.
          </p>
        </div>
      </section>
    </>
  );
}

function PhonePlan({
  email,
  onStartNow,
  pending,
  error,
}: {
  email: string;
  onStartNow: () => void;
  pending: boolean;
  error: string | null;
}) {
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
          <h2 id="plan-title">We're still waiting on Apple’s approval.</h2>
          <p className={styles.planIntro}>
            The big-button phone connects to the iPad through a small adapter called a Cell2Jack, and Porch
            needs Apple’s approval to use it. I’ll email you at <strong>{email}</strong> as soon as it comes
            through.
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
              <strong>Want to start sooner?</strong> Start with a number pad now, and add the phone once
              Apple approves it.
            </p>
            <button type="button" onClick={onStartNow} disabled={pending}>
              {pending ? "Switching…" : "Start with a number pad"}
            </button>
            {error && (
              <p className="form-error" role="alert">
                {error}
              </p>
            )}
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

// Two square photos across the top of a calling choice. They only illustrate it, so the choice's text alone
// names the button.
function ChoicePhotos({ photos }: { photos: { src: string; position?: string }[] }) {
  return (
    <span className={styles.choicePhotos}>
      {photos.map(({ src, position }) => (
        <Image
          key={src}
          src={src}
          alt=""
          width={900}
          height={900}
          sizes="(max-width: 720px) 45vw, 190px"
          style={position ? { objectPosition: position } : undefined}
        />
      ))}
    </span>
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
