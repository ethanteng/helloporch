export type PhotoFraming = { fit: "whole" | "fill"; zoom: number; x: number; y: number };

export const MAX_PHOTO_ZOOM = 3;
export const WHOLE_PHOTO: PhotoFraming = { fit: "whole", zoom: 1, x: 0, y: 0 };

export function clampPosition(value: number) {
  return Math.max(-1, Math.min(1, value));
}

/** Coordinates are in print points. Positions range from one edge to the other. */
export function photoPlacement(width: number, height: number, imageWidth: number, imageHeight: number, hasName: boolean, framing?: PhotoFraming) {
  const caption = hasName ? Math.min(26, height * 0.36) : 0;
  const photoHeight = height - caption;
  const fit = framing?.fit ?? "whole";
  const zoom = framing?.zoom ?? 1;
  const scale = (fit === "fill" ? Math.max : Math.min)(width / imageWidth, photoHeight / imageHeight) * zoom;
  const w = imageWidth * scale;
  const h = imageHeight * scale;
  // For unedited photos, keep the image snug against its name as before.
  const frame = framing ?? { ...WHOLE_PHOTO, y: hasName && h < photoHeight ? 1 : 0 };
  const travelX = Math.abs(width - w);
  const travelY = Math.abs(photoHeight - h);
  const x = (width - w + clampPosition(frame.x) * travelX) / 2;
  const y = (photoHeight - h + clampPosition(frame.y) * travelY) / 2;
  const visibleLeft = Math.max(0, x);
  const visibleWidth = Math.min(width, x + w) - visibleLeft;
  return { x, y, w, h, caption, photoHeight, travelX, travelY, visibleLeft, visibleWidth, frame };
}
