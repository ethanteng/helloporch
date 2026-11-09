"use client";

import { useEffect, useRef, useState, type PointerEvent } from "react";
import { canvasContext, loadPhoto, paintCard, type Contact, type Photo } from "@/lib/labels/artwork";
import { clampPosition, MAX_PHOTO_ZOOM, photoPlacement, WHOLE_PHOTO, type PhotoFraming } from "@/lib/labels/framing";
import { formatSize, POINTS_PER_INCH, type Dimensions } from "@/lib/labels/layout";
import styles from "./labels.module.css";

type Drag = { pointer: number; x: number; y: number; xScale: number; yScale: number; frame: PhotoFraming };

export default function PhotoEditor({ contact, dimensions, contactNumber, onCancel, onSave }: {
  contact: Contact & { photo: Photo };
  dimensions: Dimensions;
  contactNumber: number;
  onCancel: () => void;
  onSave: (framing: PhotoFraming | undefined) => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const drag = useRef<Drag | null>(null);
  const [photo, setPhoto] = useState<HTMLImageElement | null>(null);
  const [failed, setFailed] = useState(false);
  const [draft, setDraft] = useState(contact.framing);
  const width = dimensions.width * POINTS_PER_INCH;
  const height = dimensions.height * POINTS_PER_INCH;
  const hasName = Boolean(contact.name.trim());
  const placement = photo && photoPlacement(width, height, photo.naturalWidth, photo.naturalHeight, hasName, draft);
  const frame = placement?.frame ?? draft ?? WHOLE_PHOTO;
  const label = contact.name.trim() || `Contact ${contactNumber}`;

  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);

  useEffect(() => {
    let active = true;
    void loadPhoto(contact.photo).then((image) => { if (active) setPhoto(image); }, () => { if (active) setFailed(true); });
    return () => { active = false; };
  }, [contact.photo]);

  useEffect(() => {
    if (!photo || !canvas.current) return;
    try {
      const ctx = canvasContext(canvas.current);
      ctx.setTransform(canvas.current.width / width, 0, 0, canvas.current.height / height, 0, 0);
      paintCard(ctx, { ...contact, framing: draft }, width, height, photo);
    } catch {
      setFailed(true);
    }
  }, [contact, draft, height, photo, width]);

  function close(save: boolean) {
    dialog.current?.close();
    if (save) onSave(draft);
    else onCancel();
  }

  function startDrag(event: PointerEvent<HTMLCanvasElement>) {
    if (!placement || !event.isPrimary || event.button !== 0 || (placement.travelX < 0.01 && placement.travelY < 0.01)) return;
    const rect = event.currentTarget.getBoundingClientRect();
    if ((event.clientY - rect.top) / rect.height * height > placement.photoHeight) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    drag.current = {
      pointer: event.pointerId, x: event.clientX, y: event.clientY, frame,
      xScale: placement.travelX >= 0.01 ? 2 * width / (rect.width * placement.travelX) : 0,
      yScale: placement.travelY >= 0.01 ? 2 * height / (rect.height * placement.travelY) : 0,
    };
  }

  function moveDrag(event: PointerEvent<HTMLCanvasElement>) {
    const start = drag.current;
    if (!start || start.pointer !== event.pointerId) return;
    setDraft({ ...start.frame,
      x: clampPosition(start.frame.x + (event.clientX - start.x) * start.xScale),
      y: clampPosition(start.frame.y + (event.clientY - start.y) * start.yScale),
    });
  }

  const scale = 640 / Math.max(width, height);
  return (
    <dialog ref={dialog} className={styles.photoEditor} aria-labelledby="photo-editor-title" onCancel={(event) => { event.preventDefault(); close(false); }}>
      <header className={styles.photoEditorHeader}>
        <div>
          <h2 id="photo-editor-title">Adjust photo</h2>
          <p>{label} · {formatSize(dimensions)}</p>
        </div>
        <button type="button" className={styles.editorClose} aria-label="Close photo editor" onClick={() => close(false)}>×</button>
      </header>
      <div className={styles.photoEditorBody}>
        <div className={styles.photoStage}>
          {failed ? <p role="alert">Couldn’t preview this photo.</p> : !photo ? <p role="status">Opening photo…</p> : (
            <canvas ref={canvas} width={Math.round(width * scale)} height={Math.round(height * scale)}
              style={{ width: `min(100%, 300px, calc(var(--editor-preview-height) * ${width / height}))` }}
              className={styles.photoCanvas} role="img" aria-label={`Label preview for ${label}`}
              onPointerDown={startDrag} onPointerMove={moveDrag} onLostPointerCapture={() => { drag.current = null; }} />
          )}
        </div>
        <fieldset className={styles.frameTools} disabled={!placement || failed}>
          <legend>Photo framing</legend>
          <div className={styles.frameChoices} role="group" aria-label="Photo fit">
            <button type="button" aria-pressed={frame.fit === "whole" && frame.zoom === 1} onClick={() => setDraft(undefined)}>Whole photo</button>
            <button type="button" aria-pressed={frame.fit === "fill"} onClick={() => setDraft({ ...frame, fit: "fill", zoom: 1, x: 0, y: 0 })}>Fill frame</button>
          </div>
          <p className={styles.hint}>Drag the photo or use the sliders to move it. Zoom in for more room to adjust.</p>
          <label className={styles.slider}>Zoom <span>{Math.round(frame.zoom * 100)}%</span>
            <input type="range" aria-label="Zoom" min={100} max={MAX_PHOTO_ZOOM * 100} value={Math.round(frame.zoom * 100)} onChange={(event) => setDraft({ ...frame, zoom: Number(event.target.value) / 100 })} />
          </label>
          {([ ["x", "Horizontal position", "left", "right", placement?.travelX], ["y", "Vertical position", "up", "down", placement?.travelY] ] as const).map(([axis, title, negative, positive, travel]) => {
            const value = Math.round(frame[axis] * 100);
            return <label className={styles.slider} key={axis}>{title}
              <input type="range" aria-label={title} aria-valuetext={value ? `${Math.abs(value)}% ${value < 0 ? negative : positive}` : "Centered"}
                min={-100} max={100} value={value} disabled={(travel ?? 0) < 0.01} onChange={(event) => setDraft({ ...frame, [axis]: Number(event.target.value) / 100 })} />
            </label>;
          })}
          <button type="button" className={styles.textButton} onClick={() => setDraft({ ...frame, x: 0, y: 0 })}>Center photo</button>
        </fieldset>
      </div>
      <footer className={styles.photoEditorFooter}>
        <button type="button" className={styles.cancelEdit} onClick={() => close(false)}>Cancel</button>
        <button type="button" className={styles.applyEdit} disabled={!photo || failed} onClick={() => close(true)}>Use this framing</button>
      </footer>
    </dialog>
  );
}
