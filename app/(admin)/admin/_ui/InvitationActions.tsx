"use client";
import { useActionState } from "react";
import { cancelInvitationAction, sendAgainAction } from "../actions";
import { useShowLink } from "./Links";

/** **Cancel** for a waiting invitation, **Send again** for an expired or cancelled one. */
export default function InvitationActions({ id, state }: { id: string; state: string }) {
  const [cancelled, cancel, cancelling] = useActionState(cancelInvitationAction, {});
  const [again, send, sending] = useActionState(sendAgainAction, {});
  useShowLink(again.created);
  if (state === "waiting") return (
    <form action={cancel}>
      <input type="hidden" name="id" value={id} />
      <button type="submit" className="secondary small" disabled={cancelling}>{cancelling ? "Cancelling…" : "Cancel"}</button>
      {cancelled.error && <p role="alert" className="error">{cancelled.error}</p>}
    </form>
  );
  if ((state !== "expired" && state !== "cancelled") || again.created) return null;
  return (
    <form action={send}>
      <input type="hidden" name="id" value={id} />
      <button type="submit" className="secondary small" disabled={sending}>{sending ? "Making link…" : "Send again"}</button>
      {again.error && <p role="alert" className="error">{again.error}</p>}
    </form>
  );
}
