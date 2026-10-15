import type { Metadata, Viewport } from "next";
import { DM_Sans, Newsreader } from "next/font/google";
import "./globals.css";

const serif = Newsreader({ subsets: ["latin"], style: ["normal", "italic"], axes: ["opsz"], variable: "--font-serif" });
const sans = DM_Sans({ subsets: ["latin"], axes: ["opsz"], variable: "--font-sans" });

export const metadata: Metadata = {
  title: "Porch — Press a face. See a face.",
  description:
    "Porch is a tablet and a large-button keypad for individuals with dementia or limited dexterity. Each button is someone they love. One press starts a video call.",
};

export const viewport: Viewport = {
  themeColor: "#f7f0de",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${serif.variable} ${sans.variable}`}>
      <body>{children}</body>
    </html>
  );
}
