"use client";

import { useEffect, useRef } from "react";

// Set NEXT_PUBLIC_DEMO_VIDEO_URL in Vercel to swap the video. It's baked in at build time.
const SRC =
  process.env.NEXT_PUBLIC_DEMO_VIDEO_URL ||
  "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/Porch%20Demo%20Video%20v2%20compressed.mp4";

// Silent demo loop: plays while on screen, pauses when scrolled away.
// Reduced-motion users get a still frame and the native controls.
export default function DemoVideo() {
  const ref = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = ref.current;
    if (!video || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) video.play().catch(() => {});
        else video.pause();
      },
      { threshold: 0.25 },
    );
    io.observe(video);
    return () => io.disconnect();
  }, []);

  return (
    <video
      ref={ref}
      className="demo__video"
      src={SRC}
      muted
      loop
      playsInline
      controls
      preload="metadata"
      aria-label="Porch demo: pressing a face on the keypad starts a video call"
    />
  );
}
