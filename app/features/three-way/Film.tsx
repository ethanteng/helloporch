"use client";

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { flushSync } from "react-dom";
import PorchLogo from "@/components/PorchLogo";
import { AddPhoneForm, CallScreen, Phone, Porch, Sheet } from "./Screens";
import type { ThreeWayPeople } from "./people";
import styles from "./film.module.css";

// A short portrait film of 3-way calling, drawn from the app's screens in Screens.tsx. Everything on screen is a
// function of the time, so scripts/render-three-way-film.mjs can step through it frame by frame with
// `window.__film.seek(seconds)`. Opened without ?render, it plays on a loop.

const DURATION = 20.5;

// When things happen, in seconds.
const AT = {
  form: [3.0, 3.45],
  typeName: [3.8, 4.4],
  typeNumber: [4.7, 6.1],
  press: [6.3, 7.3],
  formOut: [7.4, 7.8],
  toPorch: [8.4, 9.0],
  zoomIn: [9.2, 10.0],
  bankAnswers: 11.2,
  zoomOut: [13.0, 13.6],
  toPhone: [13.6, 14.2],
  onTheCall: [14.5, 15.7],
  end: [17.6, 18.2],
} as const;

const CAPTIONS: { from: number; to: number; text: ReactNode }[] = [
  { from: 0, to: 3.0, text: <>The bank insists that <em>Mom</em> be on the call.</> },
  { from: 3.0, to: 8.4, text: <>Call her on Porch, then <em>add the bank.</em></> },
  { from: 8.4, to: 13.6, text: <>Mom hears the bank and <em>answers for herself.</em></> },
  { from: 13.6, to: 17.6, text: <>You handle <em>the menus</em> and the hold music.</> },
];

declare global {
  interface Window {
    __film?: { duration: number; seek: (seconds: number) => Promise<void> };
  }
}

export default function Film({ people }: { people: ThreeWayPeople }) {
  const [t, setT] = useState(0);

  useEffect(() => {
    window.__film = {
      duration: DURATION,
      seek: (seconds) => {
        flushSync(() => setT(seconds));
        return new Promise((resolve) => requestAnimationFrame(() => resolve()));
      },
    };
    if (new URLSearchParams(window.location.search).has("render")) return;
    let frame = 0;
    const start = performance.now();
    const tick = (now: number) => {
      setT(((now - start) / 1000) % DURATION);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  return (
    <div className={styles.film}>
      <Scenes t={t} people={people} />
    </div>
  );
}

function Scenes({ t, people }: { t: number; people: ThreeWayPeople }) {
  const { mom, caller } = people;
  const phoneShown = t < AT.toPorch[1] ? 1 - ramp(t, ...AT.toPorch) : ramp(t, ...AT.toPhone) * (1 - ramp(t, ...AT.end));
  const porchShown = ramp(t, ...AT.toPorch) * (1 - ramp(t, ...AT.toPhone));
  // Moves in close on the Porch's heading, small at the iPad's real size, while it says who's joining.
  const zoom = ramp(t, ...AT.zoomIn) * (1 - ramp(t, ...AT.zoomOut));
  const answered = t >= AT.bankAnswers;
  const guest = t >= AT.formOut[0] ? { name: "Bank", answered } : undefined;
  const form = ramp(t, ...AT.form) * (1 - ramp(t, ...AT.formOut));
  // The one tap the film shows, Call and add to this call, and then "Bank is on the call".
  const press = t >= AT.press[0] && t <= AT.press[1] ? (t - AT.press[0]) / (AT.press[1] - AT.press[0]) : undefined;
  const onTheCall = t >= AT.onTheCall[0] ? Math.min(1, (t - AT.onTheCall[0]) / (AT.onTheCall[1] - AT.onTheCall[0])) : undefined;

  return (
    <>
      {phoneShown > 0 && (
        <div className={styles.phoneShot} style={shot(phoneShown)}>
          <Phone light={form > 0.5}>
            <CallScreen device="phone" title={mom.name} status={["Video call connected"]} remote={mom} self={caller} guest={guest} highlight={onTheCall}>
              <Sheet shown={form}>
                <AddPhoneForm
                  name={typed("Bank", t, ...AT.typeName)}
                  number={typed("(800) 555-0199", t, ...AT.typeNumber)}
                  typing={t < AT.typeName[1] + 0.2 ? "name" : t < AT.press[0] ? "number" : undefined}
                  press={press}
                />
              </Sheet>
            </CallScreen>
          </Phone>
        </div>
      )}

      {porchShown > 0 && (
        <div className={styles.porchShot} style={shot(porchShown, 1 + zoom * 1.2)}>
          <Porch>
            <CallScreen
              device="porch"
              title={caller.name}
              status={["Video call connected", answered ? "Bank joined the call" : "Calling Bank…"]}
              remote={caller}
              self={mom}
            />
          </Porch>
        </div>
      )}

      {/* Keeps the captions clear of a device that's zoomed in under them. */}
      <div className={styles.band} />
      {CAPTIONS.map((caption) => (
        <p key={caption.from} className={styles.caption} style={fade(t, caption.from, caption.to)}>
          <span>{caption.text}</span>
        </p>
      ))}

      <div className={styles.end} style={{ opacity: ramp(t, ...AT.end) }}>
        <p className={`logo ${styles.logo}`}>
          <PorchLogo />
        </p>
        <p className={styles.endTitle}>
          <em>3-way</em> calling
        </p>
      </div>
    </>
  );
}

/** 0 before `from`, 1 after `to`, eased in between. */
function ramp(t: number, from: number, to: number) {
  const x = Math.min(1, Math.max(0, (t - from) / (to - from)));
  return x < 0.5 ? 4 * x ** 3 : 1 - (-2 * x + 2) ** 3 / 2;
}

function typed(text: string, t: number, from: number, to: number) {
  return text.slice(0, Math.round(text.length * Math.min(1, Math.max(0, (t - from) / (to - from)))));
}

function fade(t: number, from: number, to: number): CSSProperties {
  const shown = (from === 0 ? 1 : ramp(t, from, from + 0.4)) * (1 - ramp(t, to - 0.35, to));
  return { opacity: shown, transform: `translateY(${(1 - shown) * 12}px)` };
}

function shot(shown: number, zoom = 1): CSSProperties {
  return { opacity: shown, transform: `translateX(-50%) scale(${(0.96 + shown * 0.04) * zoom})` };
}
