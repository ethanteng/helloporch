import type { Metadata } from "next";
import Link from "next/link";
import { listPorches, type PorchRow } from "../../../../../lib/admin/porches.ts";
import { adminRequest, requireAdmin } from "../../../../../lib/admin/request.ts";
import { pacificDay, porchUsage, usageHistorySeconds, usagePresets, usageRange, type Tally, type UsageRow } from "../../../../../lib/admin/usage.ts";
import { ago, day } from "../../_ui/format";

export const metadata: Metadata = { title: "Porches" };

// A bedside that hasn't checked in for a day is likely off, unplugged or offline.
const offlineAfter = 86400;
const phoneNumber = (number: string) => number.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");
const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

function seen(row: PorchRow, now: number) {
  if (row.lastSeenAt === undefined) return <span className="muted">Never</span>;
  if (now - row.lastSeenAt > offlineAfter) {
    const days = Math.floor((now - row.lastSeenAt) / 86400);
    return <span className="tag warn">Offline for {days} {days === 1 ? "day" : "days"}</span>;
  }
  return ago(row.lastSeenAt, now);
}

const full = "Some of this range may be missing from Porch's records, so this is a minimum.";
const minimum = (count: number, partial?: boolean) => <span title={partial ? full : undefined}>{count}{partial ? "+" : ""}</span>;
const total = (tally: Tally) => minimum(tally.count, tally.partial);
// Active contacts are counted from the same histories. When any of those is a minimum, so is this.
const activePartial = (u: UsageRow) => !!(u.callsReceived.partial || u.audioMessages.partial || u.audioMessages.peoplePartial || u.videoMessages.partial || u.texts.partial);
// How many things, and from (or to) how many different people, such as "from 3 callers". Each is a minimum when the
// count is; the people can be one even when the count isn't.
function tallied(tally: Tally, [word, one, many]: [string, string, string], extra?: (plus: string) => string) {
  const plus = tally.partial ? "+" : "", peoplePlus = tally.partial || tally.peoplePartial ? "+" : "";
  return <>{total(tally)}{tally.count ? <span className="sub" title={peoplePlus ? full : undefined}>{word} {tally.people}{peoplePlus} {tally.people === 1 ? one : many}</span> : null}
    {tally.count && extra ? <span className="sub">{extra(plus)}</span> : null}</>;
}
function sum(rows: UsageRow[], pick: (row: UsageRow) => Tally): Tally {
  return { count: rows.reduce((n, row) => n + pick(row).count, 0), people: 0, ...(rows.some(row => pick(row).partial) ? { partial: true as const } : {}) };
}

export default async function PorchesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  const params = await searchParams, range = usageRange(params, now);
  // The dates in the custom range's fields: the range shown, or what was typed when it couldn't be used.
  const typed = (value: string | string[] | undefined) => typeof value === "string" ? value.slice(0, 10) : undefined;
  const fields = "custom" in range ? range.custom : range.error ? { from: typed(params.from) ?? "", to: typed(params.to) ?? "" } : { from: pacificDay(range.from), to: pacificDay(now) };
  const [rows, usage] = await Promise.all([listPorches(session, store), porchUsage(session, store, range, now)]);
  const usageByID = new Map(usage.map(u => [u.id, u]));
  const listed = rows.flatMap(row => { const u = usageByID.get(row.id); return u ? [{ row, u }] : []; }), shown = listed.map(({ u }) => u);
  const today = pacificDay(now), historyStarts = now - usageHistorySeconds;
  return (
    <>
      <h1>Porches</h1>
      <p className="lead">Every household, ours included. Messages, names, phone numbers and keypads stay private to each family: Activity counts calls, messages and texts without saying who they were with.</p>
      {rows.length ? (
        <div className="table">
          <table>
            <thead><tr><th>Porch for</th><th>Porch number</th><th>Set up</th><th>Bedside last seen</th><th>Family phones</th><th>Setup</th></tr></thead>
            <tbody>
              {rows.map(row => (
                <tr key={row.id}>
                  <td title={row.id}>{row.bedsideName}{row.invitationLabel && <span className="sub">{row.invitationLabel}</span>}{row.androidBedside && <span className="sub">Android tablet</span>}</td>
                  <td>{row.porchNumber ? phoneNumber(row.porchNumber) : row.numberPending ? <span className="muted">Being set up</span> : <span className="muted">None</span>}</td>
                  <td>{row.setUpAt ? day(row.setUpAt) : <span className="muted">Before this list</span>}</td>
                  <td>{seen(row, now)}</td>
                  <td>{row.familyPhones}{row.androidPhones ? <span className="sub">{row.androidPhones} Android</span> : null}</td>
                  <td>{row.setupFinished ? <span className="tag good">Finished</span> : <span className="tag warn">Not finished</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <p className="empty">No Porches yet.</p>}

      {rows.length > 0 && <>
        <h2 id="activity">Activity</h2>
        <div className="range-picker">
          <div className="range-links" role="group" aria-label="Time range">
            {usagePresets.map(p => (
              <Link key={p.key} href={`/porches?range=${p.key}#activity`} scroll={false} aria-current={"preset" in range && range.preset === p.key ? "true" : undefined}>{p.label}</Link>
            ))}
          </div>
          {/* Keyed by its dates, so choosing a preset after typing shows the preset's dates, not what was typed. */}
          <form key={`${fields.from} ${fields.to}`} className="custom-range" action="/porches#activity" method="get" aria-label="Custom range">
            {"preset" in range && <input type="hidden" name="range" value={range.preset} />}
            <label className="field"><span>From</span><input type="date" name="from" required max={today} defaultValue={fields.from} /></label>
            <label className="field"><span>To</span><input type="date" name="to" required max={today} defaultValue={fields.to} /></label>
            <button type="submit" className="small secondary">Show</button>
          </form>
        </div>
        {"error" in range && range.error && <p className="error" role="alert">{range.error} Showing {usagePresets.find(p => p.key === range.preset)?.label.toLowerCase()} instead.</p>}
        <p className="muted">{day(range.from)} to {range.to >= now ? "now" : day(range.to - 1)}, Pacific time.{range.from < historyStarts && <> Calls, texts and phone voicemail senders only go back 90 days, to {day(historyStarts)}.</>}</p>
        <div className="table">
          <table>
            <thead><tr><th>Porch for</th><th>Contacts</th><th>Active contacts</th><th>Calls received</th><th>Audio messages</th><th>Video messages</th><th>Texts</th><th>Calls made</th></tr></thead>
            <tbody>
              {listed.map(({ row, u }) => (
                <tr key={row.id}>
                  <td title={row.id}>{row.bedsideName}{row.invitationLabel && <span className="sub">{row.invitationLabel}</span>}</td>
                  <td>{u.contacts.porchApp + u.contacts.phoneNumbers}<span className="sub">{u.contacts.porchApp} on Porch, {plural(u.contacts.phoneNumbers, "number", "numbers")}</span></td>
                  <td>{minimum(u.activeContacts, activePartial(u))}<span className="sub">of {u.contacts.porchApp + u.contacts.phoneNumbers}</span></td>
                  <td>{tallied(u.callsReceived, ["from", "caller", "callers"], plus => `${u.callsReceived.answered}${plus} answered`)}</td>
                  <td>{tallied(u.audioMessages, ["from", "sender", "senders"], u.audioMessages.voicemails ? plus => `${u.audioMessages.voicemails}${plus} phone ${u.audioMessages.voicemails === 1 ? "voicemail" : "voicemails"}` : undefined)}</td>
                  <td>{tallied(u.videoMessages, ["from", "sender", "senders"])}</td>
                  <td>{tallied(u.texts, ["from", "sender", "senders"])}</td>
                  <td>{tallied(u.callsMade, ["to", "contact", "contacts"])}</td>
                </tr>
              ))}
            </tbody>
            {listed.length > 1 && (
              <tfoot>
                <tr>
                  <th scope="row">All Porches</th>
                  <td>{listed.reduce((n, { u }) => n + u.contacts.porchApp + u.contacts.phoneNumbers, 0)}</td>
                  <td>{minimum(listed.reduce((n, { u }) => n + u.activeContacts, 0), shown.some(activePartial))}</td>
                  <td>{total(sum(shown, u => u.callsReceived))}</td>
                  <td>{total(sum(shown, u => u.audioMessages))}</td>
                  <td>{total(sum(shown, u => u.videoMessages))}</td>
                  <td>{total(sum(shown, u => u.texts))}</td>
                  <td>{total(sum(shown, u => u.callsMade))}</td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
        <p className="note">
          Contacts are family members on the Porch app plus the phone numbers a household knows: saved on the keypad, approved to drop in, or allowed by a caregiver.
          A contact is active if they called, left a recorded message or texted. Calls come from each Porch&rsquo;s call history, which keeps its newest 100 calls for up to 90 days.
          Texts, and who left phone voicemail, are counted from November 2026, when Porch started keeping them. A + means some of that range may be missing from Porch&rsquo;s records, so the count is a minimum.
          Callers who hide their number aren&rsquo;t counted as senders.
        </p>
      </>}
    </>
  );
}
