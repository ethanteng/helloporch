import { homeCountry, type DialingCountry, type DialingPermissions } from "../calls/countries.ts";
import type { FamilyStore } from "../family/store.ts";
import { logActivity } from "./activity.ts";
import { AdminError, assertAdmin, type AdminSession } from "./session.ts";

/** Every country in Twilio's list, by name, with whether Porch can call it. */
export async function listCountries(session: AdminSession, permissions: DialingPermissions | undefined): Promise<DialingCountry[]> {
  assertAdmin(session);
  if (!permissions) throw new AdminError("Twilio isn't set up on this server. Set TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN.", 503);
  let countries: DialingCountry[];
  try { countries = await permissions.list(); } catch { throw new AdminError("Couldn't reach Twilio. Try again in a minute.", 502); }
  return countries.sort((a, b) => a.name.localeCompare(b.name));
}

/** Turns calls to a country on or off in Twilio, for every Porch at once. Contacts already saved there keep their place
 * on the keypad, but Twilio won't ring them while the country is off. */
export async function setCountry(session: AdminSession, store: FamilyStore, now: number, permissions: DialingPermissions | undefined, iso: unknown, enabled: boolean) {
  const country = (await listCountries(session, permissions)).find(c => c.iso === iso);
  if (!country) throw new AdminError("Choose a country.");
  // Already in this state: nothing to send, including a repeat Allow for the US and Canada.
  if (country.enabled === enabled) return;
  // Porch numbers and three-way calls need them. Turning them off is refused; turning them back on is allowed.
  if (country.iso === homeCountry && !enabled) throw new AdminError("Calls to the US and Canada always stay on.");
  try { await permissions!.set(country.iso, enabled); } catch { throw new AdminError("Twilio didn't make the change. Try again in a minute.", 502); }
  await logActivity(store, now, enabled ? "Allowed calls to a country" : "Stopped calls to a country", country.name);
}
