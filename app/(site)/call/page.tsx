import type { Metadata } from "next";
import CallPrototype from "./CallPrototype";

export const metadata: Metadata = {
  title: "Join a call — Porch",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

export default function CallPage() {
  return <CallPrototype />;
}
