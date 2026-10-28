// The equipment on the pilot page. Families provide all of it; costs are what each part cost on
// Amazon in October 2026.
export type Part = {
  id: string;
  name: string;
  cost?: number;
  description: string;
  href?: string;
  photo: { src: string; alt: string };
};

export const parts: Part[] = [
  {
    id: "ipad",
    name: "iPad",
    description:
      "One with an M-series chip and iPadOS 16 or later: an iPad Pro from 2021 or later, or an iPad Air from 2022 or later. A spare one is perfect. It stays plugged in and on your Wi-Fi.",
    photo: {
      src: "/pilot/ipad.jpg",
      alt: "An iPad in its stand, showing Porch’s clock and a Call someone button.",
    },
  },
  {
    id: "stand",
    name: "Sturdy iPad stand",
    cost: 30,
    description:
      "A weighted base and a folding aluminum arm hold the iPad steady at eye level, so it won’t tip when someone taps the screen. The clamp fits any iPad.",
    href: "https://www.amazon.com/dp/B0H3N2YPKJ",
    photo: {
      src: "/pilot/stand.jpg",
      alt: "The back of the stand: a spring clamp holding the iPad, a black folding arm and a round base.",
    },
  },
  {
    id: "hub",
    name: "USB hub",
    cost: 19,
    description:
      "Plugs into the iPad’s USB-C port. Your iPad’s charger plugs into the hub, so the iPad stays charged with the phone plugged in too.",
    href: "https://www.amazon.com/dp/B0BQLLB61B",
    photo: {
      src: "/pilot/hub.jpg",
      alt: "A slim black Anker USB hub with a charging cable and a white USB cable plugged in.",
    },
  },
  {
    id: "phone",
    name: "Big-button phone",
    cost: 28,
    description:
      "A corded phone with a photo under each big button. Pressing someone’s photo calls them on Porch. The phone is only the keypad: you see and hear each other on the iPad.",
    href: "https://www.amazon.com/dp/B0FZ99J2QG",
    photo: {
      src: "/pilot/phone.jpg",
      alt: "A white big-button phone with a photo on each number key and large red * and # keys.",
    },
  },
  {
    id: "cell2jack",
    name: "Cell2Jack",
    cost: 37,
    description:
      "Made to connect home phones to a cell phone. Here it connects the big-button phone to the USB hub, and Porch reads the button presses through it.",
    href: "https://www.amazon.com/dp/B089984QRT",
    photo: {
      src: "/pilot/cell2jack.jpg",
      alt: "The Cell2Jack, a small white box with a blue light, a USB cable and a phone cord.",
    },
  },
];

// What everything but the iPad costs together.
export const equipmentCost = parts.reduce((sum, part) => sum + (part.cost ?? 0), 0);
