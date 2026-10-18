import type { Metadata, Viewport } from "next";
import { Bricolage_Grotesque, DM_Sans, Newsreader } from "next/font/google";
import "./globals.css";

const serif = Newsreader({ subsets: ["latin"], style: ["normal", "italic"], axes: ["opsz"], variable: "--font-serif" });
const sans = DM_Sans({ subsets: ["latin"], axes: ["opsz"], variable: "--font-sans" });
const brand = Bricolage_Grotesque({ subsets: ["latin"], axes: ["opsz"], variable: "--font-brand" });

export const metadata: Metadata = {
  title: "HelloPorch | One-button video calling for dementia & Parkinson’s",
  description:
    "HelloPorch makes one-button video calling simpler for people with Parkinson’s, dementia, and limited dexterity, with a tablet and large physical photo buttons.",
};

export const viewport: Viewport = {
  themeColor: "#f7f0de",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${serif.variable} ${sans.variable} ${brand.variable}`}>
      <body>{children}</body>
    </html>
  );
}
