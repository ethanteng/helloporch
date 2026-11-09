export const LETTER_WIDTH = 612;
export const LETTER_HEIGHT = 792;
export const POINTS_PER_INCH = 72;
export const DEFAULT_WIDTH = "1";
export const DEFAULT_HEIGHT = "1.5";
export const MAX_CONTACTS = 8;
export const MIN_DIMENSION = 0.5;
export const MAX_DIMENSION = 4;
export const MAX_SETS = 10;

export const SHEET_MARGIN = 36;
export const SHEET_TOP = 90;
export const SHEET_BOTTOM = 720;
const CARD_GAP = 12;

export type Dimensions = { width: number; height: number };
export type Card = { x: number; y: number; width: number; height: number; contactIndex: number };
export type Line = readonly [number, number, number, number];

export function parseDimensions(width: string, height: string): Dimensions | null {
  const values = [width, height].map((value) => Number(value));
  if (values.some((value) => !Number.isFinite(value) || value < MIN_DIMENSION || value > MAX_DIMENSION)) return null;
  return { width: values[0], height: values[1] };
}

/** Positions use points measured from the upper-left corner of the sheet. */
export function makeSheets(dimensions: Dimensions, contactCount: number, setCount: number): Card[][] {
  const width = dimensions.width * POINTS_PER_INCH;
  const height = dimensions.height * POINTS_PER_INCH;
  const columns = Math.floor((LETTER_WIDTH - 2 * SHEET_MARGIN + CARD_GAP) / (width + CARD_GAP));
  const rows = Math.floor((SHEET_BOTTOM - SHEET_TOP + CARD_GAP) / (height + CARD_GAP));
  const capacity = columns * rows;
  if (columns < 1 || rows < 1) throw new RangeError("Label size does not fit on US Letter paper.");
  const total = contactCount * setCount;
  const pages: Card[][] = [];
  for (let start = 0; start < total; start += capacity) {
    const count = Math.min(total - start, capacity);
    pages.push(Array.from({ length: count }, (_, index) => ({
      x: SHEET_MARGIN + (index % columns) * (width + CARD_GAP),
      y: SHEET_TOP + Math.floor(index / columns) * (height + CARD_GAP),
      width,
      height,
      contactIndex: (start + index) % contactCount,
    })));
  }
  return pages;
}

export function cornerMarks({ x, y, width, height }: Card): Line[] {
  const lines: Line[] = [];
  for (const dx of [-1, 1]) {
    for (const dy of [-1, 1]) {
      const cornerX = dx < 0 ? x : x + width;
      const cornerY = dy < 0 ? y : y + height;
      lines.push([cornerX + 2 * dx, cornerY, cornerX + 5 * dx, cornerY]);
      lines.push([cornerX, cornerY + 2 * dy, cornerX, cornerY + 5 * dy]);
    }
  }
  return lines;
}

export const SCALE_Y = 748;
export const SCALE_MARKS: Line[] = [
  [SHEET_MARGIN, SCALE_Y, SHEET_MARGIN + POINTS_PER_INCH, SCALE_Y],
  [SHEET_MARGIN, SCALE_Y - 4, SHEET_MARGIN, SCALE_Y + 4],
  [SHEET_MARGIN + POINTS_PER_INCH, SCALE_Y - 4, SHEET_MARGIN + POINTS_PER_INCH, SCALE_Y + 4],
];

export function formatSize({ width, height }: Dimensions) {
  return `${width} × ${height} in`;
}
