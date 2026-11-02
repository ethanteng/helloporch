"use client";

import { useEffect, useRef, useState, type MouseEvent, type SyntheticEvent } from "react";
import type { Clip } from "./clips";
import { CloseIcon, PlayIcon } from "./icons";
import styles from "./story.module.css";

// A button that plays one clip in a dialog over the page, so the story keeps its place. The video only exists while
// the dialog is open, so closed dialogs don't load posters, and closing it stops the clip.
export default function WatchClip({ clip, label, hero = false }: { clip: Clip; label: string; hero?: boolean }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const video = useRef<HTMLVideoElement>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    dialog.current?.showModal();
    // Some browsers only start a clip with sound from its own play button, which stays on screen.
    video.current?.play().catch(() => {});
  }, [open]);

  function close() {
    dialog.current?.close();
  }

  // A click on the backdrop lands on the dialog itself.
  function onDialogClick(event: MouseEvent<HTMLDialogElement>) {
    if (event.target === event.currentTarget) close();
  }

  // Only one clip plays at a time, as in the clips below.
  function onPlay(event: SyntheticEvent<HTMLVideoElement>) {
    const current = event.currentTarget;
    document.querySelectorAll("video").forEach((other) => {
      if (other !== current) other.pause();
    });
  }

  return (
    <>
      <button
        type="button"
        className={hero ? `hero__secondary ${styles.heroWatch}` : styles.watch}
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        <span className={hero ? "hero__secondary-icon" : styles.watchIcon}>
          <PlayIcon className={styles.playGlyph} />
        </span>
        <span>
          {label} <span className={styles.watchTime}>· {clip.duration}</span>
        </span>
      </button>
      <dialog ref={dialog} className={styles.lightbox} aria-label={clip.title} onClose={() => setOpen(false)} onClick={onDialogClick}>
        {open ? (
          <div className={styles.lightboxBody}>
            <div className={styles.lightboxBar}>
              <p>{clip.title}</p>
              <button type="button" className={styles.lightboxClose} onClick={close} aria-label="Close">
                <CloseIcon />
              </button>
            </div>
            <video
              ref={video}
              src={clip.src}
              poster={clip.poster}
              controls
              playsInline
              crossOrigin="anonymous"
              width={1080}
              height={1920}
              aria-label={clip.title}
              onPlay={onPlay}
              className={styles.lightboxVideo}
            >
              Your browser does not support embedded video. <a href={clip.src}>Watch {clip.title}</a>.
            </video>
          </div>
        ) : null}
      </dialog>
    </>
  );
}
