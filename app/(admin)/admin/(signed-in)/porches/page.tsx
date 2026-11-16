import type { Metadata } from "next";
import Link from "next/link";
import { listPorches, type PorchRow } from "../../../../../lib/admin/porches.ts";
import { adminRequest, requireAdmin } from "../../../../../lib/admin/request.ts";
import { pacificDay, porchUsage, trendPoints, usageHistorySeconds, usagePresets, usageRange, type Tally, type UsageRow } from "../../../../../lib/admin/usage.ts";
import { ago, day, shortDay } from "../../_ui/format";
import Help from "../../_ui/Help";
import Sparkline from "../../_ui/Sparkline";
import TrendChart, { type TrendSeries } from "../../_ui/TrendChart";

export const metadata: Metadata = { title: "Porches" };

// A bedside that hasn't checked in for a day is likely off, unplugged or offline.
const offlineAfter = 86400;
const phoneNumber = (number: string) => number.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");
const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
const hidden = (text: string) => <span className="visually-hidden">{text} </span>;

function status(row: PorchRow, now: number) {
  let seen;
  if (row.lastSeenAt === undefined) seen = <span className="muted">Never seen</span>;
  else if (now - row.lastSeenAt > offlineAfter) {
    const days = Math.floor((now - row.lastSeenAt) / 86400);
    seen = <span className="tag warn">Offline {plural(days, "day", "days")}</span>;
  } else seen = <span className="seen"><span className="dot" aria-hidden="true" />Seen {ago(row.lastSeenAt, now)}</span>;
  return <span className="status">{seen}{!row.setupFinished && <span className="tag">Setup not finished</span>}</span>;
}

const bedside = (row: PorchRow) => row.lastSeenAt === undefined ? <span className="muted">No bedside</span> : <span className="chip">{row.androidBedside ? "Android" : "iOS"}</span>;
function phones(row: PorchRow, none: string) {
  const android = row.androidPhones ?? 0, ios = row.familyPhones - android;
  if (!row.familyPhones) return <span className="muted">{none}</span>;
  return <span className="chips">{ios > 0 && <span className="chip">{ios} iOS</span>}{android > 0 && <span className="chip">{android} Android</span>}</span>;
}

const full = "Some of this range may be missing from Porch's records, so this is a minimum.";
/** A count, with + when it's a minimum. Zero is grey. */
const count = (n: number, partial?: boolean) => <span className={n ? undefined : "muted"} title={partial ? full : undefined}>{n}{partial ? "+" : ""}</span>;
const total = (tally: Tally) => count(tally.count, tally.partial);
// Messages are audio and video messages together, phone voicemail included.
const messages = (u: UsageRow): Tally => ({ count: u.audioMessages.count + u.videoMessages.count, people: 0,
  ...(u.audioMessages.partial || u.videoMessages.partial ? { partial: true as const } : {}) });
// Active contacts are counted from the same histories. When any of those is a minimum, so is this.
const activePartial = (u: UsageRow) => !!(u.callsReceived.partial || u.audioMessages.partial || u.audioMessages.peoplePartial || u.videoMessages.partial || u.texts.partial);
/** How many, then from (or to) how many different people, such as "18 from 5 callers, 14 answered". */
function tallied(tally: Tally, [word, one, many]: [string, string, string], extra?: (plus: string) => string) {
  // A zero can be a minimum too, when the history is full and kept nothing from this range.
  if (!tally.count) return total(tally);
  const plus = tally.partial ? "+" : "", peoplePlus = tally.partial || tally.peoplePartial ? "+" : "";
  return <><span className="num">{total(tally)}</span><span className="muted" title={peoplePlus ? full : undefined}>
    {word} {tally.people}{peoplePlus} {tally.people === 1 ? one : many}{extra ? `, ${extra(plus)}` : ""}</span></>;
}
function sum(rows: UsageRow[], pick: (row: UsageRow) => Tally): Tally {
  return { count: rows.reduce((n, row) => n + pick(row).count, 0), people: 0, ...(rows.some(row => pick(row).partial) ? { partial: true as const } : {}) };
}
/** The list's activity columns, each a total and, with Trends on, its trend line. */
const columns: { name: string; color: TrendSeries["color"]; tally: (u: UsageRow) => Tally; line: (u: UsageRow) => number[] }[] = [
  { name: "Calls in", color: "s1", tally: u => u.callsReceived, line: u => u.trend.callsIn },
  { name: "Calls out", color: "s2", tally: u => u.callsMade, line: u => u.trend.callsMade },
  { name: "Messages", color: "s3", tally: messages, line: u => u.trend.messages },
  { name: "Texts", color: "s4", tally: u => u.texts, line: u => u.trend.texts },
];

const chevron = <svg className="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6" /></svg>;

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
  const preset = "preset" in range ? usagePresets.find(p => p.key === range.preset) : undefined;
  // Numbers, or each activity column as a trend line beside its total. Links keep the range and this choice.
  const trends = params.view === "trends", trendsQuery: Record<string, string> = trends ? { view: "trends" } : {};
  const rangeQuery: Record<string, string> = "custom" in range ? { from: range.custom.from, to: range.custom.to } : { range: range.preset };
  const porches = (query: Record<string, string>) => `/porches?${new URLSearchParams(query)}`;
  const dates = `${day(range.from)} – ${range.to >= now ? "now" : day(range.to - 1)}`;
  // Each trend line's points: a day each (named by the day most of it falls on), a week each, or 30 days each.
  const points = trendPoints(range);
  const bucket = points.seconds === 86400 ? "a day" : points.seconds === 7 * 86400 ? "a week" : "every 30 days";
  const labels = Array.from({ length: points.count }, (_, i) => {
    const start = range.from + i * points.seconds, end = Math.min(range.to, start + points.seconds);
    return points.seconds === 86400 ? shortDay((start + end) / 2) : `${shortDay(start)} – ${shortDay(end - 1)}`;
  });
  // Each column's lines share its busiest point, and the All Porches row adds every Porch's together.
  const most = columns.map(c => Math.max(1, ...shown.flatMap(c.line)));
  const allLines = columns.map(c => labels.map((_, i) => shown.reduce((n, u) => n + c.line(u)[i], 0)));

  return (
    <>
      <div className="titlerow">
        <div className="hgroup">
          <h1>Porches</h1>
          <Help id="porches-help" label="About this list">
            <ul>
              <li>Every household, ours included. Names, phone numbers, messages and keypads stay private to each family: activity is counted without saying who it was with.</li>
              <li><b>Offline</b>: the bedside hasn&rsquo;t checked in for a day.</li>
              <li><b>Setup not finished</b>: the Porch doesn&rsquo;t have its number or a family phone yet.</li>
              <li><b>App not reported</b>: the bedside&rsquo;s app is from before Porch reported its version, or it hasn&rsquo;t checked in since updating.</li>
            </ul>
          </Help>
        </div>
        {/* On its own row, above the controls: the custom form hangs down from them and would cover a message below. */}
        {"error" in range && range.error && <p className="error range-error" role="alert">{range.error} Showing {preset?.label.toLowerCase()} instead.</p>}
        {rows.length > 0 && (
          <div className="controls">
            <span className="muted">Activity</span>
            <div className="seg" role="group" aria-label="Time range">
              {usagePresets.map(p => (
                <Link key={p.key} href={porches({ range: p.key, ...trendsQuery })} scroll={false} aria-current={preset?.key === p.key ? "true" : undefined}>{p.short}</Link>
              ))}
              <details className="custom" open={"error" in range && !!range.error}>
                <summary aria-current={"custom" in range ? "true" : undefined}>Custom</summary>
                {/* Keyed by its dates, so choosing a preset after typing shows the preset's dates, not what was typed. */}
                <form key={`${fields.from} ${fields.to}`} className="custom-form" action="/porches" method="get" aria-label="Custom range">
                  {"preset" in range && <input type="hidden" name="range" value={range.preset} />}
                  {trends && <input type="hidden" name="view" value="trends" />}
                  <label className="field"><span>From</span><input type="date" name="from" required max={today} defaultValue={fields.from} /></label>
                  <label className="field"><span>To</span><input type="date" name="to" required max={today} defaultValue={fields.to} /></label>
                  <button type="submit" className="small">Show</button>
                </form>
              </details>
            </div>
            <span className="muted">{dates}</span>
            <div className="seg" role="group" aria-label="Show activity as">
              <Link href={porches(rangeQuery)} scroll={false} aria-current={trends ? undefined : "true"}>Numbers</Link>
              <Link href={porches({ ...rangeQuery, view: "trends" })} scroll={false} aria-current={trends ? "true" : undefined}>Trends</Link>
            </div>
            <Help id="activity-help" label="About these counts" end>
              <ul>
                <li><b>Contacts</b>: family on the Porch app plus the phone numbers a household knows: saved on the keypad, approved to drop in, or allowed by a caregiver. <b>Active</b> ones called, left a recorded message or texted.</li>
                <li><b>Messages</b>: audio and video messages, phone voicemail included.</li>
                <li>Calls come from each Porch&rsquo;s call history, which keeps its newest 100 calls for up to 90 days. Texts, and who left phone voicemail, are counted from November 2026.</li>
                <li><b>+</b> means some of the range may be missing from Porch&rsquo;s records, so the count is a minimum. Callers who hide their number aren&rsquo;t counted as senders.</li>
                <li>Days are in Pacific time.</li>
              </ul>
            </Help>
          </div>
        )}
      </div>
      {rows.length > 0 && range.from < historyStarts && <p className="muted">Calls, texts and phone voicemail senders only go back 90 days, to {day(historyStarts)}.</p>}

      {listed.length ? (
        <div className={trends ? "porch-list trends" : "porch-list"}>
          <div className="porch-rows">
            <div className="cols porch-head" aria-hidden="true">
              <span>Porch for</span><span>Status</span><span>Bedside · phones</span>
              {columns.map(c => <span key={c.name} className="n">{c.name}</span>)}<span />
            </div>
            {listed.map(({ row, u }) => {
              const contacts = u.contacts.porchApp + u.contacts.phoneNumbers;
              const any = columns.some(c => c.line(u).some(Boolean)), unsure = columns.some(c => c.tally(u).partial);
              return (
                <details key={row.id} className="porch">
                  <summary className="cols">
                    <span title={row.id}><span className="name">{row.bedsideName}</span>
                      {row.invitationLabel && row.invitationLabel !== row.bedsideName && <span className="sub">{row.invitationLabel}</span>}</span>
                    <span>{status(row, now)}</span>
                    <span className="chips">{hidden("Bedside")}{bedside(row)}<span className="muted" aria-hidden="true">·</span>{hidden("Family phones")}{phones(row, "no phones")}</span>
                    {columns.map((c, i) => (
                      <span key={c.name} className="n">{trends && <Sparkline values={c.line(u)} max={most[i]} color={c.color} />}{hidden(c.name)}{total(c.tally(u))}</span>
                    ))}
                    {chevron}
                  </summary>
                  <div className="panel">
                    <div>
                      <h3>This Porch</h3>
                      <dl className="pairs">
                        <dt>Porch number</dt><dd>{row.porchNumber ? phoneNumber(row.porchNumber) : <span className="muted">{row.numberPending ? "Being set up" : "None"}</span>}</dd>
                        <dt>Set up</dt><dd>{row.setUpAt ? day(row.setUpAt) : <span className="muted">Before this list</span>}</dd>
                        <dt>Bedside</dt><dd><span className="chips">{bedside(row)}{row.lastSeenAt !== undefined && (row.bedsideVersion ?? <span className="muted">App not reported</span>)}</span></dd>
                        <dt>Last seen</dt><dd>{row.lastSeenAt === undefined ? <span className="muted">Never</span> : ago(row.lastSeenAt, now)}</dd>
                        <dt>Family phones</dt><dd>{phones(row, "None")}</dd>
                      </dl>
                    </div>
                    <div>
                      <h3>{preset?.label ?? dates}</h3>
                      <dl className="pairs">
                        <dt>Contacts</dt><dd>{contacts ? <><span className="num">{contacts}</span><span className="muted">
                          {u.contacts.porchApp} on Porch, {plural(u.contacts.phoneNumbers, "number", "numbers")} · {u.activeContacts}{activePartial(u) ? "+" : ""} active</span></> : <span className="muted">0</span>}</dd>
                        <dt>Calls in</dt><dd>{tallied(u.callsReceived, ["from", "caller", "callers"], plus => `${u.callsReceived.answered}${plus} answered`)}</dd>
                        <dt>Calls out</dt><dd>{tallied(u.callsMade, ["to", "contact", "contacts"])}</dd>
                        <dt>Audio messages</dt><dd>{tallied(u.audioMessages, ["from", "sender", "senders"], u.audioMessages.voicemails ? plus => `${u.audioMessages.voicemails}${plus} phone ${u.audioMessages.voicemails === 1 ? "voicemail" : "voicemails"}` : undefined)}</dd>
                        <dt>Video messages</dt><dd>{tallied(u.videoMessages, ["from", "sender", "senders"])}</dd>
                        <dt>Texts</dt><dd>{tallied(u.texts, ["from", "sender", "senders"])}</dd>
                      </dl>
                    </div>
                    {any ? (
                      <TrendChart labels={labels} description={`${row.bedsideName}: calls in, calls out, messages and texts ${bucket}, ${dates}`}
                        series={columns.map(c => ({ name: c.name, color: c.color, values: c.line(u) }))} />
                    ) : <p className="quiet">{unsure ? "No calls, messages or texts found, but some of this range may be missing from Porch’s records."
                      : "No calls, messages or texts in this range."}</p>}
                  </div>
                </details>
              );
            })}
            {listed.length > 1 && (
              <div className="cols porch-total">
                <span>All Porches</span><span /><span />
                {columns.map((c, i) => (
                  <span key={c.name} className="n">{trends && <Sparkline values={allLines[i]} max={Math.max(...allLines[i])} color={c.color} />}{hidden(c.name)}{total(sum(shown, c.tally))}</span>
                ))}
                <span />
              </div>
            )}
          </div>
        </div>
      ) : <p className="empty">No Porches yet.</p>}
    </>
  );
}
