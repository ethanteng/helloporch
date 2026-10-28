"use client";

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { flushSync } from "react-dom";
import PorchLogo from "@/components/PorchLogo";
import { AddPhoneForm, AddSomeoneMenu, CallScreen, Phone, PhoneKeypad, Porch, Sheet, type Tap } from "./Screens";
import type { ThreeWayPeople } from "./people";
import styles from "./film.module.css";

// A short portrait film of 3-way calling, drawn from the features page's screens. Everything on screen is a
// function of the time, so scripts/render-three-way-film.mjs can step through it frame by frame with
// `window.__film.seek(seconds)`. Opened without ?render, it plays on a loop.

const DURATION = 24.5;

// When things happen, in seconds.
const AT = {
  addTap: 1.7,
  menu: [2.0, 2.4],
  numberTap: 3.3,
  menuOut: [3.7, 4.0],
  form: [3.8, 4.25],
  typeName: [4.6, 5.2],
  typeNumber: [5.5, 6.9],
  callTap: 7.4,
  formOut: [7.8, 8.2],
  toPorch: [10.0, 10.6],
  zoomIn: [11.0, 11.7],
  bankAnswers: 12.2,
  zoomOut: [13.7, 14.3],
  toPhone: [14.6, 15.2],
  keypadTap: 16.0,
  keypad: [16.3, 16.7],
  keys: [17.2, 17.8, 18.4],
  keypadOut: [19.5, 19.9],
  end: [20.4, 21.0],
} as const;

const CAPTIONS: { from: number; to: number; text: ReactNode }[] = [
  { from: 0, to: 3.8, text: <>The bank needs to hear from <em>Mom.</em></> },
  { from: 3.8, to: 10.0, text: <>Call her on Porch, then <em>add the bank.</em></> },
  { from: 10.0, to: 14.6, text: <>Mom hears the bank and <em>answers for herself.</em></> },
  { from: 14.6, to: 20.4, text: <>You handle <em>the menus</em> and the hold music.</> },
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
  const { mom, caller, family } = people;
  const phoneShown = t < AT.toPorch[1] ? 1 - ramp(t, ...AT.toPorch) : ramp(t, ...AT.toPhone) * (1 - ramp(t, ...AT.end));
  const porchShown = ramp(t, ...AT.toPorch) * (1 - ramp(t, ...AT.toPhone));
  // Moves in on the Porch's heading, small at the iPad's real size, while it says who's joining.
  const zoom = ramp(t, ...AT.zoomIn) * (1 - ramp(t, ...AT.zoomOut));
  const answered = t >= AT.bankAnswers;
  const guest = t >= AT.formOut[0] ? { name: "Bank", answered } : undefined;

  // What's over the call on the phone: the Add someone menu, the Add a phone form, or the keypad.
  const menu = ramp(t, ...AT.menu) * (1 - ramp(t, ...AT.menuOut));
  const form = ramp(t, ...AT.form) * (1 - ramp(t, ...AT.formOut));
  const keypad = ramp(t, ...AT.keypad) * (1 - ramp(t, ...AT.keypadOut));
  const pressed = AT.keys.filter((at) => t >= at).map((_, i) => "12#"[i]).join("");
  const tap =
    tapAt(t, AT.addTap, "add") ??
    tapAt(t, AT.numberTap, "number") ??
    tapAt(t, AT.callTap, "call") ??
    tapAt(t, AT.keypadTap, "keypad") ??
    AT.keys.map((at, i) => tapAt(t, at, "12#"[i])).find(Boolean);

  return (
    <>
      {CAPTIONS.map((caption) => (
        <p key={caption.from} className={styles.caption} style={fade(t, caption.from, caption.to)}>
          <span>{caption.text}</span>
        </p>
      ))}

      {phoneShown > 0 && (
        <div className={styles.phoneShot} style={shot(phoneShown)}>
          <Phone label="" light={form > 0.5 || keypad > 0.5}>
            <CallScreen device="phone" title={mom.name} status={["Video call connected"]} remote={mom} self={caller} guest={guest} tap={tap}>
              <Sheet shown={menu}>
                <AddSomeoneMenu family={family} tap={tap} />
              </Sheet>
              <Sheet shown={form} page>
                <AddPhoneForm
                  name={typed("Bank", t, ...AT.typeName)}
                  number={typed("(800) 555-0199", t, ...AT.typeNumber)}
                  typing={t < AT.typeName[1] + 0.2 ? "name" : t < AT.callTap ? "number" : undefined}
                  tap={tap}
                />
              </Sheet>
              <Sheet shown={keypad} page>
                <PhoneKeypad name="Bank" pressed={pressed} tap={tap} />
              </Sheet>
            </CallScreen>
          </Phone>
        </div>
      )}

      {porchShown > 0 && (
        <div className={styles.porchShot} style={shot(porchShown, 1 + zoom * 0.3)}>
          <Porch label="">
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

      <div className={styles.end} style={{ opacity: ramp(t, ...AT.end) }}>
        <p className={`logo ${styles.logo}`}>
          <PorchLogo />
        </p>
        <p className={styles.endTitle}>
          <em>3-way</em> calling
        </p>
        <p className={styles.endLine}>When you hang up, the bank hangs up too, so Mom is never left alone with a caller.</p>
      </div>
    </>
  );
}

/** 0 before `from`, 1 after `to`, eased in between. */
function ramp(t: number, from: number, to: number) {
  const x = Math.min(1, Math.max(0, (t - from) / (to - from)));
  return x < 0.5 ? 4 * x ** 3 : 1 - (-2 * x + 2) ** 3 / 2;
}

function tapAt(t: number, at: number, on: string): Tap | undefined {
  return t >= at && t < at + 0.45 ? { on, p: (t - at) / 0.45 } : undefined;
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
