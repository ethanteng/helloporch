// Short portrait clips of the Porch prototype, grouped by tab on the features page.
// Posters are caption-free frames (or crops) from the clips, so the player controls don't cover burned-in text.
export type Clip = {
  id: string;
  title: string;
  description: string;
  duration: string;
  src: string;
  poster: string;
};

export const calling: Clip[] = [
  {
    id: "mom-calls-me",
    title: "One press, and you’re face to face.",
    description:
      "They press the button with your photo on it. Your phone rings in the Porch app, you answer, and you’re seeing each other in seconds. Nothing to find, unlock, or remember.",
    duration: "15 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Mom%20Calls%20Me%20compressed.mp4",
    poster: "/features/mom-calls-me.jpg",
  },
  {
    id: "phone-fallback",
    title: "Their call still gets through.",
    description:
      "Porch tries a video call first. If you don’t answer in the app, it rings your regular phone instead, and you talk by voice. For them, it’s still just one press.",
    duration: "24 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Mom%20calls%20me%20%28phone%20fallback%29%20compressed.mp4",
    poster: "/features/phone-fallback.jpg",
  },
  {
    id: "video-drop-in",
    title: "Stop by, like you would on the porch.",
    description:
      "People they trust can drop in with video or voice. Porch says who’s coming, counts down 3, 2, 1, and connects on its own, so they don’t have to answer.",
    duration: "15 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Video%20drop-in%20compressed.mp4",
    poster: "/features/video-drop-in.jpg",
  },
  {
    id: "send-a-message",
    title: "Send a hello, any time.",
    description:
      "Record a short video or voice message on your phone, whether it’s a reminder about Tuesday’s appointment or just “I love you.” It shows up on their Porch right away, and you’ll see when they’ve played it.",
    duration: "26 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Send%20a%20message%20compressed.mp4",
    poster: "/features/send-a-message.jpg",
  },
  {
    id: "auto-play-messages",
    title: "Your message finds them.",
    description:
      "When they’re there to see it, Porch plays your message on its own. They don’t have to remember to check or figure out how to open it, so nothing you send goes unseen.",
    duration: "16 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Auto-play%20messages%20compressed.mp4",
    poster: "/features/auto-play-messages.jpg",
  },
];

export const accessibility: Clip[] = [
  {
    id: "multi-language",
    title: "In the language they grew up with.",
    description:
      "Set Porch to Mandarin, Cantonese, Spanish, or English. The clock and call screens switch over, and Porch speaks its announcements in that language too, so everything they see and hear feels familiar.",
    duration: "17 sec",
    src: "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Multi-language%20support%20compressed.mp4",
    poster: "/features/multi-language.jpg",
  },
];
