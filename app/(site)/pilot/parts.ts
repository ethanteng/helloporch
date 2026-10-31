// The equipment on the pilot page. Families provide all of it and can shop around for everything
// but the Cell2Jack; costs are what the parts I use cost on Amazon in October 2026.
export type Part = {
  id: string;
  name: string;
  // Dollars, or "own" for something the family already has. Left out when there's no part to price.
  cost?: number | "own";
  // What any replacement has to do. Exact parts can't be swapped for another brand.
  rule: { label: string; text: string; exact?: boolean };
  description: string;
  href?: string;
  photo: { src: string; alt: string };
};

// Which iPad each way of calling needs, as the pilot form asks it. The touchscreen and number pads need
// only iPadOS 15, which every iPad from 2015 on can run, but the Cell2Jack driver needs an M-series chip.
export const ipadNeeds = {
  touch: {
    question: "Do you have an iPad from 2015 or later?",
    label: "For the touchscreen or a number pad",
    text: "Almost any iPad works. It just needs to be from 2015 or later.",
  },
  phone: {
    question: "Do you have an iPad with an M1 chip or newer?",
    label: "For a big-button phone",
    text: "The phone needs a newer iPad: an iPad Pro from 2021 on, or an iPad Air from 2022 on.",
  },
};

const stand: Part = {
  id: "stand",
  name: "Sturdy iPad stand",
  cost: 30,
  rule: {
    label: "Any brand",
    text: "Look for one that holds the iPad steady at eye level and won’t tip when someone taps the screen.",
  },
  description: "Mine has a weighted base, a folding aluminum arm and a clamp that fits any iPad.",
  href: "https://www.amazon.com/dp/B0H3N2YPKJ",
  photo: {
    src: "/pilot/stand.jpg",
    alt: "The back of the stand: a spring clamp holding the iPad, a black folding arm and a round base.",
  },
};

const hub = {
  id: "hub",
  name: "USB hub",
  cost: 19,
  href: "https://www.amazon.com/dp/B0BQLLB61B",
  photo: {
    src: "/pilot/hub.jpg",
    alt: "A slim black Anker USB hub with a charging cable and a white USB cable plugged in.",
  },
};

// For a touchscreen or number pad Porch. None of these are required.
export const accessories: Part[] = [
  stand,
  {
    id: "number-pad",
    name: "Number pad",
    rule: {
      label: "Any brand",
      text: "Any USB or Bluetooth number pad works. A Bluetooth one leaves the iPad’s charging port free.",
    },
    description:
      "For anyone who finds buttons easier than the screen. You choose what each key does, such as calling someone or answering.",
    photo: {
      src: "/pilot/number-pad.jpg",
      alt: "A silver Macally number pad with black keys for 0 to 9, arrows and enter, on a wooden table.",
    },
  },
  {
    ...hub,
    rule: {
      label: "Only with a USB number pad",
      text: "Look for a USB-C hub with a charging port, so the iPad charges while the number pad is plugged in.",
    },
    description: "It plugs into the iPad’s USB-C port, with the charger and the number pad plugged into it.",
  },
];

// For a big-button phone Porch.
export const phoneParts: Part[] = [
  {
    id: "ipad",
    name: "iPad",
    cost: "own",
    rule: {
      label: "M1 chip or later",
      text: "An iPad Pro from 2021 on, or an iPad Air from 2022 on, with iPadOS 16 or later.",
    },
    description: "A spare one is perfect. It stays plugged in, on your Wi-Fi and open to Porch.",
    photo: {
      src: "/pilot/ipad.jpg",
      alt: "An iPad in its stand, showing Porch’s clock and a Call someone button.",
    },
  },
  stand,
  {
    ...hub,
    rule: {
      label: "Any brand",
      text: "Look for a USB-C hub with a charging port for the iPad’s charger and a USB port for the Cell2Jack.",
    },
    description: "It plugs into the iPad’s USB-C port, so the iPad stays charged with the phone plugged in too.",
  },
  {
    id: "phone",
    name: "Big-button phone",
    cost: 28,
    rule: {
      label: "Any brand",
      text: "Look for a corded home phone with big number keys. Room for a photo on each key makes it easiest.",
    },
    description:
      "Mine has a photo under each big button, and pressing someone’s photo calls them on Porch. The phone is only the keypad: you see and hear each other on the iPad.",
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
    rule: {
      label: "Must be a Cell2Jack",
      text: "Porch’s driver is built for it, so other adapters won’t work.",
      exact: true,
    },
    description:
      "Made to connect home phones to a cell phone. Here it connects the big-button phone to the USB hub, and Porch reads the button presses through it.",
    href: "https://www.amazon.com/dp/B089984QRT",
    photo: {
      src: "/pilot/cell2jack.jpg",
      alt: "The Cell2Jack, a small white box with a blue light, a USB cable and a phone cord.",
    },
  },
];

// What the phone parts I use, other than the iPad, cost together.
export const phoneCost = phoneParts.reduce((sum, part) => sum + (typeof part.cost === "number" ? part.cost : 0), 0);

// Families can shop around for any part that isn't exact, so its cost is only an estimate.
export function priceLabel(part: Part) {
  if (part.cost === undefined) return null;
  if (part.cost === "own") return "Your own";
  return part.rule.exact ? `$${part.cost}` : `About $${part.cost}`;
}
