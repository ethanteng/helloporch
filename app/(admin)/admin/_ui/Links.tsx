"use client";
import { createContext, use, useEffect, useState } from "react";
import type { LinkState } from "../actions";
import NewLink from "./NewLink";

type Created = NonNullable<LinkState["created"]>;
const Links = createContext<{ latest?: Created; waiting: string[]; show: (created: Created) => void }>({ waiting: [], show: () => {} });

/** Holds the newest setup link, from **Make setup link** or **Send again**, for `LatestLink` to show under the form.
 * `waiting`: the invitations whose links still work. A link stays up only while its invitation is one of them. */
export function InvitationLinks({ waiting, children }: { waiting: string[]; children: React.ReactNode }) {
  const [latest, show] = useState<Created>();
  return <Links value={{ latest, waiting, show }}>{children}</Links>;
}
export function LatestLink() {
  const { latest, waiting } = use(Links);
  return latest && waiting.includes(latest.id) ? <NewLink key={latest.id} {...latest} /> : null;
}
export function useShowLink(created: Created | undefined) {
  const { show } = use(Links);
  useEffect(() => { if (created) show(created); }, [created, show]);
}
