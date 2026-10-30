import type { Metadata, Viewport } from "next";
import "./admin.css";

// The admin page's own root layout: none of the website's styles, fonts or analytics.
export const metadata: Metadata = {
  title: { default: "Porch admin", template: "%s · Porch admin" },
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};
export const viewport: Viewport = { colorScheme: "light dark" };

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
