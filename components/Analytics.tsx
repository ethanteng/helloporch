"use client";

import { usePathname } from "next/navigation";
import { GoogleAnalytics } from "@next/third-parties/google";
import { invitePaths } from "@/lib/invite-links";

// Invitation links carry a private code; the label maker also works without analytics.
export default function Analytics({ id }: { id: string }) {
  const path = usePathname();
  const invitation = Object.values(invitePaths).some(prefix => path === prefix || path?.startsWith(`${prefix}/`));
  return invitation || path === "/labels" ? null : <GoogleAnalytics gaId={id} />;
}
