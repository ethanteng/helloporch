import assert from "node:assert/strict";
import { test } from "node:test";
import { photoPlacement } from "../lib/labels/framing.ts";
import { cornerMarks, makeSheets, parseDimensions, SCALE_MARKS } from "../lib/labels/layout.ts";

test("print sizes accept custom inch values without rounding and reject unusable sizes", () => {
  assert.deepEqual(parseDimensions("1", "1.5"), { width: 1, height: 1.5 });
  assert.deepEqual(parseDimensions("0.875", "1.3"), { width: 0.875, height: 1.3 });
  for (const width of ["", "NaN", "Infinity", "-1", "0.49", "4.1"]) assert.equal(parseDimensions(width, "1.5"), null);
});

test("custom labels retain their exact dimensions and copies across page boundaries", () => {
  const sheets = makeSheets({ width: 4, height: 3.75 }, 3, 2);
  assert.deepEqual(sheets.map((page) => page.map((card) => card.contactIndex)), [[0, 1], [2, 0], [1, 2]]);
  for (const card of sheets.flat()) {
    assert.equal(card.width, 288);
    assert.equal(card.height, 270);
    assert.equal(card.x, 36);
    assert.ok(card.y + card.height <= 720);
  }
});

test("default cut marks align to the exact 1 by 1.5 inch card and leave its content clear", () => {
  const [[card]] = makeSheets({ width: 1, height: 1.5 }, 1, 1);
  const { x, y, width, height } = card;
  assert.deepEqual([width, height], [72, 108]);
  assert.deepEqual(cornerMarks(card), [
    [x - 2, y, x - 5, y], [x, y - 2, x, y - 5],
    [x - 2, y + height, x - 5, y + height], [x, y + height + 2, x, y + height + 5],
    [x + width + 2, y, x + width + 5, y], [x + width, y - 2, x + width, y - 5],
    [x + width + 2, y + height, x + width + 5, y + height], [x + width, y + height + 2, x + width, y + height + 5],
  ]);
  assert.equal(SCALE_MARKS[0][2] - SCALE_MARKS[0][0], 72);
});

test("reframing can move a contained photo without extending its caption area beyond the photo", () => {
  const placement = photoPlacement(72, 108, 200, 400, true, { fit: "whole", zoom: 1, x: 1, y: 0 });
  assert.equal(placement.photoHeight, 82);
  assert.equal(placement.visibleWidth, 41);
  assert.equal(placement.visibleLeft, 31);
  assert.equal(placement.visibleLeft + placement.visibleWidth, 72);
});

test("panning a filled and zoomed photo to the corners still covers the printable photo area", () => {
  const left = photoPlacement(72, 108, 800, 400, true, { fit: "fill", zoom: 2, x: -1, y: -1 });
  const right = photoPlacement(72, 108, 800, 400, true, { fit: "fill", zoom: 2, x: 1, y: 1 });
  assert.equal(left.x + left.w, 72);
  assert.equal(left.y + left.h, 82);
  assert.deepEqual([right.x, right.y], [0, 0]);
  assert.equal(left.visibleWidth, 72);
  assert.equal(right.visibleWidth, 72);
});
