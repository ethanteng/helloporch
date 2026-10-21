"use client";

import { useState, type SyntheticEvent } from "react";

type Props = {
  src: string;
  poster: string;
  captions: string;
  title: string;
  className: string;
};

export default function StoryVideo({ src, poster, captions, title, className }: Props) {
  const [failed, setFailed] = useState(false);

  function play(event: SyntheticEvent<HTMLVideoElement>) {
    const current = event.currentTarget;
    current.closest("[data-story-page]")?.querySelectorAll("video").forEach((video) => {
      if (video !== current) video.pause();
    });
  }

  return (
    <div className={className}>
      <video
        src={src}
        poster={poster}
        controls
        playsInline
        crossOrigin="anonymous"
        preload="none"
        width={1920}
        height={1080}
        aria-label={title}
        onPlay={play}
        onError={() => setFailed(true)}
      >
        <track kind="captions" src={captions} srcLang="en" label="English" />
        Your browser does not support embedded video. <a href={src}>Watch {title}</a>.
      </video>
      {failed ? (
        <p role="status">
          This video couldn’t load. <a href={src}>Open the video</a>, or read the transcript below.
        </p>
      ) : null}
    </div>
  );
}
