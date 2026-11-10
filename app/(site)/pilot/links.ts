// The links pilot families use to get Porch: its public TestFlight link and its Google Play internal test. If one
// changes, change it here too, and make its QR code again.
export const testFlight = "https://testflight.apple.com/join/yM4JpBHC";
export const playTesting = "https://play.google.com/apps/internaltest/4701338934153341848";
// Apple's TestFlight app on the App Store.
export const testFlightApp = "https://apps.apple.com/app/testflight/id899247664";

// QR codes made for these exact links with scripts/guide-videos/qr.swift. If a link changes, the guides show it
// without a code until its code is made again.
const qrCodes: Record<string, string> = {
  [testFlightApp]: "/pilot/links/testflight-app.svg",
  [testFlight]: "/pilot/links/testflight.svg",
  [playTesting]: "/pilot/links/google-play.svg",
};

export function qrFor(href: string | undefined) {
  return href ? qrCodes[href] : undefined;
}
