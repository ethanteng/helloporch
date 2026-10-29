// Invitation links on Porch's website, https://helloporch.store/join#code=… for a family member and /setup#code=… for a
// new bedside. They open Porch as universal links, or show how to get it. The code stays after `#`, so it never reaches
// a server's logs. A web link names no server: it's for the one the app is built with (its `PorchServerURL`), and an
// invitation for any other server keeps the porch:// form.
export const porchWebOrigin = "https://helloporch.store";
export const porchServerOrigin = "https://porch-calling-prototype.vercel.app";
export const porchAppID = "7U9T57JPF7.com.ethanteng.helloporch";
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

/** Apple fetches this from helloporch.store to let invitation links open Porch. */
export function appSiteAssociation() {
  return { applinks: { details: [{ appIDs: [porchAppID], components: [
    { "/": invitePaths.family, comment: "A family member's invitation" },
    { "/": invitePaths.bedside, comment: "Setting up a new bedside iPad" },
  ] }] } };
}
