import type { Ref } from "react";

// A field people never see or reach with the keyboard, so anything in it came from a bot that fills in every field.
// The forms send it as `website`, and the sign-up routes quietly drop those (lib/signup-guard.ts).
export function Honeypot({ ref }: { ref?: Ref<HTMLInputElement> }) {
  return (
    <div aria-hidden="true" style={{ position: "absolute", left: "-10000px", width: 1, height: 1, overflow: "hidden" }}>
      <label>
        Leave this empty
        <input ref={ref} name="website" type="text" tabIndex={-1} autoComplete="off" />
      </label>
    </div>
  );
}
