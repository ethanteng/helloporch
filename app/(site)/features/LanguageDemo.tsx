"use client";

import { useState } from "react";
import { PhoneIcon, SpeakerIcon } from "./icons";
import styles from "./story.module.css";

// The bedside in each language it speaks. The clock, the button and the spoken drop-in come from the app's own
// strings (ios/PorchCore/Sources/PorchCore/BedsideLanguage.swift); times follow each locale's clock.
const LANGUAGES = [
  {
    id: "zh-Hans",
    name: "普通话",
    english: "Mandarin",
    scene: "夜晚 · 秋天",
    day: "星期三",
    before: "晚上",
    time: "8:15",
    after: "",
    call: "打电话",
    spoken: "Sarah要和您视频通话，五秒后接通。",
    message: "妈，星期天见。爱你！",
  },
  {
    id: "zh-HK",
    name: "廣東話",
    english: "Cantonese",
    scene: "夜晚 · 秋天",
    day: "星期三",
    before: "晚上",
    time: "8:15",
    after: "",
    call: "打電話",
    spoken: "Sarah想同您視像通話，五秒後接通。",
    message: "媽，星期日見。愛你！",
  },
  {
    id: "es",
    name: "Español",
    english: "Spanish",
    scene: "Noche · Otoño",
    day: "miércoles",
    before: "",
    time: "20:15",
    after: "",
    call: "Llamar a alguien",
    spoken: "Sarah quiere hablar con usted por vídeo. La llamada se conectará en cinco segundos.",
    message: "Nos vemos el domingo, mamá. ¡Te quiero!",
  },
  {
    id: "en",
    name: "English",
    english: "English",
    scene: "Night · Fall",
    day: "Wednesday",
    before: "",
    time: "8:15",
    after: "PM",
    call: "Call someone",
    spoken: "Sarah is dropping in with video. Connecting in five seconds.",
    message: "See you Sunday, Mom. Love you!",
  },
];

const SENT = LANGUAGES[LANGUAGES.length - 1].message;

export default function LanguageDemo() {
  const [chosen, setChosen] = useState(LANGUAGES[0].id);
  const language = LANGUAGES.find((l) => l.id === chosen) ?? LANGUAGES[0];

  return (
    <div className={styles.lang}>
      <div className={styles.langPicker} role="group" aria-label="Show Porch in">
        {LANGUAGES.map((l) => (
          <button
            key={l.id}
            type="button"
            aria-pressed={l.id === chosen}
            className={styles.langOption}
            onClick={() => setChosen(l.id)}
          >
            <span lang={l.id}>{l.name}</span>
            {l.name !== l.english ? <small>{l.english}</small> : null}
          </button>
        ))}
      </div>

      <div className={styles.langBody} aria-live="polite">
        <div className={styles.clockIpad} aria-hidden="true">
          <div className={styles.clock} lang={language.id}>
            <span className={styles.stars} />
            <span className={styles.moon} />
            <p className={styles.clockScene}>{language.scene}</p>
            <p className={styles.clockDay}>{language.day}</p>
            <p className={styles.clockTime}>
              {language.before ? <span className={styles.clockPeriod}>{language.before}</span> : null}
              {language.time}
              {language.after ? <span className={styles.clockPeriod}>{language.after}</span> : null}
            </p>
            <span className={styles.hills} />
            <span className={styles.clockCall}>
              <PhoneIcon />
              {language.call}
            </span>
          </div>
        </div>

        <div className={styles.langNotes}>
          <div className={styles.langNote}>
            <p className={styles.tag}>
              <SpeakerIcon /> Out loud
            </p>
            <p className={styles.spoken} lang={language.id}>
              “{language.spoken}”
            </p>
          </div>
          <div className={styles.langNote}>
            <p className={styles.tag}>Sarah’s message{language.id === "en" ? "" : ", translated"}</p>
            {language.id === "en" ? null : <p className={styles.original}>“{SENT}”</p>}
            <p className={styles.translated} lang={language.id}>
              “{language.message}”
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
