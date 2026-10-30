import { createHash, randomBytes } from "node:crypto";
import { requireValue } from "./household.ts";
import { holdersKey } from "./numbers.ts";
import { updateJSON, type FamilyStore } from "./store.ts";

/** A one-use link that sets up a new bedside iPad and its household (`enrollBedside`). Only a hash of its code is kept.
 * `invitationID`: the admin page's invitation it was made for. `cancelled`: that invitation was cancelled.
 * `claimedBy`, `claimHash` and `claimedAt`: the device that used it and when; it may retry after a lost response. */
export type Activation = { expiresAt: number; invitationID?: string; cancelled?: boolean; claimedBy?: string; claimHash?: string; claimedAt?: number };
export const activationKey = (code: string) => `activation:${createHash("sha256").update(code).digest("hex")}`;

export async function createActivation(store: FamilyStore, now: number, seconds: number, invitationID?: string) {
  const code = randomBytes(32).toString("hex"), expiresAt = now + seconds;
  const activation: Activation = { expiresAt, ...(invitationID ? { invitationID } : {}) };
  requireValue(await store.create(activationKey(code), JSON.stringify(activation), seconds), "Couldn't create an activation. Try again.", 409);
  return { code, key: activationKey(code), expiresAt };
}

/** An invitation made on the admin page, newest first. `label` is who it's for, such as "Lee family". `activation` is the
 * key of its link's record, never the link. `householdID` and `setUpAt` are filled in when the link is used. */
export type BedsideInvitation = { id: string; label: string; createdAt: number; expiresAt: number; activation: string; householdID?: string; setUpAt?: number; cancelledAt?: number };
export const invitationsKey = "admin-invitations";
/** How many used, cancelled or expired invitations the list keeps, newest first. Waiting ones all stay, so each can still
 * be cancelled until it expires. */
export const keptInvitations = 200;

export async function markInvitationSetUp(store: FamilyStore, invitationID: string, householdID: string, now: number) {
  await updateJSON<BedsideInvitation[]>(store, invitationsKey, [], invitations => {
    const invitation = invitations.find(i => i.id === invitationID);
    if (!invitation || invitation.householdID) return undefined;
    invitation.householdID = householdID; invitation.setUpAt = now;
    return invitations;
  });
}

/** Every household, so the admin page can list them: the store can't search its keys. Households that got a Porch number
 * before this list existed, such as ours, are on the list of number holders. */
export const householdsKey = "households";
export async function rememberHousehold(store: FamilyStore, householdID: string) {
  await updateJSON<string[]>(store, householdsKey, [], ids => ids.includes(householdID) ? undefined : [...ids, householdID]);
}
export async function householdIDs(store: FamilyStore): Promise<string[]> {
  const [listed, holders] = await Promise.all([store.get(householdsKey), store.get(holdersKey)]);
  return [...new Set<string>([...(listed ? JSON.parse(listed) : []), ...(holders ? JSON.parse(holders) : [])])];
}
