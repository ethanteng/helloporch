import { dialableNumber } from "../family/phone-guests.ts";

// Which countries Porch can ring regular phones in. Twilio's Voice Geo Permissions are the only list: the admin page
// switches them, and Twilio refuses to dial a country they leave off (error 32205 on the trunk). Porch reads them only
// to turn away a keypad contact it couldn't call, rather than let the call fail when it's dialed. Three-way calls are
// limited to the US and Canada separately, in phone-guests.ts.
// https://www.twilio.com/docs/voice/api/dialingpermissions-country-resource

/** A country in Twilio's list. `codes` are its calling codes: Jamaica is 1876 and 1658, the US and Canada together 1. */
export type DialingCountry = { iso: string; name: string; codes: string[]; enabled: boolean };
/** Twilio's Geo Permissions. Tests fake them, so they never change the account. */
export type DialingPermissions = {
  list(): Promise<DialingCountry[]>;
  /** Turns calls to the country's ordinary numbers on or off. Its premium-rate and high-risk numbers always stay off. */
  set(iso: string, enabled: boolean): Promise<void>;
};
/** The US and Canada stay on: the Porch numbers, three-way calls and most keypad contacts are there. */
export const homeCountry = "US";

export function twilioDialing(accountSID: string, authToken: string, fetcher: typeof fetch = fetch): DialingPermissions {
  const base = "https://voice.twilio.com/v1/DialingPermissions";
  const authorization = `Basic ${Buffer.from(`${accountSID}:${authToken}`).toString("base64")}`;
  const call = async (url: string, form?: URLSearchParams) => {
    const response = await fetcher(url, { method: form ? "POST" : "GET", body: form, redirect: "error", signal: AbortSignal.timeout(10_000),
      headers: { authorization, ...(form ? { "content-type": "application/x-www-form-urlencoded" } : {}) } });
    if (!response.ok) throw new Error(`Twilio request failed (${response.status}).`);
    return await response.json() as Record<string, unknown>;
  };
  return {
    async list() {
      const countries: DialingCountry[] = [];
      // All of them fit on one page today; the rest are followed in case that changes.
      for (let url: unknown = `${base}/Countries?PageSize=1000`, pages = 0; typeof url === "string" && url.startsWith(`${base}/`) && pages < 5; pages++) {
        const body = await call(url);
        for (const c of Array.isArray(body.content) ? body.content as Record<string, unknown>[] : []) {
          // The API sends bare digits, such as "1876", but Twilio's docs show "+1". Porch keeps the digits either way.
          const codes = Array.isArray(c.country_codes) ? c.country_codes.flatMap(code => typeof code === "string" && /^\+?[0-9]{1,6}$/.test(code) ? [code.replace("+", "")] : []) : [];
          if (typeof c.iso_code === "string" && /^[A-Z]{2}$/.test(c.iso_code) && typeof c.name === "string" && codes.length)
            countries.push({ iso: c.iso_code, name: c.name, codes, enabled: c.low_risk_numbers_enabled === true });
        }
        url = (body.meta as Record<string, unknown> | undefined)?.next_page_url;
      }
      return countries;
    },
    async set(iso, enabled) {
      const update = [{ iso_code: iso, low_risk_numbers_enabled: enabled, high_risk_special_numbers_enabled: false, high_risk_tollfraud_numbers_enabled: false }];
      const body = await call(`${base}/BulkCountryUpdates`, new URLSearchParams({ UpdateRequest: JSON.stringify(update) }));
      if (body.update_count !== 1) throw new Error("Twilio didn't update the country.");
    },
  };
}

/** Twilio's Geo Permissions for this server's account, or nothing when Twilio isn't set up here. */
export function dialingPermissions(): DialingPermissions | undefined {
  const { TWILIO_ACCOUNT_SID: accountSID, TWILIO_AUTH_TOKEN: authToken } = process.env;
  return accountSID && /^AC[0-9a-f]{32}$/.test(accountSID) && authToken ? twilioDialing(accountSID, authToken) : undefined;
}

/** The country an E.164 number rings in: the one with the longest calling code it starts with, so +1 876 is Jamaica. */
export function countryOf(number: string, countries: DialingCountry[]): DialingCountry | undefined {
  let best: DialingCountry | undefined, length = 0;
  for (const country of countries) for (const code of country.codes)
    if (code.length > length && number.startsWith(`+${code}`)) { best = country; length = code.length; }
  return best;
}

/** Why Porch can't call this number, or nothing when it can. Twilio being unreachable isn't a reason to refuse: it still
 * checks the country when the call is dialed. */
export async function uncallable(number: string, permissions: DialingPermissions | undefined): Promise<string | undefined> {
  if (!permissions) return;
  let countries: DialingCountry[];
  try { countries = await permissions.list(); } catch { return; }
  if (!countries.length) return;
  const country = countryOf(number, countries);
  if (!country) return "Porch can't call this number.";
  if (!country.enabled) return `Porch can't call phone numbers in ${country.name} yet.`;
  // Twilio refuses premium-rate numbers everywhere. Porch knows the US and Canadian ones, as for three-way calls.
  if (country.iso === homeCountry && !dialableNumber(number)) return "Porch can't call premium-rate or special-service numbers.";
}
