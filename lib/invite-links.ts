// Invitation links on Porch's website, https://helloporch.store/join#code=… for a family member and /setup#code=… for a
// new bedside. They open Porch as universal links, or show how to get it. The code stays after `#`, so it never reaches
// a server's logs. A web link names no server: it's for the one the app is built with (its `PorchServerURL`), and an
// invitation for any other server keeps the porch:// form.
export const porchWebOrigin = "https://helloporch.store";
export const porchServerOrigin = "https://porch-calling-prototype.vercel.app";
export const porchAppID = "7U9T57JPF7.com.ethanteng.helloporch";
export const porchAndroidPackage = "com.ethanteng.helloporch";
/** The SHA-256 fingerprint of Play App Signing's certificate, as Play Console shows it, and no other. A debug or upload
 * key isn't kept as safely, and any build it signs could open invitation links and read their codes. Approve the links
 * for a debug build on its test device instead (Open by default, or `adb shell pm set-app-links-user-selection`).
 * Until it's added, no build can open invitation links. */
export const androidCertificates: string[] = [];
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
