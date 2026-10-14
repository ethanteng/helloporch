"use client";

import { createContext, useContext, useState, type FormEvent, type ReactNode } from "react";

const WHO_OPTIONS = ["My mom", "My dad", "Both parents", "A grandparent", "Someone I care for"];

type State = {
  email: string | null;
  who: string | null;
  pending: boolean;
  error: string | null;
  submit: (email: string) => Promise<void>;
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
export function WaitlistProvider({ children }: { children: ReactNode }) {
  const [email, setEmail] = useState<string | null>(null);
  const [who, setWho] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (value: string) => {
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

  return <Ctx.Provider value={{ email, who, pending, error, submit, pick }}>{children}</Ctx.Provider>;
}

function onSubmit(submit: State["submit"]) {
  return (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const v = String(new FormData(e.currentTarget).get("email") || "").trim();
    if (!/\S+@\S+\.\S+/.test(v)) return;
    submit(v);
  };
}

export function HeroWaitlist() {
  const { email, who, pending, error, submit, pick } = useWaitlist();

  if (!email) {
    return (
      <>
        <form className="pill-form pill-form--hero" onSubmit={onSubmit(submit)}>
          <input name="email" type="email" required placeholder="Your email address" aria-label="Your email address" autoComplete="email" />
          <button type="submit" disabled={pending}>
            {pending ? "Joining…" : "Join the waitlist"}
          </button>
        </form>
        {error && <p className="form-error" role="alert">{error}</p>}
      </>
    );
  }

  return (
    <div className="hero-thanks" aria-live="polite">
      <div className="hero-thanks__title">You&rsquo;re on the list.</div>
      {who ? (
        <div className="hero-thanks__sub">Thank you. That helps us build the right thing.</div>
      ) : (
        <>
          <div className="hero-thanks__sub">One quick question: who would use Porch?</div>
          <div className="who-options">
            {WHO_OPTIONS.map((w) => (
              <button key={w} type="button" onClick={() => pick(w)}>
                {w}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

export function JoinWaitlist() {
  const { email, pending, error, submit } = useWaitlist();

  if (email) return <div className="join__thanks" aria-live="polite">You&rsquo;re on the list. Thank you.</div>;

  return (
    <>
      <form className="pill-form pill-form--join" onSubmit={onSubmit(submit)}>
        <input name="email" type="email" required placeholder="Your email address" aria-label="Your email address" autoComplete="email" />
        <button type="submit" disabled={pending}>
          {pending ? "Joining…" : "Join"}
        </button>
      </form>
      {error && <p className="form-error form-error--dark" role="alert">{error}</p>}
    </>
  );
}
