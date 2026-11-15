// Short portrait clips of the Porch prototype, grouped by tab on the features page, and the odd widescreen film.
// Posters are caption-free frames (or crops) from the clips, so the player controls don't cover burned-in text.
// Settings with nothing to watch get a screenshot instead, cropped to the part of the screen that matters.
export type Clip = {
  id: string;
  title: string;
  description: string;
  duration: string;
  src: string;
  poster: string;
  /** A 16:9 film rather than a portrait clip. It sits in the same card, at its own shape rather than cropped. */
  landscape?: boolean;
};

export type Screenshot = {
  id: string;
  title: string;
  description: string;
  label: string;
  image: string;
  alt: string;
};

// The language clips live under Translation and are shown again under Calling and Accessibility. Every tab is in
// the page at once, so each copy takes its own id; the plain ids (#live-translation, #translated-texts,
// #multi-language) open Translation.

// The launch film for in-call translation, the story from the launch email.
const liveTranslation: Clip = {
  id: "live-translation",
  title: "Live translation on our calls",
  description:
    "My mom speaks Mandarin, and my Mandarin doesn’t go much past asking where the bathroom is. Everyday chats are fine, but harder talks, like her health or a doctor’s appointment, used to fall apart. Now I can turn on translation during a call: she hears me in Mandarin and I hear her in English, even when I mix the two.",
  duration: "59 sec",
  src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/helloporch-live-translation.mp4",
  poster: "/features/live-translation.jpg",
  landscape: true,
};

const translatedTexts: Clip = {
  id: "translated-texts",
  title: "I text in English, Mom hears it in Mandarin",
  description:
    "Not every family shares a first language. When I text my mom in English, Porch translates it and reads it to her in Mandarin, with the words on her screen too.",
  duration: "26 sec",
  src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/sms_translation.MP4",
  poster: "/features/translated-texts.jpg",
};

const multiLanguage: Clip = {
  id: "multi-language",
  title: "Porch in their own language",
  description:
    "Porch can run in English, Mandarin, Cantonese, Spanish, Tagalog, or Korean. Whichever you pick, the screens and everything Porch says out loud switch over, so they’re not stuck trying to follow along in English.",
  duration: "17 sec",
  src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Multi-language%20support%20compressed.mp4",
  poster: "/features/multi-language.jpg",
};

export const calling: Clip[] = [
  {
    id: "first-real-call",
    title: "Mom’s first real call",
    description:
      "This is the first time my mom used Porch for real. She pressed my brother’s photo at her desk, and a few seconds later they were talking face to face.",
    duration: "22 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Celebrate%20first%20real%20HelloPorch%20call%20compressed.mp4",
    poster: "/features/first-real-call.jpg",
  },
  {
    id: "mom-calls-me",
    title: "Mom calls me",
    description: "She presses my photo, and my phone rings in the Porch app. That’s all she has to do.",
    duration: "15 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Mom%20Calls%20Me%20compressed.mp4",
    poster: "/features/mom-calls-me.jpg",
  },
  {
    id: "phone-fallback",
    title: "If I miss it in the app",
    description:
      "If I don’t pick up in the Porch app, it calls my regular phone number next. She only pressed once, and we still get to talk.",
    duration: "24 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Mom%20calls%20me%20%28phone%20fallback%29%20compressed.mp4",
    poster: "/features/phone-fallback.jpg",
  },
  {
    id: "video-drop-in",
    title: "When I call her, Porch picks up",
    description: "Porch tells my mom out loud who’s calling, then answers on its own. She doesn’t have to touch anything.",
    duration: "15 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Video%20drop-in%20compressed.mp4",
    poster: "/features/video-drop-in.jpg",
  },
  {
    id: "send-a-message",
    title: "Leaving a message",
    description:
      "You can send a quick video or voice message from the Porch app. It might be a reminder about an appointment, some family news, or just a hello.",
    duration: "26 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Send%20a%20message%20compressed.mp4",
    poster: "/features/send-a-message.jpg",
  },
  {
    id: "auto-play-messages",
    title: "Messages play on their own",
    description:
      "When she’s in front of the tablet, Porch plays whatever messages are waiting for her. There’s nothing for her to open or check.",
    duration: "16 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Auto-play%20messages%20compressed.mp4",
    poster: "/features/auto-play-messages.jpg",
  },
  { ...translatedTexts, id: "translated-texts-calling" },
  // A film of the app's own 3-way calling screens, rendered by scripts/render-three-way-film.mjs.
  {
    id: "three-way-calling",
    title: "Adding someone to the call",
    description:
      "If someone else needs to be on the call, you can add them. That could be another relative, an old friend, or the bank when they need to talk to her directly.",
    duration: "22 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/3-way%20calling%20v2%20compressed.mp4",
    poster: "/features/three-way-calling.jpg",
  },
  { ...liveTranslation, id: "live-translation-calling" },
];

// Wherever they appear, the language clips go in this order, live translation last.
export const translation: Clip[] = [multiLanguage, translatedTexts, liveTranslation];

export const accessibility: Clip[] = [
  { ...multiLanguage, id: "multi-language-accessibility" },
  { ...translatedTexts, id: "translated-texts-accessibility" },
  {
    id: "choosing-the-keypad",
    title: "Why we picked a big-button phone",
    description:
      "We tried a few different keypads before landing on a regular corded phone with big buttons and photos on them. In this video I go through what we tried and why this one worked best for my mom.",
    duration: "4 min 24 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Form%20factor%20selection%20with%20closing%20card%20compressed.mp4",
    poster: "/features/choosing-the-keypad.jpg",
  },
  { ...liveTranslation, id: "live-translation-accessibility" },
];

export const safety: Screenshot[] = [
  {
    id: "block-unknown-callers",
    title: "Only people you approve can call",
    description:
      "The people on her keypad, plus any numbers you allow, can ring her Porch. Every other number gets blocked, so spam calls don’t reach her.",
    label: "On by default",
    image: "/features/block-unknown-callers.png",
    alt: "Porch’s Calls settings in caregiver mode on an iPhone. Under “Calls to Mom,” Block unknown callers is switched on, with the note “Only keypad contacts and numbers you allow can ring.” Below it, Blocked numbers shows 4, with 1 allowed.",
  },
];

const allClips = [...calling, ...translation, ...accessibility];

/** A clip by its id, for the story at the top of the page to play. */
export function clip(id: string): Clip {
  const found = allClips.find((c) => c.id === id);
  if (!found) throw new Error(`No clip with id "${id}"`);
  return found;
}
