import type { Metadata, Viewport } from "next";
import { Bricolage_Grotesque, DM_Sans, Newsreader } from "next/font/google";
import Analytics from "@/components/Analytics";
import { SITE_URL } from "@/lib/site-metadata";
import "./globals.css";

const serif = Newsreader({ subsets: ["latin"], style: ["normal", "italic"], axes: ["opsz"], variable: "--font-serif" });
const sans = DM_Sans({ subsets: ["latin"], axes: ["opsz"], variable: "--font-sans" });
const brand = Bricolage_Grotesque({ subsets: ["latin"], axes: ["opsz"], variable: "--font-brand" });

// Pages set their own titles, descriptions, canonical links and link previews (lib/site-metadata.ts); these are the
// fallback, and metadataBase turns their relative URLs into helloporch.store ones.
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "HelloPorch | A video calling app for people with dementia, Parkinson’s or shaky hands",
  description: "Porch is an app that turns your own iPad or Android tablet into a simple video phone. One press on a big-button phone starts a video call. Made for Parkinson’s, dementia and shaky hands.",
};

export const viewport: Viewport = {
  themeColor: "#f7f0de",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${serif.variable} ${sans.variable} ${brand.variable}`}>
      <body>{children}</body>
      {/* Only the production deployment reports to Google Analytics, so local dev and preview visits stay out, and never
          from invitation pages. */}
      {process.env.VERCEL_ENV === "production" && <Analytics id="G-84FVKFX34W" />}
    </html>
  );
}
