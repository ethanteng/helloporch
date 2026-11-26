import { householdIDs, invitationsKey, type BedsideInvitation } from "../family/activations.ts";
import type { BedsidePhoneKind } from "../family/bedside-phone.ts";
import type { Household } from "../family/household.ts";
import type { FamilyStore } from "../family/store.ts";
import { assertAdmin, type AdminSession } from "./session.ts";

/** What the admin page shows about a household. It never includes messages, family members' names, keypad contents or
 * call details. `bedsideName` is the person the Porch is for, such as "Mom". `androidBedside` and `androidPhones` say which
 * of its devices run Android; the rest are iPads and iPhones. `bedsideVersion` is the version of Porch the bedside last
 * reported, such as "0.1.0 (78)"; a bedside on an app from before it was reported has none. `phone` is its desk phone as
 * it last reported it: how it's plugged in, whether it's connected, since when, and whether it's been out long enough
 * that caregivers were told (`noticed`). A bedside with no phone set up, or an app from before it was reported, has none. */
export type PorchRow = { id: string; bedsideName: string; invitationLabel?: string; porchNumber?: string; numberPending: boolean;
  setUpAt?: number; lastSeenAt?: number; bedsideVersion?: string; familyPhones: number; androidBedside?: true; androidPhones?: number; setupFinished: boolean;
  phone?: { kind: BedsidePhoneKind; connected: boolean; since: number; noticed?: true } };

/** Every listed household that still exists. */
export async function readHouseholds(store: FamilyStore): Promise<Household[]> {
  const raws = await Promise.all((await householdIDs(store)).map(id => store.get(`house:${id}`)));
  return raws.flatMap(raw => raw ? [JSON.parse(raw) as Household] : []);
}

export async function listPorches(session: AdminSession, store: FamilyStore): Promise<PorchRow[]> {
  assertAdmin(session);
  const [houses, rawInvitations] = await Promise.all([readHouseholds(store), store.get(invitationsKey)]);
  const invitations: BedsideInvitation[] = JSON.parse(rawInvitations ?? "[]");
  return houses.map(house => {
    const bedside = house.members.find(m => m.role === "bedside" && !m.revoked);
    const invitation = invitations.find(i => i.householdID === house.id);
    const phones = house.members.filter(m => m.role === "family" && !m.revoked), familyPhones = phones.length;
    const androidPhones = phones.filter(m => m.platform === "android").length;
    return { id: house.id, bedsideName: bedside?.name ?? house.name, ...(invitation ? { invitationLabel: invitation.label } : {}),
      ...(house.porchNumber ? { porchNumber: house.porchNumber.number } : {}), numberPending: !house.porchNumber && !!house.phoneSetup,
      ...(house.createdAt ?? invitation?.setUpAt ? { setUpAt: house.createdAt ?? invitation?.setUpAt } : {}),
      ...(bedside ? { lastSeenAt: bedside.seenAt } : {}), ...(bedside?.appVersion ? { bedsideVersion: bedside.appVersion } : {}), familyPhones,
      ...(bedside?.platform === "android" ? { androidBedside: true as const } : {}), ...(androidPhones ? { androidPhones } : {}),
      ...(house.bedsidePhone ? { phone: { kind: house.bedsidePhone.kind, connected: house.bedsidePhone.connected, since: house.bedsidePhone.since,
        ...(!house.bedsidePhone.connected && house.bedsidePhone.noticedAt !== undefined ? { noticed: true as const } : {}) } } : {}),
      // Until the setup screens have a checklist, a Porch is set up once it has its number and a family phone.
      setupFinished: !!house.porchNumber && familyPhones > 0 };
  }).sort((a, b) => (b.setUpAt ?? 0) - (a.setUpAt ?? 0));
}
