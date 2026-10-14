"use client";

import { createContext, useContext, useState, type FormEvent, type ReactNode } from "react";

const WHO_OPTIONS = ["My mom", "My dad", "Both parents", "A grandparent", "Someone I care for"];

type Source = "hero" | "join";

type State = {
  email: string | null;
  from: Source | null;
  who: string | null;
  pending: boolean;
  error: string | null;
  submit: (email: string, from: Source) => Promise<void>;
  pick: (who: string) => void;
};

const Ctx = createContext<State | null>(null);

function useWaitlist() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useWaitlist must be used inside <WaitlistProvider>");
  return v;
}

async function post(body: Record<string, string>) {
  const res = await fetch("/api/waitlist", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error((await res.json().catch(() => null))?.error || "Something went wrong");
}

// Both waitlist forms on the page share this state, so joining from either one flips both to "thanks".
// `from` remembers which form was used, so progress, errors and the follow-up question stay where the visitor is looking.
export function WaitlistProvider({ children }: { children: ReactNode }) {
  const [email, setEmail] = useState<string | null>(null);
  const [from, setFrom] = useState<Source | null>(null);
  const [who, setWho] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (value: string, source: Source) => {
    setFrom(source);
    setPending(true);
    setError(null);
    try {
      await post({ email: value });
      setEmail(value);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong");
    } finally {
      setPending(false);
    }
  };

  const pick = (value: string) => {
    setWho(value);
    if (email) post({ email, who: value }).catch(() => {});
  };

  return <Ctx.Provider value={{ email, from, who, pending, error, submit, pick }}>{children}</Ctx.Provider>;
}

function onSubmit(submit: State["submit"], from: Source) {
  return (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const v = String(new FormData(e.currentTarget).get("email") || "").trim();
    if (!/\S+@\S+\.\S+/.test(v)) return;
    submit(v, from);
  };
}

// Replaces a form once the visitor has joined. Only the form they used asks the follow-up question.
function Thanks({ variant }: { variant: Source }) {
  const { from, who, pick } = useWaitlist();
  const c = `${variant}-thanks`;

  return (
    <div className={c} aria-live="polite">
      <div className={`${c}__title`}>You&rsquo;re on the list.</div>
      {from === variant &&
        (who ? (
          <div className={`${c}__sub`}>Thank you. That helps us build the right thing.</div>
        ) : (
          <>
            <div className={`${c}__sub`}>One quick question: who would use Porch?</div>
            <div className="who-options">
              {WHO_OPTIONS.map((w) => (
                <button key={w} type="button" onClick={() => pick(w)}>
                  {w}
                </button>
              ))}
            </div>
          </>
        ))}
    </div>
  );
}

export function HeroWaitlist() {
  const { email, from, pending, error, submit } = useWaitlist();

  if (email) return <Thanks variant="hero" />;

  const here = from === "hero";
  return (
    <>
      <form className="pill-form pill-form--hero" onSubmit={onSubmit(submit, "hero")}>
        <input name="email" type="email" required placeholder="Your email address" aria-label="Your email address" autoComplete="email" />
        <button type="submit" disabled={pending}>
          {pending && here ? "Joining…" : "Join the waitlist"}
        </button>
      </form>
      {error && here && <p className="form-error" role="alert">{error}</p>}
    </>
  );
}

export function JoinWaitlist() {
  const { email, from, pending, error, submit } = useWaitlist();

  if (email) return <Thanks variant="join" />;

  const here = from === "join";
  return (
    <>
      <form className="pill-form pill-form--join" onSubmit={onSubmit(submit, "join")}>
        <input name="email" type="email" required placeholder="Your email address" aria-label="Your email address" autoComplete="email" />
        <button type="submit" disabled={pending}>
          {pending && here ? "Joining…" : "Join"}
        </button>
      </form>
      {error && here && <p className="form-error form-error--dark" role="alert">{error}</p>}
    </>
  );
}
