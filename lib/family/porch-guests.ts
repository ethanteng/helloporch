import { randomUUID } from "node:crypto";
import { activePorchGuest, callRoom, displayName, expire, FamilyError, mutate, requireValue, ringLimits, type Call, type Household, type Member, type PorchGuest } from "./household.ts";
import { inRoom, type PhoneGuestServices } from "./phone-guests.ts";
import type { FamilyStore } from "./store.ts";

// Ringing another family member into a call with the bedside, such as a brother joining Mom and Ethan with video.
// Their phone gets an ordinary incoming Porch call for this invitation (see guestCall), and answering it joins the
// same room. Anyone in the family on the call can add one, one at a time; unlike a phone guest, they stay on if
// whoever added them leaves.
export const porchGuestActions = new Set(["addPorchGuest"]);
export const porchGuestLimits = { perCall: 5, ringSeconds: ringLimits.standard };
export type PorchGuestContext = { store: FamilyStore; now: number; house: Household; me: Member; input: Record<string, unknown>;
  rooms: PhoneGuestServices["rooms"];
  /** Whether their Porch app can ring now: open, or reachable by a VoIP push. */
  reachable: (member: Member) => boolean;
  /** Rings their phone. False when the push couldn't be delivered and their app isn't open. */
  ring: (guest: PorchGuest, member: Member, callerName: string) => Promise<boolean> };

function bedsideOf(house: Household, call: Call) {
  return house.members.find(m => m.role === "bedside" && [call.from, call.to].includes(m.id));
}
/** How a family guest's phone names the call: "Ethan with Mom". */
export function guestCallerName(house: Household, call: Call, guest: PorchGuest): string {
  const adder = house.members.find(m => m.id === guest.addedBy), bedside = bedsideOf(house, call);
  return [adder, bedside].filter((m): m is Member => !!m).map(displayName).join(" with ") || "Family";
}
/** A family guest's own view of the call: an ordinary incoming call that is ringing, answered, or over. */
export function guestCall(house: Household, call: Call, guest: PorchGuest) {
  const state = guest.state === "ringing" ? "pending" : guest.state === "joined" && call.state === "accepted" ? "accepted" : "ended";
  return { id: guest.id, from: guest.addedBy, to: guest.memberID, mode: call.mode, kind: "call", state, createdAt: guest.invitedAt,
    ...(guest.joinedAt ? { acceptedAt: guest.joinedAt } : {}), expiresAt: guest.state === "ringing" ? guest.ringUntil : call.expiresAt,
    ...(state === "ended" ? { reason: guest.state === "missed" ? "The call timed out." : "Call ended." } : {}),
    guest: true, source: "porch", callerName: guestCallerName(house, call, guest) };
}
/** What the call's two ends see of the family member they rang in. */
export function publicPorchGuest(house: Household, call: Call) {
  const guest = call.porchGuests?.at(-1), member = guest && house.members.find(m => m.id === guest.memberID);
  return guest && member && { id: guest.id, memberID: guest.memberID, name: displayName(member), state: guest.state };
}

export async function handlePorchGuestAction(_action: string, context: PorchGuestContext) {
  const { store, now, house, me, input, rooms } = context;
  const call = house.call;
  requireValue(call && call.id === input.callID && [call.from, call.to].includes(me.id) && !call.phone, "This call is no longer available.", 404);
  requireValue(me.role === "family", "Only a family member on the call can add someone.", 403);
  requireValue(call.state === "accepted" && call.expiresAt > now && call.left?.[me.id] === undefined, "Add someone once you're both on the call.", 409);
  const bedside = bedsideOf(house, call);
  requireValue(bedside, "This call is no longer available.", 404);
  requireValue(call.left?.[bedside.id] === undefined, `${displayName(bedside)} has left this call.`, 409);
  const target = house.members.find(m => m.id === input.memberID && !m.revoked && m.role === "family" && ![call.from, call.to].includes(m.id));
  requireValue(target, "This person isn't in your family on Porch.", 404);
  if (!context.reachable(target)) throw new FamilyError(`${displayName(target)}'s Porch app isn't ready. Ask them to open it.`, 409, "offline");
  // Don't ring anybody until both of you are actually in the call.
  requireValue(await inRoom(rooms, callRoom(call), bedside.id) && await inRoom(rooms, callRoom(call), me.id),
    `Porch can add someone once you and ${displayName(bedside)} are both connected.`, 409);

  const { house: updated, result: { guest, invitee } } = await mutate(store, house.id, current => {
    expire(current, now);
    const live = current.call;
    requireValue(live?.id === call.id && live.state === "accepted" && live.left?.[me.id] === undefined && live.left?.[bedside.id] === undefined, "This call ended.", 410);
    // Access can change while the room is checked: ring only someone still in the family, using what's stored now.
    requireValue(current.members.some(m => m.id === me.id && !m.revoked), "This call is no longer available.", 404);
    const invitee = current.members.find(m => m.id === target.id && !m.revoked && m.role === "family" && ![live.from, live.to].includes(m.id));
    requireValue(invitee, "This person isn't in your family on Porch.", 404);
    requireValue(!activePorchGuest(live), "Someone is already being added to this call.", 409);
    requireValue((live.porchGuests?.length ?? 0) < porchGuestLimits.perCall, "This call can't add more people. Start a new call to add someone else.", 429);
    const added: PorchGuest = { id: randomUUID(), memberID: target.id, addedBy: me.id, invitedAt: now, ringUntil: now + porchGuestLimits.ringSeconds, state: "ringing" };
    (live.porchGuests ??= []).push(added);
    return { guest: added, invitee };
  });
  // Outside the update, as for ordinary calls: only an invitation that won the household's reservation rings.
  let delivered = false;
  try { delivered = await context.ring(guest, invitee, guestCallerName(updated, updated.call!, guest)); } catch { /* treated as undelivered */ }
  if (!delivered) {
    const { result: missed } = await mutate(store, house.id, current => {
      const ringing = current.call?.porchGuests?.find(g => g.id === guest.id);
      // A receipt or an answer outweighs a missing push acknowledgment.
      if (ringing?.state !== "ringing" || ringing.receivedAt !== undefined) return false;
      ringing.state = "missed"; ringing.endedAt = now;
      return true;
    });
    if (missed) throw new FamilyError(`Couldn't reach ${displayName(invitee)}'s Porch app.`, 409, "offline");
  }
  return { porchGuest: { id: guest.id, memberID: invitee.id, name: displayName(invitee), state: guest.state } };
}
