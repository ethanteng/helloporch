"use client";
import { useActionState } from "react";
import { createInvitationAction } from "../actions";
import { useShowLink } from "./Links";

export default function InvitationForm() {
  const [state, action, pending] = useActionState(createInvitationAction, {});
  useShowLink(state.created);
  return (
    <>
      <form action={action} className="row invite">
        <label className="field grow">
          <span>Who it&apos;s for</span>
          <input name="label" placeholder="Lee family" maxLength={80} required autoComplete="off" />
        </label>
        <button type="submit" disabled={pending}>{pending ? "Making link…" : "Make setup link"}</button>
      </form>
      {state.error && <p role="alert" className="error">{state.error}</p>}
    </>
  );
}
