// The links pilot families use to get Porch, from the website's Vercel project. Until one is set, the guides say I'll
// send it.
export const testFlight = process.env.NEXT_PUBLIC_TESTFLIGHT_URL;
export const playTesting = process.env.NEXT_PUBLIC_PLAY_TESTING_URL;
// Apple's TestFlight app on the App Store.
export const testFlightApp = "https://apps.apple.com/app/testflight/id899247664";

// QR codes made for these exact links with scripts/guide-videos/qr.swift. If a link changes, the guides show it
// without a code until its code is made again.
const qrCodes: Record<string, string> = {
  "https://testflight.apple.com/join/yM4JpBHC": "/pilot/links/testflight.svg",
  "https://play.google.com/apps/internaltest/4701338934153341848": "/pilot/links/google-play.svg",
};

export function qrFor(href: string | undefined) {
  return href ? qrCodes[href] : undefined;
}
