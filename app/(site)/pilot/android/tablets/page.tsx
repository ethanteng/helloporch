import type { Metadata } from "next";
import { pageMetadata } from "@/lib/site-metadata";
import { Guide, UI, type GuidePart } from "../../_guide/parts";

export const metadata: Metadata = pageMetadata({
  path: "/pilot/android/tablets",
  title: "Android tablets that work with Porch | HelloPorch",
  description:
    "Porch needs an Android tablet that can charge and use the big-button phone at the same time. Which tablets work, and how to check one.",
  shareTitle: "Choosing an Android tablet for Porch",
  image: { url: "/og/pilot.jpg", alt: "HelloPorch: Join the Porch pilot. Beside the Porch prototype, a tablet and a big-button phone." },
});

// The tablets come from LAVA's tested lists, which show which tablets charge while they use a USB device, as Porch
// needs (https://lavalink.com/lavaaccessory/charge-plus-compatibility/ and
// https://lavalink.com/lavasimulcharge/esync-usync-compatibility/), checked in November 2026. Only tablets that run
// Android 15 or later and worked without trouble are listed. A tablet that can't do both has no USB Power Delivery or
// won't use it to swap roles with the hub; the MUISOO KB10 has none.
const parts: GuidePart[] = [
  {
    id: "why",
    title: "Why it matters",
    body: (
      <>
        <p>
          The big-button phone and the tablet’s charger both plug into the tablet through a small hub. Many Android
          tablets stop listening to the phone as soon as the charger is plugged in.
        </p>
        <p>Porch stays plugged in all day, so the tablet has to do both at once.</p>
      </>
    ),
  },
  {
    id: "work",
    title: "Tablets that work",
    body: (
      <ul>
        <li>
          <strong>Lenovo Idea Tab</strong>, lower cost
        </li>
        <li>
          <strong>Samsung Galaxy Tab S9+</strong>, higher cost
        </li>
        <li>
          <strong>Samsung Galaxy Tab S10+</strong>, higher cost
        </li>
        <li>
          <strong>Samsung Galaxy Tab S10 Ultra</strong>, higher cost
        </li>
      </ul>
    ),
  },
  {
    id: "avoid",
    title: "Tablets to avoid",
    body: (
      <ul>
        <li>
          <strong>Amazon Fire tablets.</strong> Porch can’t be installed on them.
        </li>
        <li>
          <strong>Samsung Galaxy Tab A7, A7 Lite and A8.</strong>
        </li>
        <li>
          <strong>Low-cost tablets from brands you don’t recognize.</strong> Most can’t do both.
        </li>
      </ul>
    ),
  },
  {
    id: "check",
    title: "Checking another tablet",
    body: (
      <>
        <p>
          Look for <strong>“USB PD”</strong> or <strong>“Power Delivery”</strong> in the tablet’s charging details, and
          for Android 15 or later. Without Power Delivery, it won’t work.
        </p>
        <p>To be sure, try this with the hub, the tablet’s charger and any USB mouse:</p>
        <ol>
          <li>Plug the hub into the tablet, and the mouse into the hub.</li>
          <li>Plug the charger into the hub.</li>
          <li>If the mouse still works and the tablet is charging, the tablet can do both.</li>
        </ol>
      </>
    ),
  },
  {
    id: "already",
    title: "If Porch is already set up",
    body: (
      <p>
        If Porch keeps showing <UI>Waiting for the phone…</UI> while the charger is plugged in, unplug the charger from
        the hub. If the phone then connects, the tablet can’t do both, and you’ll need a different one. Let me know, and
        I’ll help.
      </p>
    ),
  },
];

// A page to share with families choosing a tablet, linked from the pilot page and the Android guide. Unlike the guides,
// it's public: it helps before anyone joins.
export default function AndroidTablets() {
  return (
    <Guide
      eyebrow="Porch pilot"
      title={
        <>
          Choosing an <em>Android tablet</em> for Porch
        </>
      }
      lede={
        <p>Porch needs an Android tablet that can charge and use the big-button phone at the same time. Not every tablet can.</p>
      }
      aside={<>Any iPad with iPadOS 15 or later works with Porch.</>}
      contentsTitle="On this page"
      parts={parts}
    />
  );
}
