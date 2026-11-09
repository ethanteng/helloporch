// Invitation links on Porch's website, https://helloporch.store/join#code=… for a family member and /setup#code=… for a
// new bedside. They open Porch as universal links, or show how to get it. The code stays after `#`, so it never reaches
// a server's logs. A web link names no server: it's for the one the app is built with (its `PorchServerURL`), and an
// invitation for any other server keeps the porch:// form.
export const porchWebOrigin = "https://helloporch.store";
export const porchServerOrigin = "https://porch-calling-prototype.vercel.app";
export const porchAppID = "7U9T57JPF7.com.ethanteng.helloporch";
export const porchAndroidPackage = "com.ethanteng.helloporch";
/** SHA-256 fingerprints of the certificates Android builds are signed with, as `keytool -list -v` prints them, so each kind
 * of build opens invitation links (android/README.md, "Release to Google Play"). */
export const androidCertificates: string[] = [
  // Play App Signing's key, which signs Porch as Google Play installs it.
  "22:F5:00:7A:89:81:04:70:F1:5D:99:CC:FA:A1:A2:30:50:C0:AB:CA:B9:C7:74:D8:CF:D7:C0:41:E6:EC:21:00",
  // The upload key, for a release build installed without Google Play.
  "4A:20:C5:AA:B6:52:30:0F:1B:B4:0D:A1:C5:78:22:63:97:B5:1F:85:FD:6F:FD:6C:32:E1:C6:1F:6E:90:6F:F8",
  // The debug key of the Mac that builds test versions.
  "1A:46:5E:5A:F8:61:AA:A4:33:17:77:36:E3:CA:DE:BA:D1:14:B3:60:C1:C6:BA:07:26:FE:29:9C:21:DF:23:18",
];
export type InviteKind = "family" | "bedside";
export const invitePaths: Record<InviteKind, string> = { family: "/join", bedside: "/setup" };
// The app's own scheme: porch://pair for a family member, porch://activate for a bedside.
const appHosts: Record<InviteKind, string> = { family: "pair", bedside: "activate" };
const codePattern = /^[a-f0-9]{64}$/;

export function inviteCode(value: unknown): string | undefined {
  return typeof value === "string" && codePattern.test(value) ? value : undefined;
}

/** The link to share: a web link for Porch's own server, porch:// for any other. */
export function inviteLink(kind: InviteKind, code: string, server = porchServerOrigin): string {
  return new URL(server).origin === porchServerOrigin ? `${porchWebOrigin}${invitePaths[kind]}#code=${code}` : appLink(kind, code, server);
}

/** The same invitation in the app's own form, which every version of Porch opens. */
export function appLink(kind: InviteKind, code: string, server = porchServerOrigin): string {
  return `porch://${appHosts[kind]}?${new URLSearchParams({ server: new URL(server).origin, code })}`;
}

/** The code in a web invitation's `#`, such as "#code=…". */
export function codeFromHash(hash: string): string | undefined {
  return inviteCode(new URLSearchParams(hash.replace(/^#/, "")).get("code"));
}

/** Phone or tablet, for an invitation page. Undefined when the browser isn't Android. Chrome's reduced user agent
 * says "Mobile" on tablets too, so pass `navigator.userAgentData?.mobile`, which still tells them apart. */
export function androidDevice(userAgent: string, mobileHint?: boolean): "phone" | "tablet" | undefined {
  if (!/Android/i.test(userAgent)) return;
  return (mobileHint ?? /Mobile/i.test(userAgent)) ? "phone" : "tablet";
}

/** Android fetches this from helloporch.store when Porch is installed, to let invitation links open it. */
export function assetLinks() {
  return androidCertificates.length ? [{ relation: ["delegate_permission/common.handle_all_urls"],
    target: { namespace: "android_app", package_name: porchAndroidPackage, sha256_cert_fingerprints: androidCertificates } }] : [];
}

/** Apple fetches this from helloporch.store to let invitation links open Porch. */
export function appSiteAssociation() {
  return { applinks: { details: [{ appIDs: [porchAppID], components: [
    { "/": invitePaths.family, comment: "A family member's invitation" },
    { "/": invitePaths.bedside, comment: "Setting up a new bedside iPad" },
  ] }] } };
}
