/** One line a series over the same points, on one axis, with a legend. Hovering a point shows its counts, in the
 * browser's own tooltip, so it needs no script. Colors come from admin.css by each series' `color`: s1 to s4. */
export type TrendSeries = { name: string; color: "s1" | "s2" | "s3" | "s4"; values: number[] };

const width = 1000, height = 170, left = 34, right = 10, top = 8, bottom = 24;
const plotWidth = width - left - right, plotHeight = height - top - bottom;

/** The smallest of 1, 2 and 5 times a power of ten that is at least `value`, so the axis reads in clean numbers. */
function cleanStep(value: number) {
  const power = 10 ** Math.floor(Math.log10(Math.max(value, 1)));
  return [1, 2, 5, 10].map(m => m * power).find(step => step >= value) ?? 10 * power;
}

export default function TrendChart({ series, labels, description }: { series: TrendSeries[]; labels: string[]; description: string }) {
  const count = labels.length;
  const most = Math.max(1, ...series.flatMap(s => s.values)), step = cleanStep(most / 3), axisTop = Math.ceil(most / step) * step;
  const x = (i: number) => count === 1 ? left + plotWidth / 2 : left + i * plotWidth / (count - 1);
  const y = (value: number) => top + plotHeight - value / axisTop * plotHeight;
  const ticks = Array.from({ length: axisTop / step + 1 }, (_, i) => i * step);
  // Up to five dates along the bottom: the first, the last and three between.
  const dated = [...new Set([0, 0.25, 0.5, 0.75, 1].map(f => Math.round(f * (count - 1))))];
  const slot = count === 1 ? plotWidth : plotWidth / (count - 1);
  return (
    <figure className="trend">
      <ul className="legend">{series.map(s => <li key={s.name}><i className={`key ${s.color}`} />{s.name}</li>)}</ul>
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={description}>
        {ticks.map(t => (
          <g key={t}>
            <line className="rule" x1={left} x2={width - right} y1={y(t)} y2={y(t)} />
            <text x={left - 8} y={y(t) + 4} textAnchor="end">{t}</text>
          </g>
        ))}
        {dated.map(i => <text key={i} x={x(i)} y={height - 6} textAnchor={count === 1 ? "middle" : i === 0 ? "start" : i === count - 1 ? "end" : "middle"}>{labels[i].split(" – ")[0]}</text>)}
        {count > 1 && series.map(s => <polyline key={s.name} className={`line ${s.color}`} points={s.values.map((v, i) => `${x(i)},${y(v)}`).join(" ")} />)}
        {labels.map((label, i) => (
          <g key={i} className={count === 1 ? "point only" : "point"}>
            <rect className="hit" x={x(i) - slot / 2} y={top} width={slot} height={plotHeight} />
            <line className="cross" x1={x(i)} x2={x(i)} y1={top} y2={top + plotHeight} />
            {series.map(s => <circle key={s.name} className={`mark ${s.color}`} cx={x(i)} cy={y(s.values[i])} r={4} />)}
            <title>{`${label}: ${series.map(s => `${s.name.toLowerCase()} ${s.values[i]}`).join(", ")}`}</title>
          </g>
        ))}
      </svg>
    </figure>
  );
}
