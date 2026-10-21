"use client";

import { useState, type SyntheticEvent } from "react";

type Props = {
  src: string;
  poster: string;
  captions?: string;
  title: string;
  className: string;
  width?: number;
  height?: number;
};

export default function StoryVideo({ src, poster, captions, title, className, width = 1920, height = 1080 }: Props) {
  const [failed, setFailed] = useState(false);

  // Only one film plays at a time.
  function play(event: SyntheticEvent<HTMLVideoElement>) {
    const current = event.currentTarget;
    document.querySelectorAll("video").forEach((video) => {
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
        width={width}
        height={height}
        aria-label={title}
        onPlay={play}
        onError={() => setFailed(true)}
      >
        {captions ? <track kind="captions" src={captions} srcLang="en" label="English" /> : null}
        Your browser does not support embedded video. <a href={src}>Watch {title}</a>.
      </video>
      {failed ? (
        <p role="status">
          This video couldn’t load. <a href={src}>Open the video</a>
          {captions ? ", or read the transcript below." : "."}
        </p>
      ) : null}
    </div>
  );
}
