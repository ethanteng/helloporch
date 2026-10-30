import { updateJSON, type FamilyStore } from "../family/store.ts";
import { assertAdmin, type AdminSession } from "./session.ts";

/** What was done on the admin page, newest first. `detail` names what it was done to, such as an invitation's label; it
 * never holds a link, password or anything a family said. */
export type ActivityEntry = { at: number; action: string; detail?: string };
export const activityKey = "admin-log";
export const keptActivity = 500;

export async function logActivity(store: FamilyStore, at: number, action: string, detail?: string) {
  await updateJSON<ActivityEntry[]>(store, activityKey, [], log => [{ at, action, ...(detail ? { detail } : {}) }, ...log].slice(0, keptActivity));
}
export async function readActivity(session: AdminSession, store: FamilyStore): Promise<ActivityEntry[]> {
  assertAdmin(session);
  return JSON.parse(await store.get(activityKey) ?? "[]");
}
