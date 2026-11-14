import type { Metadata } from "next";
import { pageMetadata } from "@/lib/site-metadata";
import { Guide, Picks, Tip, UI, Warn, type GuidePart } from "../../_guide/parts";

export const metadata: Metadata = pageMetadata({
  path: "/pilot/android/tablets",
  title: "Android tablets that work with Porch | HelloPorch",
  description:
    "Porch needs an Android tablet that can charge and use the big-button phone at the same time. Why it matters, which tablets work, and a one-minute check for any other tablet.",
  shareTitle: "Choosing an Android tablet for Porch",
  image: { url: "/og/pilot.jpg", alt: "HelloPorch: Join the Porch pilot. Beside the Porch prototype, a tablet and a big-button phone." },
});

// Where the list comes from. LAVA makes adapters that charge a tablet while it uses USB devices, for tablets in shops
// and offices, and publishes the tablets it tested. Porch needs the same thing: the tablet charges through the hub while
// it reads the Cell2Jack. Only tablets that run Android 15 or later are listed, since Porch needs it. A tablet that can't
// charge while it uses USB has no USB Power Delivery, or won't swap roles with the hub (the MUISOO KB10, tested
// 2026-11-13, has no Power Delivery at all). Checked against LAVA's lists in November 2026.
const lavaChargePlus = "https://lavalink.com/lavaaccessory/charge-plus-compatibility/";
const lavaESync = "https://lavalink.com/lavasimulcharge/esync-usync-compatibility/";

type Tablet = { name: string; model: string; cost: "Lower cost" | "Higher cost"; note: string };

const BEST: Tablet[] = [
  {
    name: "Lenovo Idea Tab",
    model: "TB336ZU",
    cost: "Lower cost",
    note: "Works. The phone may take a couple of tries to connect the first time.",
  },
  {
    name: "Samsung Galaxy Tab S9+",
    model: "SM-X818U",
    cost: "Higher cost",
    note: "Works, with no problems found. The tested model is the one with cellular service.",
  },
  {
    name: "Samsung Galaxy Tab S10+",
    model: "SM-X820",
    cost: "Higher cost",
    note: "Works. Now and then you may need to unplug the hub and plug it back in.",
  },
  {
    name: "Samsung Galaxy Tab S10 Ultra",
    model: "SM-X920",
    cost: "Higher cost",
    note: "Works. Now and then you may need to unplug the hub and plug it back in.",
  },
];

const WITH_A_CATCH: Tablet[] = [
  {
    name: "Lenovo Tab (10.1-inch, 2024)",
    model: "TB311FU",
    cost: "Lower cost",
    note:
      "Lets go of the phone when its screen turns off. Porch keeps the screen on while the clock is showing, but after a power cut you may need to unplug the hub and plug it back in.",
  },
  {
    name: "Samsung Galaxy Tab A11+",
    model: "SM-X230",
    cost: "Lower cost",
    note: "Tested only with a different kind of adapter, so it’s less certain.",
  },
];

/** Tablets with their model number, rough cost and what to expect, one row each. */
function Tablets({ label, items }: { label: string; items: Tablet[] }) {
  return (
    <Picks
      label={label}
      items={items.map(({ name, model, cost, note }) => ({ name, detail: `Model ${model} · ${cost}`, note }))}
    />
  );
}

const parts: GuidePart[] = [
  {
    id: "why",
    title: "Why the tablet matters",
    body: (
      <>
        <p>
          Porch connects the big-button phone to the tablet through the tablet’s charging port. A small USB-C hub lets
          the phone’s adapter, the Cell2Jack, and the tablet’s charger share that one port.
        </p>
        <p>
          Many Android tablets can only do one of those jobs at a time. As soon as the charger is plugged in, they stop
          paying attention to the phone. Porch keeps showing <UI>Waiting for the phone…</UI> and the phone’s buttons do
          nothing.
        </p>
        <p>
          Porch stays plugged in at your loved one’s bedside all day, so the tablet has to do both at once. Whether it
          can depends on how the tablet is made. A different hub, cable or setting won’t change it.
        </p>
      </>
    ),
  },
  {
    id: "work",
    title: "Tablets known to work",
    body: (
      <>
        <p>
          LAVA, a company that makes charging adapters for tablets used in shops and offices, publishes which tablets
          it has tested charging while using a USB device. That’s what Porch needs. These are the ones that run Android
          15 or later, which Porch also needs. I haven’t tested each one with Porch myself yet.
        </p>
        <h3>Best choices</h3>
        <Tablets label="Best choices" items={BEST} />
        <h3>These work, with a catch</h3>
        <Tablets label="Tablets that work, with a catch" items={WITH_A_CATCH} />
        <Tip label="Before you buy">
          <p>
            Check the model number. It’s on the box, and on the tablet in <UI>Settings</UI>, then <UI>About tablet</UI>.
            Other versions of the same tablet usually behave the same, but only the model listed was tested.
          </p>
          <p>
            Buy from a store with easy returns, and do the <a href="#check">one-minute check</a> as soon as it arrives.
          </p>
        </Tip>
        <p>
          This list comes from LAVA’s tested tablets for its <a href={lavaChargePlus}>Charge-Plus</a> and{" "}
          <a href={lavaESync}>eSynC</a> adapters, checked in November 2026.
        </p>
      </>
    ),
  },
  {
    id: "avoid",
    title: "Tablets to avoid",
    body: (
      <ul>
        <li>
          <strong>Samsung Galaxy Tab A7 Lite and Galaxy Tab A8.</strong> LAVA found their connection to USB devices
          comes and goes while they charge.
        </li>
        <li>
          <strong>Samsung Galaxy Tab A7 (10.4-inch, 2020).</strong> It can’t charge and use a USB device at the same
          time.
        </li>
        <li>
          <strong>Amazon Fire tablets.</strong> They don’t have Google Play, so Porch can’t be installed.
        </li>
        <li>
          <strong>Budget tablets from brands you don’t recognize.</strong> Most can’t do both. The one I tested, a
          MUISOO KB10, can’t.
        </li>
        <li>
          <strong>Older tablets that can’t update to Android 15.</strong>
        </li>
      </ul>
    ),
  },
  {
    id: "look",
    title: "If a tablet isn’t listed",
    body: (
      <>
        <p>
          The box or the store listing can’t tell you for sure that a tablet will work, but it can rule one out. Look
          for:
        </p>
        <ul>
          <li>
            <strong>Android 15 or later.</strong>
          </li>
          <li>
            <strong>Google Play.</strong> Porch installs from Google Play.
          </li>
          <li>
            <strong>A USB-C port.</strong> It’s small and oval, and the plug fits either way up.
          </li>
          <li>
            <strong>“USB PD” or “Power Delivery”</strong> in the charging details. On Samsung tablets, “Super Fast
            Charging” means it has Power Delivery. This is the one that matters most: a tablet without it can’t
            charge and use the phone at once.
          </li>
        </ul>
        <p>
          Be wary of a listing that only says “5V 2A”, “10W” or “Type-C charging”. Fast charging on its own isn’t
          enough, because some tablets charge quickly without Power Delivery. USB speeds, such as “USB 3.2”, have
          nothing to do with it.
        </p>
        <p>Even a tablet with Power Delivery might not work, so do the one-minute check before you set it up.</p>
      </>
    ),
  },
  {
    id: "check",
    title: "Check a tablet in one minute",
    body: (
      <>
        <p>
          You’ll need the USB-C hub, a USB-C wall charger, such as the one that came with the tablet, and any wired USB
          mouse.
        </p>
        <ol>
          <li>Plug the hub into the tablet, and the mouse into the hub. Move the mouse: a pointer appears on the screen.</li>
          <li>Plug the charger into the hub’s charging port.</li>
          <li>
            Move the mouse again and look at the battery icon. If the pointer still moves and the tablet shows it’s
            charging, the tablet passes.
          </li>
          <li>Unplug the charger, wait a few seconds and plug it back in. The pointer should still move.</li>
        </ol>
        <Warn label="If the pointer stops">
          <p>
            The tablet can’t charge and use the phone at the same time. If you just bought it, return it.
          </p>
        </Warn>
      </>
    ),
  },
  {
    id: "already",
    title: "If Porch is already set up",
    body: (
      <>
        <p>
          If Porch keeps showing <UI>Waiting for the phone…</UI> while the charger is plugged into the hub, unplug the
          charger from the hub. If the phone then connects, the tablet can’t charge and use the phone at the same time.
        </p>
        <p>
          Porch can’t fix this in the app, and the tablet won’t last the day on its battery. A tablet from the list above
          is the reliable fix. Let me know if this happens to you, and we’ll work out what to do.
        </p>
        <p>
          This list will grow as families try more tablets. If yours works, or doesn’t, please tell me which one it is.
        </p>
      </>
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
        <p>
          Porch needs an Android tablet that can charge and use the big-button phone at the same time. Many tablets
          can’t, and the box rarely says. Here’s why it matters, which tablets work, and a one-minute check for any
          other tablet.
        </p>
      }
      aside={<>This page is about Android tablets. Any iPad with iPadOS 15 or later works with Porch.</>}
      contentsTitle="On this page"
      parts={parts}
    />
  );
}
