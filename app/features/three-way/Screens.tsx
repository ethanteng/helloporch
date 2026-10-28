import Image from "next/image";
import type { CSSProperties, ReactNode } from "react";
import styles from "./three-way.module.css";

// Mockups of the iOS app's 3-way calling screens (ios/Porch/CallGuests.swift and NativeCallViewController.swift),
// drawn in iOS points so they keep their proportions at any size, for the film on the features page.

export type Person = { name: string; photo?: string };

/** An iPhone 17 Pro, 402 × 874 points. */
export function Phone({ light = false, children }: { light?: boolean; children: ReactNode }) {
  return (
    <div className={styles.phone}>
      <div className={styles.phoneScreen}>
        <div className={styles.ui}>
          {children}
          <div className={styles.statusBar} aria-hidden>
            <span>9:41</span>
            <svg viewBox="0 0 76 14" className={styles.statusIcons}>
              <g fill="currentColor">
                <rect x="0" y="9" width="3.2" height="4" rx="1" />
                <rect x="4.8" y="6.5" width="3.2" height="6.5" rx="1" />
                <rect x="9.6" y="3.8" width="3.2" height="9.2" rx="1" />
                <rect x="14.4" y="1" width="3.2" height="12" rx="1" />
                <path d="M31 3.2a11 11 0 0 1 8 3.3l1.4-1.5a13 13 0 0 0-18.8 0L23 6.5a11 11 0 0 1 8-3.3zm0 3.9a7 7 0 0 1 5.1 2.1l1.4-1.5a9 9 0 0 0-13 0l1.4 1.5A7 7 0 0 1 31 7.1zm0 3.9a3 3 0 0 0-2.2.9L31 14l2.2-2.1A3 3 0 0 0 31 11z" />
                <rect x="47" y="1.5" width="24" height="11" rx="3.4" fill="none" stroke="currentColor" strokeOpacity=".4" />
                <rect x="49" y="3.5" width="17" height="7" rx="1.8" />
                <path d="M72.6 5.2c.9.3 1.4 1 1.4 1.8s-.5 1.5-1.4 1.8z" fillOpacity=".4" />
              </g>
            </svg>
          </div>
          <div className={styles.island} />
          <div className={styles.homeBar} data-light={light || undefined} />
        </div>
      </div>
    </div>
  );
}

/** Mom's Porch: an iPad Air standing upright, 820 × 1180 points, with no status bar. */
export function Porch({ children }: { children: ReactNode }) {
  return (
    <div className={styles.porch}>
      <div className={styles.porchBezel}>
        <div className={styles.porchScreen}>
          <div className={styles.ui}>
            {children}
            <div className={styles.homeBar} />
          </div>
        </div>
      </div>
    </div>
  );
}

/** Someone's photo filling its box, standing in for their video, or a placeholder naming whose photo goes there. */
export function Face({ person, sizes, small = false }: { person: Person; sizes: string; small?: boolean }) {
  if (person.photo) return <Image src={person.photo} alt="" fill sizes={sizes} className={styles.face} />;
  return (
    <div className={styles.placeholder}>
      <svg viewBox="0 0 100 100" aria-hidden>
        <circle cx="50" cy="36" r="18" />
        <path d="M14 96c2-22 17-34 36-34s34 12 36 34z" />
      </svg>
      {!small && <span>{person.name}’s photo</span>}
    </div>
  );
}

type Guest = { name: string; answered: boolean };

/**
 * A call with video. On a family phone, `guest` is a phone this person added, such as the bank, with its keypad and
 * hang-up. On the Porch, `status` carries what the bedside says about who's joining.
 */
export function CallScreen({
  device,
  title,
  status,
  remote,
  self,
  guest,
  children,
}: {
  device: "phone" | "porch";
  title: string;
  status: string[];
  remote: Person;
  self: Person;
  guest?: Guest;
  children?: ReactNode;
}) {
  const phone = device === "phone";
  return (
    <>
      <div className={styles.stage}>
        <Face person={remote} sizes={phone ? "300px" : "430px"} />
      </div>
      <div className={styles.overlays}>
        <div className={`${styles.panel} ${styles.heading}`}>
          <p className={styles.title}>{title}</p>
          <p className={styles.status}>
            {status.map((line) => (
              <span key={line}>{line}</span>
            ))}
          </p>
        </div>
        <div className={styles.bottom}>
          <div className={styles.preview}>
            <Face person={self} sizes="120px" small />
          </div>
          <div className={styles.panel}>
            {guest && (
              <>
                <p className={styles.guestStatus}>{guest.answered ? `${guest.name} is on the call` : `Calling ${guest.name}…`}</p>
                <div className={styles.row}>
                  <CallButton title="Keypad" icon="keypad" disabled={!guest.answered} />
                  <CallButton title={`Hang up ${guest.name}`} icon="hangUp" end />
                </div>
              </>
            )}
            {!phone && <p className={styles.hint}>Key 0: hang up · Key 9: video off / on</p>}
            <div className={styles.row}>
              <CallButton title="Mute" icon="mute" />
              <CallButton title="Camera off" icon="camera" />
              {phone && <CallButton title="Add someone" icon="add" />}
              <CallButton title="End call" icon="hangUp" end />
            </div>
          </div>
        </div>
      </div>
      {children}
    </>
  );
}

function CallButton({ title, icon, end, disabled }: { title: string; icon: IconName; end?: boolean; disabled?: boolean }) {
  return (
    <span className={styles.callButton} data-end={end || undefined} data-disabled={disabled || undefined}>
      <Icon name={icon} />
      {title}
    </span>
  );
}

/** Slides a page sheet up over the call and dims it; `shown` runs from 0 (hidden) to 1. */
export function Sheet({ shown = 1, children }: { shown?: number; children: ReactNode }) {
  if (shown <= 0) return null;
  return (
    <div className={styles.sheetLayer} style={{ "--in": shown } as CSSProperties}>
      <div className={styles.dim} />
      <div className={styles.pageSheet}>{children}</div>
    </div>
  );
}

/** The Add a phone form, with what's been typed so far and the field being typed in. */
export function AddPhoneForm({ name, number, typing }: { name: string; number: string; typing?: "name" | "number" }) {
  return (
    <>
      <div className={styles.navBar}>
        <span className={styles.navButton}>Cancel</span>
        Add a phone
      </div>
      <div className={styles.form}>
        <div className={styles.card}>
          <p className={styles.cardTitle}>Who should join the call?</p>
          <p className={styles.cardDetail}>Porch calls this number and adds them to your call. If you hang up, their call ends too.</p>
          <Field label="Who are you calling?" value={name} placeholder="For example, Bank" helper="The bedside shows this name." caret={typing === "name"} />
          <Field
            label="Their phone number"
            value={number}
            placeholder="(800) 555-0123"
            helper="US and Canadian numbers, including toll-free numbers."
            caret={typing === "number"}
          />
          <span className={styles.formButton}>
            <Icon name="contact" />
            Choose from Contacts
          </span>
          <span className={styles.formButton} data-filled>
            <Icon name="dial" />
            Call and add to this call
          </span>
        </div>
      </div>
    </>
  );
}

function Field({ label, value, placeholder, helper, caret }: { label: string; value: string; placeholder: string; helper: string; caret: boolean }) {
  return (
    <div className={styles.field}>
      <p className={styles.fieldLabel}>{label}</p>
      <p className={styles.input} data-empty={!value || undefined}>
        {value || (caret ? "" : placeholder)}
        {caret && <span className={styles.caret} />}
      </p>
      <p className={styles.helper}>{helper}</p>
    </div>
  );
}

// Stand-ins for the SF Symbols the app uses: mic.slash, video.slash, person.badge.plus, phone.down.fill,
// circle.grid.3x3.fill, person.crop.circle and phone.badge.plus.
type IconName = "mute" | "camera" | "add" | "hangUp" | "keypad" | "contact" | "dial";

function Icon({ name }: { name: IconName }) {
  const shapes: Record<IconName, ReactNode> = {
    mute: (
      <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <rect x="9" y="2.5" width="6" height="11.5" rx="3" />
        <path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7M4 3l16 18" />
      </g>
    ),
    camera: (
      <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round">
        <rect x="2" y="6.5" width="13" height="11" rx="2.5" />
        <path d="M15 10.5l6-3.5v10l-6-3.5M3 3l16 18" />
      </g>
    ),
    add: (
      <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <circle cx="9" cy="7.5" r="4" />
        <path d="M1.5 20.5c.5-4 3.5-6.5 7.5-6.5s7 2.5 7.5 6.5M19.5 7v7M16 10.5h7" />
      </g>
    ),
    hangUp: (
      <path
        fill="currentColor"
        d="M12 8.5c-4.4 0-8.3 1.4-10 3.4-.7.8-.6 2 .1 2.8l1.5 1.5c.6.6 1.6.7 2.3.2l2.2-1.5c.5-.4.8-1 .7-1.6l-.2-1.6c1-.4 2.2-.6 3.4-.6s2.4.2 3.4.6l-.2 1.6c-.1.6.2 1.2.7 1.6l2.2 1.5c.7.5 1.7.4 2.3-.2l1.5-1.5c.7-.8.8-2 .1-2.8-1.7-2-5.6-3.4-10-3.4z"
      />
    ),
    keypad: (
      <g fill="currentColor">
        {[5, 12, 19].flatMap((y) => [5, 12, 19].map((x) => <circle key={`${x}-${y}`} cx={x} cy={y} r="2.4" />))}
      </g>
    ),
    contact: (
      <g fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
        <circle cx="12" cy="12" r="10" />
        <circle cx="12" cy="9.5" r="3.5" />
        <path d="M5.8 18.6c1.4-2.3 3.6-3.6 6.2-3.6s4.8 1.3 6.2 3.6" />
      </g>
    ),
    dial: (
      <g fill="currentColor">
        <path d="M5.2 2.5h2.6c.5 0 .9.3 1 .8l.8 3.4c.1.4 0 .8-.3 1.1L7.6 9.4a12.5 12.5 0 0 0 5.5 5.5l1.6-1.7c.3-.3.7-.4 1.1-.3l3.4.8c.5.1.8.5.8 1v2.6c0 .9-.7 1.6-1.6 1.6C10 18.9 3.6 12.5 3.6 4.1c0-.9.7-1.6 1.6-1.6z" />
        <path d="M17 2v8M13 6h8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      </g>
    ),
  };
  return (
    <svg viewBox="0 0 24 24" className={styles.icon} aria-hidden>
      {shapes[name]}
    </svg>
  );
}
