"use server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { refresh } from "next/cache";
import { signIn, signOut, signOutEverywhere } from "../../../lib/admin/auth.ts";
import { cancelInvitation, createInvitation, sendAgain } from "../../../lib/admin/invitations.ts";
import { adminRequest, clientAddress, cookieOptions, requireAdmin, sessionCookie } from "../../../lib/admin/request.ts";
import { AdminError } from "../../../lib/admin/session.ts";

// Server Actions are reachable by anyone who can POST, so each one checks the host and the session itself.
export type SignInState = { error?: string };
export type LinkState = { error?: string; created?: { id: string; label: string; link: string; message: string; expiresAt: number } };

async function failed<T>(work: () => Promise<T>): Promise<T | { error: string }> {
  try { return await work(); } catch (error) { if (error instanceof AdminError) return { error: error.message }; throw error; }
}

export async function signInAction(_: SignInState, form: FormData): Promise<SignInState> {
  const { store, now, settings } = await adminRequest();
  if (!settings) return { error: "The admin password isn't set up yet." };
  const result = await failed(async () => signIn(store, settings, { password: form.get("password"), address: await clientAddress() }, now));
  if ("error" in result) return result;
  (await cookies()).set(sessionCookie, result.token, { ...cookieOptions, expires: new Date(result.expiresAt * 1000) });
  redirect("/");
}
export async function signOutAction() {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  await signOut(session, store, now);
  (await cookies()).set(sessionCookie, "", { ...cookieOptions, maxAge: 0 });
  redirect("/sign-in");
}
export async function signOutEverywhereAction() {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  await signOutEverywhere(session, store, now);
  (await cookies()).set(sessionCookie, "", { ...cookieOptions, maxAge: 0 });
  redirect("/sign-in");
}
export async function createInvitationAction(_: LinkState, form: FormData): Promise<LinkState> {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  const result = await failed(() => createInvitation(session, store, now, form.get("label")));
  if ("error" in result) return result;
  refresh();
  return { created: result };
}
export async function sendAgainAction(_: LinkState, form: FormData): Promise<LinkState> {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  const result = await failed(() => sendAgain(session, store, now, form.get("id")));
  if ("error" in result) return result;
  refresh();
  return { created: result };
}
export async function cancelInvitationAction(_: LinkState, form: FormData): Promise<LinkState> {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  const result = await failed(() => cancelInvitation(session, store, now, form.get("id")));
  if (result && "error" in result) return result;
  refresh();
  return {};
}
