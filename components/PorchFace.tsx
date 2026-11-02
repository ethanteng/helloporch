"use client";

import { useEffect, useId, useRef, useState, type CSSProperties, type ReactNode } from "react";

const INK = "oklch(0.25 0.03 45)";

type Style = "walt" | "bob" | "short" | "bun" | "curly";
type Person = { skin: string; shade: string; hair: string; shirt: string; bg: string; style: Style; off: number };

const PEOPLE = {
  walt: { skin: "oklch(0.80 0.06 60)", shade: "oklch(0.68 0.07 50)", hair: "oklch(0.94 0.01 80)", shirt: "oklch(0.55 0.08 150)", bg: "oklch(0.86 0.07 85)", style: "walt", off: 0.3 },
  sarah: { skin: "oklch(0.77 0.07 55)", shade: "oklch(0.66 0.08 45)", hair: "oklch(0.48 0.11 40)", shirt: "oklch(0.62 0.09 250)", bg: "oklch(0.86 0.06 40)", style: "bob", off: 1.7 },
  mike: { skin: "oklch(0.62 0.08 50)", shade: "oklch(0.53 0.08 45)", hair: "oklch(0.28 0.03 40)", shirt: "oklch(0.72 0.1 80)", bg: "oklch(0.85 0.06 150)", style: "short", off: 2.9 },
  emma: { skin: "oklch(0.85 0.05 65)", shade: "oklch(0.75 0.06 55)", hair: "oklch(0.82 0.1 85)", shirt: "oklch(0.66 0.12 20)", bg: "oklch(0.85 0.05 280)", style: "bun", off: 0.9 },
  rose: { skin: "oklch(0.79 0.06 55)", shade: "oklch(0.68 0.07 45)", hair: "oklch(0.89 0.01 80)", shirt: "oklch(0.6 0.1 330)", bg: "oklch(0.87 0.06 60)", style: "curly", off: 2.2 },
} satisfies Record<string, Person>;

export type Who = keyof typeof PEOPLE;

// One shared ~30fps clock for every face on the page.
const subscribers = new Set<(t: number) => void>();
let raf = 0;
let t0 = 0;
let last = 0;
function loop(ts: number) {
  if (ts - last > 33) {
    last = ts;
    const t = (ts - t0) / 1000;
    subscribers.forEach((fn) => fn(t));
  }
  raf = requestAnimationFrame(loop);
}
function subscribe(fn: (t: number) => void) {
  subscribers.add(fn);
  if (subscribers.size === 1) {
    if (!t0) t0 = performance.now();
    raf = requestAnimationFrame(loop);
  }
  return () => {
    subscribers.delete(fn);
    if (subscribers.size === 0) cancelAnimationFrame(raf);
  };
}

// Animates only while on screen, and not at all for reduced-motion users.
function useClock(ref: React.RefObject<SVGSVGElement | null>) {
  const [t, setT] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let unsub: (() => void) | null = null;
    const io = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && !unsub) unsub = subscribe(setT);
      else if (!entry.isIntersecting && unsub) {
        unsub();
        unsub = null;
      }
    });
    io.observe(el);
    return () => {
      io.disconnect();
      unsub?.();
    };
  }, [ref]);
  return t;
}

type Props = {
  who: Who;
  shape?: "circle" | "rect" | "none";
  size?: number;
  width?: number | string;
  height?: number | string;
  talking?: boolean;
  style?: CSSProperties;
  className?: string;
};

export default function PorchFace({ who, shape = "circle", size = 120, width, height, talking = false, style, className }: Props) {
  const p: Person = PEOPLE[who];
  const svgRef = useRef<SVGSVGElement>(null);
  const t = useClock(svgRef);
  const clipId = "pf" + useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const w = width ?? size;
  const h = height ?? size;

  // Rounded, so the server's first frame matches the browser's: their Math.sin can differ in the last digits.
  const round = (n: number) => Math.round(n * 100) / 100;
  const o = p.off;
  const period = 3.6 + o * 0.4;
  const blink = (t + o) % period < 0.13 ? 0.1 : 1;
  const bob = round(Math.sin(t * 1.3 + o) * (talking ? 2.6 : 1.4));
  const tilt = round(Math.sin(t * 0.7 + o) * (talking ? 3 : 1.6));
  const open = talking ? round(1.5 + 8 * Math.abs(Math.sin(t * 10.5 + o) * Math.sin(t * 3.1 + o * 2))) : 0;
  const [ba, by] = [-4, -2]; // happy brows

  const mouth = talking ? (
    <ellipse cx="100" cy="131" rx={9 + open * 0.2} ry={open} fill="oklch(0.38 0.08 25)" />
  ) : (
    <path d="M85 127 Q100 142 115 127" stroke={INK} strokeWidth="3.6" fill="none" strokeLinecap="round" />
  );

  const back: Partial<Record<Style, ReactNode>> = {
    bob: <rect x="40" y="62" width="120" height="98" rx="44" fill={p.hair} />,
    bun: <circle cx="100" cy="38" r="21" fill={p.hair} />,
    curly: (
      <g fill={p.hair}>
        {[[58, 84], [66, 58], [88, 42], [112, 42], [134, 56], [142, 84], [52, 108], [148, 108]].map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r="21" />
        ))}
      </g>
    ),
  };
  const front: Record<Style, ReactNode> = {
    bob: <path d="M54 102 Q50 44 100 42 Q150 44 146 102 Q140 72 118 62 Q96 76 60 78 Q55 90 54 102Z" fill={p.hair} />,
    short: <path d="M55 94 Q54 42 100 40 Q146 42 145 94 Q140 66 128 60 Q100 68 72 60 Q60 68 55 94Z" fill={p.hair} />,
    bun: <path d="M54 98 Q52 44 100 42 Q148 44 146 98 Q132 60 100 58 Q80 60 54 98Z" fill={p.hair} />,
    curly: (
      <g fill={p.hair}>
        {[[70, 58], [88, 50], [108, 49], [127, 56]].map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r="14" />
        ))}
      </g>
    ),
    walt: (
      <g fill={p.hair}>
        <ellipse cx="56" cy="92" rx="10" ry="17" />
        <ellipse cx="144" cy="92" rx="10" ry="17" />
        <ellipse cx="100" cy="47" rx="16" ry="5" opacity=".9" />
      </g>
    ),
  };
  const browFill = who === "walt" || who === "rose" ? "oklch(0.6 0.01 70)" : who === "emma" ? "oklch(0.6 0.08 70)" : INK;

  const person = (
    <g transform={`translate(0 ${bob}) rotate(${tilt} 100 150)`}>
      <ellipse cx="100" cy="206" rx="76" ry="50" fill={p.shirt} />
      <rect x="88" y="128" width="24" height="36" rx="8" fill={p.shade} />
      {back[p.style]}
      <circle cx="54" cy="106" r="10" fill={p.skin} />
      <circle cx="146" cy="106" r="10" fill={p.skin} />
      <ellipse cx="100" cy="98" rx="46" ry="52" fill={p.skin} />
      {who === "mike" && <path d="M56 106 Q58 158 100 160 Q142 158 144 106 Q140 130 124 136 Q100 130 76 136 Q60 130 56 106Z" fill={p.hair} />}
      {front[p.style]}
      <g fill={INK}>
        <rect x="72" y={86 + by} width="20" height="4.5" rx="2.25" transform={`rotate(${ba} 82 ${88 + by})`} fill={browFill} />
        <rect x="108" y={86 + by} width="20" height="4.5" rx="2.25" transform={`rotate(${-ba} 118 ${88 + by})`} fill={browFill} />
        <g transform={`translate(0 102) scale(1 ${blink}) translate(0 -102)`}>
          <ellipse cx="83" cy="102" rx="4.6" ry="5.6" />
          <ellipse cx="117" cy="102" rx="4.6" ry="5.6" />
        </g>
      </g>
      <path d="M100 106 Q95 116 101 118" stroke={p.shade} strokeWidth="3" fill="none" strokeLinecap="round" />
      <circle cx="71" cy="119" r="8" fill="oklch(0.72 0.12 20 / .3)" />
      <circle cx="129" cy="119" r="8" fill="oklch(0.72 0.12 20 / .3)" />
      {(who === "walt" || who === "rose") && (
        <g stroke={INK} strokeWidth="2.6" fill="none">
          <circle cx="83" cy="102" r="13" />
          <circle cx="117" cy="102" r="13" />
          <path d="M96 101 Q100 98 104 101" />
        </g>
      )}
      {who === "walt" && <ellipse cx="100" cy="123" rx="15" ry="5.5" fill={p.hair} />}
      {mouth}
      {who === "sarah" && (
        <g fill="oklch(0.82 0.12 85)">
          <circle cx="54" cy="120" r="3.5" />
          <circle cx="146" cy="120" r="3.5" />
        </g>
      )}
    </g>
  );

  const common = { ref: svgRef, viewBox: "0 0 200 200", width: w, height: h, className, "aria-hidden": true } as const;

  if (shape === "none") {
    return <svg {...common} style={{ display: "block", overflow: "visible", ...style }}>{person}</svg>;
  }
  if (shape === "rect") {
    return (
      <svg {...common} preserveAspectRatio="xMidYMax meet" style={{ display: "block", ...style }}>
        <rect x="-400" y="-400" width="1000" height="1000" fill={p.bg} />
        <g transform="translate(0 14)">{person}</g>
      </svg>
    );
  }
  return (
    <svg {...common} style={{ display: "block", ...style }}>
      <defs>
        <clipPath id={clipId}>
          <circle cx="100" cy="100" r="100" />
        </clipPath>
      </defs>
      <g clipPath={`url(#${clipId})`}>
        <rect width="200" height="200" fill={p.bg} />
        <g transform="translate(0 16)">{person}</g>
      </g>
    </svg>
  );
}
