/** A small trend line for a list cell: counts a point at a time, ending in a dot. `max` is shared down the column, so a
 * Porch with one call doesn't look as busy as one with eighteen. The number beside it and the opened row's chart carry
 * the values, so the line itself is hidden from screen readers. Colors come from admin.css: s1 to s4. */
export default function Sparkline({ values, max, color }: { values: number[]; max: number; color: "s1" | "s2" | "s3" | "s4" }) {
  const width = 64, height = 22, pad = 3, last = values.length - 1, any = values.some(Boolean);
  const x = (i: number) => last === 0 ? width / 2 : i * width / last;
  const y = (value: number) => height - pad - value / Math.max(max, 1) * (height - 2 * pad);
  return (
    <svg className={any ? `spark ${color}` : "spark"} width={width} height={height} viewBox={`0 0 ${width} ${height}`} aria-hidden="true">
      <line className="base" x1={0} x2={width} y1={height - pad} y2={height - pad} />
      {any && last > 0 && <polyline className="line" points={values.map((v, i) => `${x(i)},${y(v)}`).join(" ")} />}
      {any && <circle className="mark" cx={x(last)} cy={y(values[last])} r={3} />}
    </svg>
  );
}
