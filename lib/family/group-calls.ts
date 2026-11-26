import { randomUUID } from "node:crypto";
import { displayName, requireValue, type Call, type Household, type Member, type PorchGuest } from "./household.ts";

// A bedside key that rings two family members at once, such as Ethan and his brother David. The first who can ring is
// the person called, as for any key; the other rings as a family guest (porch-guests.ts) from the start, with an incoming
// call of their own. Whoever answers first is on the call with the bedside, and the other can still answer and join until
// their ring runs out. One declining doesn't stop the other ringing. Only family on Porch can be in a group, and only
// two, so a group call is the three-person call Porch already has.
//
// Each phone keeps the ID it was rung with. When the guest answers first, or the person called declines or can't be
// reached while the guest still rings, the two swap places: the guest becomes the person called, under their own ID
// (`toCallID`), and the one before goes on as a family guest under theirs.
export const groupCallLimits = { people: 2 };

/** The family members a group key names, in its order, who are still in the family. Repeats count once. */
export function groupMembers(house: Household, me: Member, ids: unknown, kind: unknown): Member[] {
  requireValue(me.role === "bedside" && kind === "call", "Only the bedside can call a group.", 403);
  requireValue(Array.isArray(ids) && ids.length >= 1 && ids.length <= groupCallLimits.people && ids.every(id => typeof id === "string"),
    `Choose 1–${groupCallLimits.people} people to call.`);
  return [...new Set(ids as string[])].map(id => house.members.find(m => m.id === id && !m.revoked && m.role === "family")).filter((m): m is Member => !!m);
}
/** What call history names a group call: the key's name, or else the names of the people it rings. */
export function groupName(value: unknown, people: Member[]): string {
  const name = typeof value === "string" ? value.trim() : "";
  return name.length > 0 && name.length <= 80 ? name : people.map(displayName).join(" and ");
}
/** The rest of a group, ringing alongside the person called until `ringUntil`. */
export function groupGuests(bedside: Member, people: Member[], now: number, ringUntil: number): PorchGuest[] {
  return people.map(m => ({ id: randomUUID(), memberID: m.id, addedBy: bedside.id, invitedAt: now, ringUntil, state: "ringing", group: true }));
}
/** The other person a group call is still ringing. */
export function ringingGroupGuest(call: Call): PorchGuest | undefined {
  return call.porchGuests?.find(g => g.group && g.state === "ringing");
}
/** Makes `guest` the person called: they answered first, or the person called before them declined (`previous`
 * "declined") or couldn't be reached ("missed"). The person called before goes on as a family guest under the ID their
 * phone knows the call by, still ringing when `previous` is "ringing". */
export function promoteGroupGuest(call: Call, guest: PorchGuest, now: number, previous: "ringing" | "declined" | "missed") {
  const before: PorchGuest = { id: call.toCallID ?? call.id, memberID: call.to, addedBy: call.from, invitedAt: call.createdAt, ringUntil: guest.ringUntil,
    state: previous, group: true, ...(call.receivedAt !== undefined ? { receivedAt: call.receivedAt } : {}), ...(previous === "ringing" ? {} : { endedAt: now }) };
  call.porchGuests = [...(call.porchGuests ?? []).filter(g => g.id !== guest.id), before];
  call.to = guest.memberID;
  if (guest.id === call.id) delete call.toCallID; else call.toCallID = guest.id;
  if (guest.receivedAt !== undefined) call.receivedAt = guest.receivedAt; else delete call.receivedAt;
}
