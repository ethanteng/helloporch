import { cornerMarks, LETTER_HEIGHT, LETTER_WIDTH, SCALE_MARKS, SHEET_MARGIN, formatSize, type Card, type Dimensions, type Line } from "./layout";

import { photoPlacement, type PhotoFraming } from "./framing";

export type Photo = { source: string; fileName: string };
export type Contact = { name: string; photo: Photo | null; framing?: PhotoFraming };

const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const MAX_IMAGE_EDGE = 1600;
const FONT = 'Arial, "Noto Sans CJK TC", "PingFang TC", sans-serif';
const images = new WeakMap<Photo, Promise<HTMLImageElement>>();

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("This photo couldn’t be opened. Try a JPG, PNG, or WebP image."));
    image.src = src;
  });
}

export function loadPhoto(photo: Photo): Promise<HTMLImageElement> {
  let image = images.get(photo);
  if (!image) {
    image = loadImage(photo.source);
    images.set(photo, image);
  }
  return image;
}

export function canvasContext(canvas: HTMLCanvasElement) {
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Your browser couldn’t draw the labels. Try opening this page in another browser.");
  return context;
}

export async function readPhoto(file: File): Promise<Photo> {
  if (file.size > MAX_IMAGE_BYTES) throw new Error("This photo is over 20 MB. Choose a smaller image.");
  const supported = /^image\/(jpe?g|png|webp|avif|heic|heif)$/i.test(file.type);
  const recognizedExtension = /\.(jpe?g|png|webp|avif|heic|heif)$/i.test(file.name);
  if (!supported && !(recognizedExtension && (!file.type || file.type === "application/octet-stream"))) {
    throw new Error("Choose an image file, such as a JPG, PNG, or WebP.");
  }
  const url = URL.createObjectURL(file);
  try {
    const image = await loadImage(url);
    const scale = Math.min(1, MAX_IMAGE_EDGE / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvasContext(canvas);
    context.fillStyle = "white";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.imageSmoothingQuality = "high";
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    // Flatten transparency, apply the browser's orientation and strip file metadata.
    return { source: canvas.toDataURL("image/jpeg", 0.94), fileName: file.name };
  } finally {
    URL.revokeObjectURL(url);
  }
}

function splitName(name: string) {
  const words = name.split(/\s+/);
  if (words.length < 2) return [name];
  let split = 1;
  for (let i = 2; i < words.length; i++) {
    if (Math.abs(words.slice(0, i).join(" ").length - name.length / 2) < Math.abs(words.slice(0, split).join(" ").length - name.length / 2)) split = i;
  }
  return [words.slice(0, split).join(" "), words.slice(split).join(" ")];
}

function paintName(ctx: CanvasRenderingContext2D, name: string, x: number, y: number, width: number, height: number, maxSize: number) {
  const fit = (lines: string[]) => {
    ctx.font = `700 ${maxSize}px ${FONT}`;
    const widest = Math.max(...lines.map((line) => {
      const ink = ctx.measureText(line);
      return Math.max(ink.width, ink.actualBoundingBoxLeft + ink.actualBoundingBoxRight);
    }));
    return Math.min(maxSize, maxSize * width / Math.max(1, widest), height / (1.18 * lines.length));
  };
  const one = fit([name]);
  const split = splitName(name);
  const two = split.length === 2 ? fit(split) : 0;
  const lines = two > one * 1.1 ? split : [name];
  const size = lines.length === 2 ? two : one;
  if (size <= 0) return;
  ctx.font = `700 ${size}px ${FONT}`;
  ctx.textAlign = "left";
  ctx.textBaseline = "alphabetic";
  ctx.fillStyle = "#201812";
  const lineHeight = size * 1.18;
  lines.forEach((line, index) => {
    const ink = ctx.measureText(line);
    const centerY = y + height / 2 + (index - (lines.length - 1) / 2) * lineHeight;
    const inkCenterX = (ink.actualBoundingBoxRight - ink.actualBoundingBoxLeft) / 2;
    const inkCenterY = (ink.actualBoundingBoxAscent - ink.actualBoundingBoxDescent) / 2;
    ctx.fillText(line, x + width / 2 - inkCenterX, centerY + inkCenterY);
  });
}

/** Shared by the live preview and the PDF, in points. */
export function paintCard(ctx: CanvasRenderingContext2D, contact: Contact, width: number, height: number, image: HTMLImageElement | null, placeholder?: string) {
  ctx.fillStyle = "white";
  ctx.fillRect(0, 0, width, height);
  const name = contact.name.trim();
  if (image) {
    const { x, y, w, h, caption, photoHeight, visibleLeft, visibleWidth } = photoPlacement(width, height, image.naturalWidth, image.naturalHeight, Boolean(name), contact.framing);
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, width, photoHeight);
    ctx.clip();
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(image, x, y, w, h);
    ctx.restore();
    if (name) {
      const inset = Math.min(2, visibleWidth / 8);
      paintName(ctx, name, visibleLeft + inset, photoHeight + 1, visibleWidth - 2 * inset, caption - 2, 23);
    }
  } else if (name) {
    const inset = Math.min(4, width / 8);
    paintName(ctx, name, inset, inset, width - 2 * inset, height - 2 * inset, 28);
  } else if (placeholder) {
    ctx.fillStyle = "#f5eee4";
    ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = "#6c594b";
    ctx.font = `700 ${Math.min(12, width / 8)}px ${FONT}`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(placeholder, width / 2, height / 2, width - 8);
  }
}

export function sheetDescription(dimensions: Dimensions, page: number, pages: number) {
  return `${formatSize(dimensions).replace("×", "x")} per label  |  US Letter  |  Page ${page + 1} of ${pages}`;
}

export const PRINT_NOTE = "Print at Actual Size / 100%. Turn off Fit to Page.";

function drawLines(ctx: CanvasRenderingContext2D, lines: Line[], width: number) {
  ctx.lineWidth = width;
  ctx.strokeStyle = "#625d55";
  ctx.beginPath();
  lines.forEach(([x1, y1, x2, y2]) => { ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); });
  ctx.stroke();
}

export async function paintPreview(canvas: HTMLCanvasElement, contacts: Contact[], cards: Card[], dimensions: Dimensions, page: number, pages: number, current: () => boolean) {
  const photos = await Promise.all(contacts.map(({ photo }) => photo ? loadPhoto(photo).catch(() => null) : null));
  if (!current()) return;
  const scale = 1.5;
  canvas.width = LETTER_WIDTH * scale;
  canvas.height = LETTER_HEIGHT * scale;
  const ctx = canvasContext(canvas);
  ctx.scale(scale, scale);
  ctx.fillStyle = "white";
  ctx.fillRect(0, 0, LETTER_WIDTH, LETTER_HEIGHT);
  ctx.fillStyle = "#201812";
  ctx.font = `700 16px ${FONT}`;
  ctx.fillText("Porch phone labels", SHEET_MARGIN, 42);
  ctx.font = `10px ${FONT}`;
  ctx.fillText(sheetDescription(dimensions, page, pages), SHEET_MARGIN, 59);
  ctx.fillText(PRINT_NOTE, SHEET_MARGIN, 74);
  for (const card of cards) {
    ctx.save();
    ctx.translate(card.x, card.y);
    paintCard(ctx, contacts[card.contactIndex], card.width, card.height, photos[card.contactIndex], `Contact ${card.contactIndex + 1}`);
    ctx.restore();
    drawLines(ctx, cornerMarks(card), 0.6);
  }
  drawLines(ctx, SCALE_MARKS, 0.65);
  ctx.fillStyle = "#494239";
  ctx.font = `9px ${FONT}`;
  ctx.fillText("1-inch scale check", SHEET_MARGIN + 82, 751);
}
