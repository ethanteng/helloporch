import type { Metadata } from "next";
import InviteLanding from "@/components/InviteLanding";

export const metadata: Metadata = {
  title: "Set up Porch | HelloPorch",
  description: "Set up a bedside iPad with a private Porch link.",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

// A new bedside's setup link, https://helloporch.store/setup#code=… (see lib/invite-links.ts).
export default function SetupPage() {
  return <InviteLanding kind="bedside" />;
}
