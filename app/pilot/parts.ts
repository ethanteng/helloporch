// The equipment on the pilot page. Prices are what each part cost on Amazon in October 2026.
export type Part = {
  id: string;
  name: string;
  price: string;
  description: string;
  href?: string;
  photo: { src: string; alt: string };
};

// Everyone needs these.
export const shared: Part[] = [
  {
    id: "ipad",
    name: "Any iPad",
    price: "Yours",
    description:
      "A spare iPad is perfect. It stays plugged in and on your home Wi-Fi. Which models work depends on the keypad you choose.",
    photo: {
      src: "/pilot/ipad.jpg",
      alt: "An iPad in its stand, showing Porch’s clock and a Call someone button.",
    },
  },
  {
    id: "stand",
    name: "Sturdy iPad stand",
    price: "$30",
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
    price: "$19",
    description:
      "Plugs into the iPad’s USB-C port. Your iPad’s charger plugs into the hub, so the iPad stays charged with the keypad plugged in too.",
    href: "https://www.amazon.com/dp/B0BQLLB61B",
    photo: {
      src: "/pilot/hub.jpg",
      alt: "A slim black Anker USB hub with a charging cable and a white USB cable plugged in.",
    },
  },
];

// The keypad for the set-it-up-yourself option.
export const numberPad: Part[] = [
  {
    id: "keypad",
    name: "Number pad",
    price: "$30",
    description:
      "A wired keypad that plugs into the hub’s USB-C port. You choose what each key does: call a particular person, answer, hang up, or turn the camera on and off.",
    href: "https://www.amazon.com/dp/B0BXT6Q3BZ",
    photo: {
      src: "/pilot/keypad.jpg",
      alt: "A gray Macally number pad with black keys: arrows, 0 to 9, math keys and a tall enter key.",
    },
  },
];

// The keypad for the option I set up: the phone, and the adapter that connects it.
export const phoneKit: Part[] = [
  {
    id: "phone",
    name: "Big-button phone",
    price: "$28",
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
    price: "$37",
    description:
      "Made to connect home phones to a cell phone. Here it connects the big-button phone to the USB hub, and Porch reads the button presses through it.",
    href: "https://www.amazon.com/dp/B089984QRT",
    photo: {
      src: "/pilot/cell2jack.jpg",
      alt: "The Cell2Jack, a small white box with a blue light, a USB cable and a phone cord.",
    },
  },
];
