// Short portrait clips of the Porch prototype, grouped by tab on the features page.
// Posters are caption-free frames (or crops) from the clips, so the player controls don't cover burned-in text.
// Settings with nothing to watch get a screenshot instead, cropped to the part of the screen that matters.
export type Clip = {
  id: string;
  title: string;
  description: string;
  duration: string;
  src: string;
  poster: string;
};

export type Screenshot = {
  id: string;
  title: string;
  description: string;
  label: string;
  image: string;
  alt: string;
};

export const calling: Clip[] = [
  {
    id: "first-real-call",
    title: "Mom’s first real call",
    description:
      "My mom makes her first call using Porch, right from her own desk. She presses my brother’s photo, he answers, and they’re talking face to face a few seconds later.",
    duration: "22 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Celebrate%20first%20real%20HelloPorch%20call%20compressed.mp4",
    poster: "/features/first-real-call.jpg",
  },
  {
    id: "mom-calls-me",
    title: "One button starts a video call",
    description:
      "They press your photo, your Porch app rings, and you answer. No looking up contacts, dialing numbers, or navigating menus.",
    duration: "15 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Mom%20Calls%20Me%20compressed.mp4",
    poster: "/features/mom-calls-me.jpg",
  },
  {
    id: "phone-fallback",
    title: "If you miss the video call",
    description:
      "Porch tries your regular phone number next, so you can still talk even if you don’t answer in the app. They only have to press once.",
    duration: "24 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Mom%20calls%20me%20%28phone%20fallback%29%20compressed.mp4",
    poster: "/features/phone-fallback.jpg",
  },
  {
    id: "video-drop-in",
    title: "Porch answers for them",
    description:
      "Call your loved one through Porch, and it announces who’s calling before answering automatically. They don’t have to do a thing.",
    duration: "15 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Video%20drop-in%20compressed.mp4",
    poster: "/features/video-drop-in.jpg",
  },
  {
    id: "send-a-message",
    title: "Leave them a message",
    description:
      "Send a quick video or voice message from the Porch app. It could be an appointment reminder, a family update, or just a quick hello.",
    duration: "26 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Send%20a%20message%20compressed.mp4",
    poster: "/features/send-a-message.jpg",
  },
  {
    id: "auto-play-messages",
    title: "Messages play automatically",
    description:
      "When they’re in front of the tablet, Porch plays their waiting messages. No notifications to notice, inboxes to check, or buttons to press.",
    duration: "16 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Auto-play%20messages%20compressed.mp4",
    poster: "/features/auto-play-messages.jpg",
  },
  // A film of the app's own 3-way calling screens, rendered by scripts/render-three-way-film.mjs.
  {
    id: "three-way-calling",
    title: "Bring someone else into the call",
    description:
      "Add another family member, an old friend, or even someone from the bank when they need to speak with your loved one directly. Everyone can be on the same call.",
    duration: "22 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/3-way%20calling%20v2%20compressed.mp4",
    poster: "/features/three-way-calling.jpg",
  },
];

export const accessibility: Clip[] = [
  {
    id: "multi-language",
    title: "In the language they grew up with",
    description:
      "Choose English, Mandarin, Cantonese, or Spanish. Porch displays its screens and speaks its announcements in their language, so they don’t have to figure things out in English.",
    duration: "17 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Multi-language%20support%20compressed.mp4",
    poster: "/features/multi-language.jpg",
  },
  {
    id: "choosing-the-keypad",
    title: "Why we chose a big-button phone",
    description:
      "We tried a few different keypads before settling on a familiar corded phone with big buttons and photos. Here’s what we tried and why this one worked best for my mom.",
    duration: "4 min 24 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Form%20factor%20selection%20with%20closing%20card%20compressed.mp4",
    poster: "/features/choosing-the-keypad.jpg",
  },
];

export const safety: Screenshot[] = [
  {
    id: "block-unknown-callers",
    title: "Unknown callers are blocked",
    description:
      "Only approved people can call your loved one’s Porch. Unknown numbers are blocked by default, so they don’t have to deal with unwanted calls.",
    label: "On by default",
    image: "/features/block-unknown-callers.png",
    alt: "Porch’s Calls settings in caregiver mode on an iPhone. Under “Calls to Mom,” Block unknown callers is switched on, with the note “Only keypad contacts and numbers you allow can ring.” Below it, Blocked numbers shows 4, with 1 allowed.",
  },
];

const allClips = [...calling, ...accessibility];

/** A clip by its id, for the story at the top of the page to play. */
export function clip(id: string): Clip {
  const found = allClips.find((c) => c.id === id);
  if (!found) throw new Error(`No clip with id "${id}"`);
  return found;
}
