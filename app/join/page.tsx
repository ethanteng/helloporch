import type { Metadata } from "next";
import InviteLanding from "@/components/InviteLanding";

export const metadata: Metadata = {
  title: "Join your family's Porch | HelloPorch",
  description: "Open a private Porch invitation.",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

// A family member's invitation, https://helloporch.store/join#code=… (see lib/invite-links.ts).
export default function JoinPage() {
  return <InviteLanding kind="family" />;
}
