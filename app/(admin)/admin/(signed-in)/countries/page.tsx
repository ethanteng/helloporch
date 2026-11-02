import type { Metadata } from "next";
import { listCountries } from "../../../../../lib/admin/countries.ts";
import { requireAdmin } from "../../../../../lib/admin/request.ts";
import { AdminError } from "../../../../../lib/admin/session.ts";
import { dialingPermissions, homeCountry } from "../../../../../lib/calls/countries.ts";
import { AllowCountry, TurnOffCountry } from "../../_ui/CountryActions";

export const metadata: Metadata = { title: "Countries" };

const lead = "Where every Porch's keypad can call regular phones. These are Twilio's Voice Geo Permissions, so a change here changes Twilio. Premium-rate numbers stay off everywhere, and three-way calls stay in the US and Canada. The US and Canada always stay on, but places that share their +1, such as Puerto Rico and Jamaica, are separate countries here.";

export default async function CountriesPage() {
  const session = await requireAdmin();
  let countries;
  try { countries = await listCountries(session, dialingPermissions()); }
  catch (error) {
    if (!(error instanceof AdminError)) throw error;
    return <><h1>Countries</h1><p className="lead">{lead}</p><p role="alert" className="error">{error.message}</p></>;
  }
  const allowed = countries.filter(country => country.enabled);
  return (
    <>
      <h1>Countries</h1>
      <p className="lead">{lead}</p>
      <div className="table">
        <table className="narrow">
          <thead><tr><th>Country</th><th>Calling code</th><th><span className="visually-hidden">Change</span></th></tr></thead>
          <tbody>
            {allowed.map(country => (
              <tr key={country.iso}>
                <td>{country.name}</td>
                <td>{country.codes.map(code => `+${code}`).join(", ")}</td>
                <td className="actions">{country.iso === homeCountry ? <span className="muted">Always on</span> : <TurnOffCountry iso={country.iso} name={country.name} />}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <h2>Allow another country</h2>
      <p className="lead">Keypad contacts there can be saved and called once it&apos;s on. Calls cost Twilio&apos;s rate for the country, often much more to mobiles.</p>
      <AllowCountry countries={countries.filter(country => !country.enabled).map(({ iso, name }) => ({ iso, name }))} />
    </>
  );
}
