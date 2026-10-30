"use client";
import { useActionState } from "react";
import { signInAction } from "../actions";

export default function SignInForm() {
  const [state, action, pending] = useActionState(signInAction, {});
  return (
    <form action={action} className="stack">
      <label className="field">
        <span>Password</span>
        <input type="password" name="password" autoComplete="current-password" required autoFocus />
      </label>
      {state.error && <p role="alert" className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>{pending ? "Signing in…" : "Sign in"}</button>
    </form>
  );
}
