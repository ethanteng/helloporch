import { householdIDs, invitationsKey, type BedsideInvitation } from "../family/activations.ts";
import type { Household } from "../family/household.ts";
import type { FamilyStore } from "../family/store.ts";
import { assertAdmin, type AdminSession } from "./session.ts";

/** What the admin page shows about a household. It never includes messages, family members' names, keypad contents or
 * call details. `bedsideName` is the person the Porch is for, such as "Mom". */
export type PorchRow = { id: string; bedsideName: string; invitationLabel?: string; porchNumber?: string; numberPending: boolean;
  setUpAt?: number; lastSeenAt?: number; familyPhones: number; setupFinished: boolean };

export async function listPorches(session: AdminSession, store: FamilyStore): Promise<PorchRow[]> {
  assertAdmin(session);
  const [ids, rawInvitations] = await Promise.all([householdIDs(store), store.get(invitationsKey)]);
  const invitations: BedsideInvitation[] = JSON.parse(rawInvitations ?? "[]");
  const houses = await Promise.all(ids.map(async id => store.get(`house:${id}`)));
  return houses.flatMap(raw => {
    if (!raw) return [];
    const house: Household = JSON.parse(raw);
    const bedside = house.members.find(m => m.role === "bedside" && !m.revoked);
    const invitation = invitations.find(i => i.householdID === house.id);
    const familyPhones = house.members.filter(m => m.role === "family" && !m.revoked).length;
    return [{ id: house.id, bedsideName: bedside?.name ?? house.name, ...(invitation ? { invitationLabel: invitation.label } : {}),
      ...(house.porchNumber ? { porchNumber: house.porchNumber.number } : {}), numberPending: !house.porchNumber && !!house.phoneSetup,
      ...(house.createdAt ?? invitation?.setUpAt ? { setUpAt: house.createdAt ?? invitation?.setUpAt } : {}),
      ...(bedside ? { lastSeenAt: bedside.seenAt } : {}), familyPhones,
      // Until the setup screens have a checklist, a Porch is set up once it has its number and a family phone.
      setupFinished: !!house.porchNumber && familyPhones > 0 }];
  }).sort((a, b) => (b.setUpAt ?? 0) - (a.setUpAt ?? 0));
}
