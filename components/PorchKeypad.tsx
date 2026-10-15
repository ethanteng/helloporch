import { useId, type CSSProperties } from "react";
import PorchFace, { type Who } from "@/components/PorchFace";

const FAMILY: { who: Who; name: string }[] = [
  { who: "sarah", name: "Sarah" },
  { who: "mike", name: "Mike" },
  { who: "emma", name: "Emma" },
];

type KeyProps = { who?: Who; name?: string; pressed?: boolean };

// A square key built from stacked layers: a black bezel, then a glossy screen
// standing on a short wall that sinks when pressed. With no `who`, it's HELP.
export function ScreenKey({ who, name, pressed = false }: KeyProps) {
  const travel = pressed ? 2 : 8;
  return (
    <div className={who ? "key" : "key key--help"}>
      <div className="key__layer key__shadow" />
      {Array.from({ length: 8 }, (_, i) => (
        <div
          key={i}
          className="key__layer"
          style={{ background: `oklch(${(0.07 + i * 0.008).toFixed(3)} 0.01 60)`, transform: `translateZ(${i * 2}px)` }}
        />
      ))}
      <div className="key__layer key__rim" />
      {Array.from({ length: travel }, (_, i) => (
        <div key={i} className="key__wall" style={{ transform: `translateZ(${17 + i * 2}px)` }} />
      ))}
      <div className="key__screen" style={{ transform: `translateZ(${16 + travel * 2}px)` }}>
        {who ? (
          <>
            <PorchFace who={who} shape="rect" width="100%" height="100%" style={{ position: "absolute", inset: 0 }} />
            <div className="key__name">{name}</div>
          </>
        ) : (
          <div className="key__help">HELP</div>
        )}
        <div className="key__gloss" />
        <div className="key__glint" />
      </div>
    </div>
  );
}

/* The keypad: a white wedge seen from the front left, with the keys on its sloped face. */
export default function PorchKeypad({ style }: { style?: CSSProperties }) {
  const id = "pk" + useId().replace(/[^a-zA-Z0-9_-]/g, "");
  return (
    <div className="keypad" style={style} aria-hidden>
      <div className="keypad__view">
        <div className="keypad__body">
          <div className="keypad__shadow" />
          <svg className="keypad__side" width="240" height="200" viewBox="0 0 240 200">
            <defs>
              <linearGradient id={`${id}s`} x1="0" y1="0" x2="1" y2="1">
                <stop offset="0" stopColor="oklch(0.88 0.007 78)" />
                <stop offset="1" stopColor="oklch(0.76 0.012 68)" />
              </linearGradient>
              <filter id={`${id}g`} x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="5" />
              </filter>
            </defs>
            <polygon points="5,195 235,195 170,5" fill={`url(#${id}s)`} stroke={`url(#${id}s)`} strokeWidth="10" strokeLinejoin="round" />
            <line x1="26" y1="182" x2="156" y2="30" stroke="oklch(0.85 0.15 75)" strokeWidth="9" strokeLinecap="round" filter={`url(#${id}g)`} />
            <line x1="26" y1="182" x2="156" y2="30" stroke="oklch(0.95 0.08 85)" strokeWidth="4" strokeLinecap="round" />
          </svg>
          <div className="keypad__top">
            <div className="keypad__logo">
              porch<span>.</span>
            </div>
            <div className="keypad__keys">
              {FAMILY.map((f) => (
                <ScreenKey key={f.who} who={f.who} name={f.name} />
              ))}
              <div className="keypad__gap" />
              <ScreenKey />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
