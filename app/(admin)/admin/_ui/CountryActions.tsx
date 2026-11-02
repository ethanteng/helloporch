"use client";
import { useActionState } from "react";
import { setCountryAction } from "../actions";

/** **Turn off** for a country Porch can call. */
export function TurnOffCountry({ iso, name }: { iso: string; name: string }) {
  const [state, act, pending] = useActionState(setCountryAction, {});
  return (
    <form action={act}>
      <input type="hidden" name="iso" value={iso} />
      <input type="hidden" name="enabled" value="false" />
      <button type="submit" className="secondary small" disabled={pending} aria-label={`Turn off calls to ${name}`}>{pending ? "Turning off…" : "Turn off"}</button>
      {state.error && <p role="alert" className="error">{state.error}</p>}
    </form>
  );
}

/** The countries Porch can't call yet, and **Allow calls**. */
export function AllowCountry({ countries }: { countries: { iso: string; name: string }[] }) {
  const [state, act, pending] = useActionState(setCountryAction, {});
  return (
    <form action={act} className="stack">
      <div className="row invite">
        <label className="field grow">
          <span>Country</span>
          <select name="iso" required defaultValue="">
            <option value="" disabled>Choose a country</option>
            {countries.map(country => <option key={country.iso} value={country.iso}>{country.name}</option>)}
          </select>
        </label>
        <input type="hidden" name="enabled" value="true" />
        <button type="submit" disabled={pending}>{pending ? "Allowing…" : "Allow calls"}</button>
      </div>
      {state.error && <p role="alert" className="error">{state.error}</p>}
    </form>
  );
}
