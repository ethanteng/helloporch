// What the pilot's hardware roughly costs, with the Amazon listings I use. The pilot page and the getting-started
// guides all list them, so the prices and links live here once.
export const shopping = {
  tablet: { price: "About $150 to $350 new" },
  phone: { price: "About $28", href: "https://www.amazon.com/dp/B0FZ99J2QG" },
  cell2jack: { price: "About $37", href: "https://www.amazon.com/dp/B089984QRT" },
  adapter: { price: "I’ll provide it" },
  hub: { price: "About $19", href: "https://www.amazon.com/dp/B0BQLLB61B" },
  // For an iPad with a Lightning port, in place of the USB-C hub.
  lightningHub: { price: "About $8", href: "https://www.amazon.com/dp/B0F8NHNBG8" },
  stand: { price: "About $30", href: "https://www.amazon.com/dp/B0H3N2YPKJ" },
} as const;
