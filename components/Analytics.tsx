"use client";

import { usePathname } from "next/navigation";
import { GoogleAnalytics } from "@next/third-parties/google";
import { invitePaths } from "@/lib/invite-links";

// Invitation pages carry a private code in their link, so they never load Google Analytics. People arrive at them
// from a link in a message, so the page loads fresh and nothing has loaded it before.
export default function Analytics({ id }: { id: string }) {
  const path = usePathname();
  const invitation = Object.values(invitePaths).some(prefix => path === prefix || path?.startsWith(`${prefix}/`));
  return invitation ? null : <GoogleAnalytics gaId={id} />;
}
