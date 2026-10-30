import { createHash, randomBytes } from "node:crypto";
import { updateJSON, type FamilyStore } from "../family/store.ts";
import { logActivity } from "./activity.ts";
import { checkPassword, maximumPasswordLength } from "./password.ts";
import { AdminError, AdminSession, assertAdmin } from "./session.ts";

export type AdminSettings = { passwordHash: string };
export const sessionSeconds = 12 * 3600;
/** Wrong passwords pause sign-in from that address, and from everywhere after many more. Neither counts right ones. */
export const failureLimits = { address: { attempts: 10, seconds: 15 * 60 }, everywhere: { attempts: 100, seconds: 3600 } };

const hash = (value: string) => createHash("sha256").update(value).digest("hex");
/** Sessions are kept by a hash of the cookie's value, so the store never holds one that works. */
const sessionKey = (token: string) => `admin-session:${hash(token)}`;
/** Raised by **Sign out everywhere**; a session from before it no longer works. */
const generationKey = "admin-session-generation";
type SessionRecord = { createdAt: number; expiresAt: number; generation: number; password: string } | { ended: true };
type Failures = { count: number; until: number };
const failureCounts = (address: string) => [{ key: `admin-failures:${hash(address)}`, limit: failureLimits.address, from: "From one address" },
  { key: "admin-failures:everywhere", limit: failureLimits.everywhere, from: "From everywhere" }];
/** Changing the password hash signs out every session, since each was made with the old one. */
const passwordStamp = (settings: AdminSettings) => hash(settings.passwordHash).slice(0, 16);
const generation = async (store: FamilyStore) => Number(await store.get(generationKey) ?? 0);
/** Uncounts tries `signIn` counted, for a right password or one it never checked. A count that started over is left alone. */
async function giveBack(store: FamilyStore, counted: { key: string; until: number; seconds: number }[]) {
  for (const { key, until, seconds } of counted)
    await updateJSON<Failures | null>(store, key, null, failures => failures?.until === until && failures.count > 0 ? { ...failures, count: failures.count - 1 } : undefined, seconds);
}

export async function signIn(store: FamilyStore, settings: AdminSettings, attempt: { password: unknown; address: string }, now: number) {
  const { password } = attempt;
  if (typeof password !== "string" || !password || password.length > maximumPasswordLength) throw new AdminError("Enter the admin password.");
  // Each try is counted before its password is checked, so tries made at the same moment can't all get in under the
  // limit; a right password gives its try back. A paused address learns nothing about the password, right or wrong.
  const counted: (Failures & { key: string; seconds: number; attempts: number; from: string })[] = [];
  for (const { key, limit, from } of failureCounts(attempt.address)) {
    let paused = false;
    const failures = await updateJSON<Failures | null>(store, key, null, failures => {
      paused = !!failures && failures.until > now && failures.count >= limit.attempts;
      if (paused) return undefined;
      return failures && failures.until > now ? { ...failures, count: failures.count + 1 } : { count: 1, until: now + limit.seconds };
    }, limit.seconds);
    if (paused) {
      await giveBack(store, counted);
      throw new AdminError("Sign-in is paused after too many wrong passwords. Try again later.", 429);
    }
    counted.push({ ...failures!, key, seconds: limit.seconds, attempts: limit.attempts, from });
  }
  if (!await checkPassword(password, settings.passwordHash)) {
    for (const { count, attempts, from } of counted) if (count === attempts) await logActivity(store, now, "Sign-in paused after too many wrong passwords", from);
    throw new AdminError("That password isn't right.", 401);
  }
  await giveBack(store, counted);
  const token = randomBytes(32).toString("base64url"), expiresAt = now + sessionSeconds;
  const record: SessionRecord = { createdAt: now, expiresAt, generation: await generation(store), password: passwordStamp(settings) };
  if (!await store.create(sessionKey(token), JSON.stringify(record), sessionSeconds)) throw new AdminError("Couldn't sign in. Try again.", 409);
  await logActivity(store, now, "Signed in");
  return { token, expiresAt };
}

/** The session a cookie belongs to, while it lasts and hasn't been signed out. */
export async function currentSession(store: FamilyStore, settings: AdminSettings, token: string | undefined, now: number) {
  if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) return undefined;
  const key = sessionKey(token), raw = await store.get(key);
  if (!raw) return undefined;
  const record: SessionRecord = JSON.parse(raw);
  if ("ended" in record || record.expiresAt <= now || record.password !== passwordStamp(settings) || record.generation !== await generation(store)) return undefined;
  return AdminSession.issue(key, raw, record.expiresAt);
}

export async function signOut(session: AdminSession, store: FamilyStore, now: number) {
  assertAdmin(session);
  const ended: SessionRecord = { ended: true };
  await store.compareAndSet(session.key, session.raw, JSON.stringify(ended), 60);
  await logActivity(store, now, "Signed out");
}
export async function signOutEverywhere(session: AdminSession, store: FamilyStore, now: number) {
  assertAdmin(session);
  await updateJSON<number>(store, generationKey, 0, value => value + 1);
  await logActivity(store, now, "Signed out everywhere");
}
