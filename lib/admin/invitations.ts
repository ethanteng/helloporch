import { randomUUID } from "node:crypto";
import { createActivation, invitationsKey, keptInvitations, markInvitationSetUp, type Activation, type BedsideInvitation } from "../family/activations.ts";
import { updateJSON, type FamilyStore } from "../family/store.ts";
import { inviteLink } from "../invite-links.ts";
import { logActivity } from "./activity.ts";
import { AdminError, assertAdmin, type AdminSession } from "./session.ts";

/** How long a family has to set up their Porch from the link. */
export const invitationSeconds = 14 * 86400;
/** A link used this recently may still be setting up its Porch, so it can't be cancelled yet. */
export const settingUpSeconds = 10 * 60;
export type InvitationState = "waiting" | "set up" | "expired" | "cancelled";
export type InvitationRow = { id: string; label: string; state: InvitationState; createdAt: number; expiresAt: number; householdID?: string; setUpAt?: number };

export const invitationMessage = (link: string) => `Here's your private link to set up Porch. Open it on the iPad that will stay with your loved one: ${link}`;
function label(value: unknown) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text || text.length > 80 || /[\p{Cc}]/u.test(text)) throw new AdminError("Enter who it's for, such as “Lee family”, in 80 characters or fewer.");
  return text;
}
function state(invitation: BedsideInvitation, now: number): InvitationState {
  return invitation.householdID ? "set up" : invitation.cancelledAt ? "cancelled" : invitation.expiresAt <= now ? "expired" : "waiting";
}
async function invitations(store: FamilyStore): Promise<BedsideInvitation[]> { return JSON.parse(await store.get(invitationsKey) ?? "[]"); }

/** A new family's setup link. It's shown this once: Porch keeps only a hash of its code. */
export async function createInvitation(session: AdminSession, store: FamilyStore, now: number, labelInput: unknown) {
  assertAdmin(session);
  const name = label(labelInput), id = randomUUID();
  const { code, key, expiresAt } = await createActivation(store, now, invitationSeconds, id);
  await updateJSON<BedsideInvitation[]>(store, invitationsKey, [], list => {
    let finished = 0;
    return [{ id, label: name, createdAt: now, expiresAt, activation: key }, ...list].filter(i => state(i, now) === "waiting" || ++finished <= keptInvitations);
  });
  await logActivity(store, now, "Invited a new family", name);
  const link = inviteLink("bedside", code);
  return { id, label: name, expiresAt, link, message: invitationMessage(link) };
}

export async function listInvitations(session: AdminSession, store: FamilyStore, now: number): Promise<InvitationRow[]> {
  assertAdmin(session);
  return (await invitations(store)).map(i => ({ id: i.id, label: i.label, state: state(i, now), createdAt: i.createdAt, expiresAt: i.expiresAt,
    ...(i.householdID ? { householdID: i.householdID, setUpAt: i.setUpAt } : {}) }));
}

/** Stops a waiting link from working. One a family already used can't be cancelled; deleting their Porch is separate. A
 * setup that stopped partway, and hasn't been tried again for a while, can be: its link would otherwise wait out its 14 days. */
export async function cancelInvitation(session: AdminSession, store: FamilyStore, now: number, id: unknown) {
  assertAdmin(session);
  const invitation = (await invitations(store)).find(i => i.id === id);
  if (!invitation) throw new AdminError("That invitation wasn't found.", 404);
  if (state(invitation, now) !== "waiting") return;
  for (let attempt = 0; ; attempt++) {
    if (attempt === 12) throw new AdminError("Porch is busy. Try again.", 409);
    const raw = await store.get(invitation.activation);
    if (!raw) break;
    const activation: Activation = JSON.parse(raw);
    if (activation.claimedBy) {
      // A bedside's household is named for its device, so if it exists the setup finished and only its listing was lost.
      if (await store.get(`house:${activation.claimedBy}`)) { await markInvitationSetUp(store, invitation.id, activation.claimedBy, now); return; }
      if (now - (activation.claimedAt ?? 0) < settingUpSeconds) throw new AdminError("This link is setting up a Porch right now. If that stops, you can cancel it in a few minutes.", 409);
    }
    const cancelled: Activation = { ...activation, cancelled: true };
    if (await store.compareAndSet(invitation.activation, raw, JSON.stringify(cancelled), Math.max(60, activation.expiresAt - now))) break;
  }
  await updateJSON<BedsideInvitation[]>(store, invitationsKey, [], list => {
    const entry = list.find(i => i.id === id);
    if (!entry || entry.cancelledAt || entry.householdID) return undefined;
    entry.cancelledAt = now;
    return list;
  });
  await logActivity(store, now, "Cancelled an invitation", invitation.label);
}

/** A new link for the same family, after theirs expired or was cancelled. */
export async function sendAgain(session: AdminSession, store: FamilyStore, now: number, id: unknown) {
  assertAdmin(session);
  const invitation = (await invitations(store)).find(i => i.id === id);
  if (!invitation) throw new AdminError("That invitation wasn't found.", 404);
  if (!["expired", "cancelled"].includes(state(invitation, now))) throw new AdminError("That invitation is still waiting or was used.", 409);
  return createInvitation(session, store, now, invitation.label);
}
