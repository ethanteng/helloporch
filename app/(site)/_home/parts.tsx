// Sections of the home page that only it uses. The pilot section it closes with is shared (components/PilotJoin.tsx).
import type { CSSProperties, ReactNode } from "react";
import Image from "next/image";
import Link from "next/link";
import PorchFace, { type Who } from "@/components/PorchFace";
import PorchKeypad, { ScreenKey } from "@/components/PorchKeypad";
import { ShieldIcon, SpeakerIcon, VideoIcon } from "../features/icons";
import styles from "./home.module.css";

/* ---------- The keypad we're designing, with a tag saying so ---------- */

export function DeviceIllustration({ tag }: { tag?: ReactNode }) {
  return (
    <section className={`device ${styles.deviceTagged}`} aria-label="The Porch tablet and keypad, in design">
      {tag ? <p className={styles.deviceTag}>{tag}</p> : null}
      <div className="device__stage">
        <div className="device__tablet-wrap">
          <div className="device__tablet">
            <div className="device__screen">
              <PorchFace who="sarah" shape="rect" width="100%" height="100%" talking style={{ position: "absolute", inset: 0 }} />
              <div className="device__name">Sarah</div>
              <div className="device__self">
                <PorchFace who="walt" shape="rect" width="100%" height="100%" style={{ position: "absolute", inset: 0 }} />
              </div>
            </div>
          </div>
          <div className="device__stand" />
        </div>
        <PorchKeypad />
      </div>
    </section>
  );
}

/* ---------- Four steps on a phone, one on Porch ---------- */

const PHONE_STEPS = ["Unlock the phone", "Find the video app", "Scroll to Sarah", "Tap the tiny camera icon"];

export function Compare() {
  return (
    <section className="compare">
      <div className="compare__group">
        <h2 className="section-title section-title--sm">Four steps on a phone.</h2>
        <ul className="compare__steps">
          {PHONE_STEPS.map((s) => (
            <li key={s}>{s}</li>
          ))}
        </ul>
      </div>
      <div className="compare__group">
        <h2 className="section-title section-title--lg">
          <em className="bold-italic">One on Porch.</em>
        </h2>
        <div className="call-pill">
          <div className="call-pill__ring" />
          <div className="call-pill__ring call-pill__ring--late" />
          <div className="call-pill__face">
            <PorchFace who="sarah" size={104} talking />
          </div>
          Call Sarah
        </div>
      </div>
    </section>
  );
}

/* For the hands tile: the Sarah key pressed under a fingertip, the Mike key raised. */
export function KeysCloseUp() {
  const abs = (s: CSSProperties): CSSProperties => ({ position: "absolute", transformStyle: "preserve-3d", ...s });
  return (
    <div style={{ position: "relative", width: 280, height: 200, perspective: 900 }}>
      <div
        style={abs({
          left: 10,
          top: 24,
          width: 260,
          height: 160,
          borderRadius: 28,
          background: "linear-gradient(165deg,oklch(0.995 0.003 85),oklch(0.93 0.006 80))",
          boxShadow: "inset 0 2px 0 #fff,0 10px 0 oklch(0.84 0.008 75),0 24px 30px -14px oklch(0.3 0.05 50 / .45)",
          transform: "rotateX(30deg) rotateY(-12deg)",
        })}
      >
        <div style={abs({ left: 24, top: 30 })}>
          <ScreenKey who="sarah" name="Sarah" pressed />
        </div>
        <div style={abs({ left: 136, top: 30 })}>
          <ScreenKey who="mike" name="Mike" />
        </div>
        <div style={abs({ left: 26, top: 32, width: 96, height: 96, borderRadius: "50%", border: "3px solid oklch(0.64 0.17 35 / .5)", boxSizing: "border-box", transform: "translateZ(34px)" })} />
        <div style={abs({ left: 40, top: 46, width: 68, height: 68, borderRadius: "50%", background: "oklch(0.82 0.06 55 / .6)", border: "2px solid oklch(0.97 0.02 60 / .9)", boxSizing: "border-box", transform: "translateZ(36px)" })} />
      </div>
    </div>
  );
}

/* ---------- Who can call: approved family gets through, unknown numbers don't ---------- */

export function CallLog({ compact = false }: { compact?: boolean }) {
  return (
    <div className={styles.log} data-compact={compact || undefined} aria-hidden="true">
      <p className={styles.logTitle}>Calls to Mom today</p>
      <LogRow who="sarah" name="Sarah" note="Video drop-in · Porch picked up" />
      <LogRow who="mike" name="Mike" note="Called from his phone · Porch picked up" />
      <LogRow name="(888) 555-0147" note="Unknown caller · Blocked" />
      {compact ? null : <LogRow name="(202) 555-0188" note="Unknown caller · Blocked" />}
    </div>
  );
}

function LogRow({ who, name, note }: { who?: Who; name: string; note: string }) {
  return (
    <div className={styles.logRow} data-blocked={who ? undefined : true}>
      {who ? (
        <PorchFace who={who} size={44} />
      ) : (
        <span className={styles.logBlocked}>
          <ShieldIcon />
        </span>
      )}
      <div>
        <p className={styles.logName}>{name}</p>
        <p className={styles.logNote}>{note}</p>
      </div>
    </div>
  );
}

export function SafetySection({ title, children }: { title: ReactNode; children: ReactNode }) {
  return (
    <section className={styles.safety} aria-labelledby="safety-title">
      <div className={styles.safetyCopy}>
        <p className={styles.kicker}>Who can call</p>
        <h2 id="safety-title" className={styles.sectionTitle}>
          {title}
        </h2>
        <p className={styles.sectionBody}>{children}</p>
        <ul className={styles.checks}>
          <li>
            <VideoIcon /> Family you approve can drop in any time
          </li>
          <li>
            <SpeakerIcon /> Porch says who it is, out loud, first
          </li>
          <li>
            <ShieldIcon /> Unknown numbers are blocked from day one
          </li>
        </ul>
      </div>
      <div className={styles.safetyArt}>
        <CallLog />
      </div>
    </section>
  );
}

/* ---------- Ethan, in his own words from the intro film ---------- */

export function FounderNote() {
  return (
    <section className={styles.founder} aria-label="Why I'm building Porch">
      <Image src="/features/three-way/ethan.jpg" alt="Ethan, who is building Porch" width={132} height={132} className={styles.founderPhoto} />
      <blockquote className={styles.founderQuote}>
        <p>
          “My mom is 78. She has advanced Parkinson’s and dementia. Her hands have become slow and stiff, she forgets where
          her phone is, and more often than not it isn’t charged. So people call, but they can’t reach her. That’s why I’m
          building Porch.”
        </p>
        <footer>
          Ethan, founder · <Link href="/story">Watch our story</Link>
        </footer>
      </blockquote>
    </section>
  );
}
