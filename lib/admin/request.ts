import "server-only";
import { cookies, headers } from "next/headers";
import { notFound, redirect } from "next/navigation";
import { cache } from "react";
import { familyStore } from "../family/store.ts";
import { currentSession } from "./auth.ts";
import { validPasswordHash } from "./password.ts";
import { adminEnabled, isAdminHost } from "./routing.ts";

/** Secure and HttpOnly, for this host only, and never sent from another site. */
export const sessionCookie = "__Host-porch-admin";
export const cookieOptions = { httpOnly: true, secure: true, sameSite: "strict", path: "/" } as const;

/** The store and settings for an admin request, or 404 when this isn't the admin host or the admin page is off. */
export async function adminRequest() {
  // Read first, so these pages always render per request, whatever the build's settings were.
  const host = (await headers()).get("host");
  if (!adminEnabled() || !isAdminHost(host)) notFound();
  const passwordHash = process.env.PORCH_ADMIN_PASSWORD_HASH;
  return { store: familyStore(), now: Math.floor(Date.now() / 1000), settings: validPasswordHash(passwordHash) ? { passwordHash } : undefined };
}

export const currentAdmin = cache(async () => {
  const { store, now, settings } = await adminRequest();
  return settings ? currentSession(store, settings, (await cookies()).get(sessionCookie)?.value, now) : undefined;
});
/** Every admin page and action starts here. */
export async function requireAdmin() {
  const session = await currentAdmin();
  if (!session) redirect("/sign-in");
  return session;
}
/** Vercel sets these from the connection, so a client can't choose its own. */
export async function clientAddress() {
  const list = await headers();
  return list.get("x-real-ip") ?? list.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
}
