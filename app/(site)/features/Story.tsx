import type { CSSProperties, ReactNode } from "react";
import PorchFace, { type Who } from "@/components/PorchFace";
import { ScreenKey } from "@/components/PorchKeypad";
import { clip } from "./clips";
import {
  AddPersonIcon,
  BankIcon,
  EndCallIcon,
  EyeIcon,
  MicIcon,
  MicOffIcon,
  PhoneIcon,
  ShieldIcon,
  SpeakerIcon,
  TextIcon,
  VideoIcon,
} from "./icons";
import LanguageDemo from "./LanguageDemo";
import styles from "./story.module.css";
import WatchClip from "./WatchClip";

type Chapter = {
  id: string;
  kicker: string;
  title: ReactNode;
  body: ReactNode;
  watch: { id: string; label: string }[];
  scene: ReactNode;
  tint: string;
};

// The features, told from both ends of the call: what they do, what you do, and what happens between calls.
const CHAPTERS: Chapter[] = [
  {
    id: "press",
    kicker: "When they call you",
    title: "One press, and it’s ringing.",
    body: (
      <>
        Every button on their corded phone or keypad has a face and a name, so they know exactly who they’re calling.
        One press starts the call. There’s nothing to dial.
      </>
    ),
    watch: [
      { id: "mom-calls-me", label: "Mom calls me" },
      { id: "phone-fallback", label: "When I don’t pick up" },
    ],
    scene: <PressScene />,
    tint: "oklch(0.88 0.075 80)",
  },
  {
    id: "pickup",
    kicker: "When you call them",
    title: "Porch picks up for them.",
    body: (
      <>
        Porch says who’s calling, out loud, and answers on its own. They don’t have to do a thing. And every Porch has
        its own private phone number, so you can call from the Porch app or dial it from any phone.
      </>
    ),
    watch: [{ id: "video-drop-in", label: "A video drop-in" }],
    scene: <PickupScene />,
    tint: "oklch(0.87 0.05 45)",
  },
  {
    id: "messages",
    kicker: "Between calls",
    title: "Messages and texts play themselves.",
    body: (
      <>
        Record a video or voice message in the Porch app, or just text their Porch number from any phone. When they sit
        down in front of the iPad, Porch plays whatever’s waiting and reads texts aloud. Nothing to open, nothing to miss.
      </>
    ),
    watch: [
      { id: "send-a-message", label: "Sending one" },
      { id: "auto-play-messages", label: "Watching it play" },
    ],
    scene: <MessagesScene />,
    tint: "oklch(0.88 0.045 150)",
  },
  {
    id: "language",
    kicker: "In their language",
    title: "In the language they grew up with.",
    body: (
      <>
        Porch shows and speaks Mandarin, Cantonese, or Spanish as well as English, from the clock to its announcements.
        Texts sent to their Porch number are translated into their language automatically.
      </>
    ),
    watch: [{ id: "multi-language", label: "Switching languages" }],
    scene: <LanguageDemo />,
    tint: "oklch(0.87 0.04 275)",
  },
  {
    id: "together",
    kicker: "All together",
    title: "Bring everyone onto the call.",
    body: (
      <>
        On a call with them, tap Add someone to bring in a brother, a grandchild, or an old friend. It helps with the
        hard calls too, like the bank, when they need to be on the line and you’re there to help.
      </>
    ),
    watch: [{ id: "three-way-calling", label: "Adding the bank" }],
    scene: <TogetherScene />,
    tint: "oklch(0.88 0.04 235)",
  },
];

export default function Story() {
  return (
    <section className={styles.chapters} aria-label="How Porch works">
      {CHAPTERS.map((chapter, index) => (
        <article
          key={chapter.id}
          id={chapter.id}
          className={styles.chapter}
          data-flip={index % 2 === 1 || undefined}
          aria-labelledby={`${chapter.id}-title`}
        >
          <div className={styles.copy}>
            <p className={styles.marker}>
              <span className={styles.num} aria-hidden="true">
                {index + 1}
              </span>
              {chapter.kicker}
            </p>
            <h2 id={`${chapter.id}-title`}>{chapter.title}</h2>
            <p className={styles.body}>{chapter.body}</p>
            <div className={styles.watchRow}>
              {chapter.watch.map((w) => (
                <WatchClip key={w.id} clip={clip(w.id)} label={w.label} />
              ))}
            </div>
          </div>
          <div className={styles.stage} style={{ "--tint": chapter.tint } as CSSProperties}>
            {chapter.scene}
          </div>
        </article>
      ))}
    </section>
  );
}

/* ---------- 1. They press a face: Porch tries the app with video, then your phone. ---------- */

function PressScene() {
  return (
    <div className={styles.press}>
      <div className={styles.plateWrap} aria-hidden="true">
        <div className={styles.plate}>
          <div className={styles.plateKey} style={{ left: 24 }}>
            <ScreenKey who="sarah" name="Sarah" pressed />
          </div>
          <div className={styles.plateKey} style={{ left: 136 }}>
            <ScreenKey who="mike" name="Mike" />
          </div>
          <div className={styles.tapRing} />
          <div className={styles.fingertip} />
        </div>
      </div>
      <ol className={styles.route}>
        <li className={styles.routeStep}>
          <span className={styles.routeIcon} data-tone="video">
            <VideoIcon />
          </span>
          <span>
            <strong>Your Porch app rings</strong>
            <span className={styles.routeNote}>A video call comes first</span>
          </span>
        </li>
        <li className={styles.routeFork}>No answer, or no app?</li>
        <li className={styles.routeStep}>
          <span className={styles.routeIcon} data-tone="phone">
            <PhoneIcon />
          </span>
          <span>
            <strong>Then your phone rings</strong>
            <span className={styles.routeNote}>Porch dials your number</span>
          </span>
        </li>
      </ol>
    </div>
  );
}

/* ---------- 2. You call: Porch announces you and connects itself. It has its own number. ---------- */

function PickupScene() {
  return (
    <div className={styles.pickup}>
      <div className={styles.announce}>
        <SpeakerIcon className={styles.announceIcon} />
        <p>“Sarah is dropping in with video. Connecting in five seconds.”</p>
      </div>
      <div className={styles.ipad} aria-hidden="true">
        <div className={`${styles.ipadScreen} ${styles.dropIn}`}>
          <div className={styles.dropFace}>
            <PorchFace who="sarah" shape="rect" width="100%" height="100%" style={{ position: "absolute", inset: 0 }} />
          </div>
          <p className={styles.dropName}>Sarah</p>
          <p className={styles.dropStatus}>
            Video drop-in
            <br />
            Connecting in 3…
          </p>
        </div>
      </div>
      <div className={styles.numberCard}>
        <p className={styles.numberLabel}>Mom’s Porch number</p>
        <p className={styles.number}>(415) 555-0142</p>
        <ul className={styles.numberWays}>
          <li>
            <VideoIcon /> Call in the Porch app
          </li>
          <li>
            <PhoneIcon /> Or call or text it from any phone
          </li>
          <li>
            <ShieldIcon /> Unknown callers are blocked
          </li>
        </ul>
      </div>
    </div>
  );
}

/* ---------- 3. Messages and texts wait for Mom, then play when she sits down. ---------- */

function MessagesScene() {
  return (
    <div className={styles.messages} aria-hidden="true">
      <div className={styles.waiting}>
        <p className={styles.waitingTitle}>Waiting for Mom</p>
        <Waiting who="sarah" name="Sarah" kind="Video message · 0:06" icon={<VideoIcon />} playing />
        <Waiting who="mike" name="Mike" kind="Voice message · 0:14" icon={<MicIcon />} />
        <Waiting who="emma" name="Emma" kind="Text · read aloud" icon={<TextIcon />} quote="Can’t wait for Sunday!" />
      </div>
      <div className={styles.messagesIpad}>
        <span className={styles.here}>
          <EyeIcon /> Mom’s here, so they play
        </span>
        <div className={styles.ipad}>
          <div className={styles.ipadScreen}>
            <PorchFace who="sarah" shape="rect" width="100%" height="100%" talking style={{ position: "absolute", inset: 0 }} />
            <span className={styles.banner}>Message from Sarah · Sent today at 9:12 AM</span>
            <span className={styles.stop}>
              <span className={styles.stopSquare} /> Stop
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

function Waiting({
  who,
  name,
  kind,
  icon,
  quote,
  playing,
}: {
  who: Who;
  name: string;
  kind: string;
  icon: ReactNode;
  quote?: string;
  playing?: boolean;
}) {
  return (
    <div className={styles.waitingItem} data-playing={playing || undefined}>
      <PorchFace who={who} size={44} className={styles.waitingFace} />
      <div>
        <p className={styles.waitingName}>
          {name}
          {playing ? <span className={styles.nowPlaying}>Playing</span> : null}
        </p>
        <p className={styles.waitingKind}>
          {icon} {kind}
        </p>
        {quote ? <p className={styles.waitingQuote}>“{quote}”</p> : null}
      </div>
    </div>
  );
}

/* ---------- 5. A call with Mom, with family and the bank added. ---------- */

function TogetherScene() {
  return (
    <div className={styles.together} aria-hidden="true">
      <div className={styles.hub}>
        <svg className={styles.hubLines} viewBox="0 0 400 330">
          <path d="M200 155 L62 62" />
          <path d="M200 155 L338 62" />
          <path d="M200 155 L338 248" />
          <path d="M200 155 L62 248" data-new />
        </svg>
        <div className={styles.hubCenter}>
          <PorchFace who="rose" size={128} talking />
          <span>Mom</span>
        </div>
        <Guest at={[62, 62]} name="You">
          <PorchFace who="sarah" size={76} />
        </Guest>
        <Guest at={[338, 62]} name="Mike" note="Joined with video">
          <PorchFace who="mike" size={76} />
        </Guest>
        <Guest at={[338, 248]} name="The bank" note="Joined by phone">
          <span className={styles.bank}>
            <BankIcon />
          </span>
        </Guest>
        <Guest at={[62, 248]} name="Emma" note="Calling…" dashed>
          <PorchFace who="emma" size={76} />
        </Guest>
      </div>
      <div className={styles.controls}>
        <span>
          <MicOffIcon /> Mute
        </span>
        <span data-active>
          <AddPersonIcon /> Add someone
        </span>
        <span data-end>
          <EndCallIcon /> End call
        </span>
      </div>
    </div>
  );
}

function Guest({ at, name, note, dashed, children }: { at: [number, number]; name: string; note?: string; dashed?: boolean; children: ReactNode }) {
  return (
    <div className={styles.guest} data-dashed={dashed || undefined} style={{ left: at[0], top: at[1] }}>
      <div className={styles.guestFace}>{children}</div>
      <span className={styles.guestName}>{name}</span>
      {note ? <span className={styles.guestNote}>{note}</span> : null}
    </div>
  );
}
