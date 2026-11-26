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
/** Roughly how long, short: "25 min", "3 hours", "2 days". */
function howLong(seconds: number) {
  const minutes = Math.max(1, Math.floor(seconds / 60));
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  return hours < 48 ? plural(hours, "hour", "hours") : plural(Math.floor(hours / 24), "day", "days");
}
const phoneKind = (kind: string) => kind === "adapter" ? "adapter" : "Cell2Jack";

const svgProps = { viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 2.2, strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": true } as const;
const phoneOff = <svg {...svgProps}><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2" /><path d="M3 3l18 18" /></svg>;
const powerOff = <svg {...svgProps}><path d="M12 3v9" /><path d="M6.3 6.8a8 8 0 1 0 11.4 0" /></svg>;

/** What needs a look at a Porch: its bedside has been offline for a day (red), or it's on and its desk phone has been
 * out long enough that caregivers were told (amber). Offline comes first: the phone can't be known then. */
type Problem = { level: "bad" | "warn"; short: string; long: string };
function problem(row: PorchRow, now: number): Problem | undefined {
  if (row.lastSeenAt !== undefined && now - row.lastSeenAt > offlineAfter) {
    const days = plural(Math.floor((now - row.lastSeenAt) / 86400), "day", "days");
    return { level: "bad", short: `Offline ${days}`, long: `Offline for ${days}` };
  }
  if (row.phone?.noticed) return { level: "warn", short: "Phone not connected", long: `Phone not connected for ${howLong(now - row.phone.since)}` };
  return undefined;
}
const pill = (p: Problem, long = false) => <span className={`pill ${p.level}`}>{p.level === "bad" ? powerOff : phoneOff}{long ? p.long : p.short}</span>;

function status(row: PorchRow, now: number) {
  const p = problem(row, now);
  const main = p ? pill(p) : row.lastSeenAt === undefined ? <span className="muted">Never seen</span>
    : <span className="seen"><span className="dot" aria-hidden="true" />Seen {ago(row.lastSeenAt, now)}</span>;
  return <span className="status lines">{main}{!row.setupFinished && <span className="muted subline">Setup not finished</span>}</span>;
}

const bedside = (row: PorchRow) => row.lastSeenAt === undefined ? <span className="muted">No bedside</span> : <span className="chip">{row.androidBedside ? "Android" : "iOS"}</span>;
function phones(row: PorchRow, none: string) {
  const android = row.androidPhones ?? 0, ios = row.familyPhones - android;
  if (!row.familyPhones) return <span className="muted">{none}</span>;
  return <span className="chips">{ios > 0 && <span className="chip">{ios} iOS</span>}{android > 0 && <span className="chip">{android} Android</span>}</span>;
}

/** One line of a Porch's health: a dot, what, and how it is. A problem's line is tinted. */
type Check = { level: "ok" | "warn" | "bad" | "none"; label: string; value: React.ReactNode; flag?: boolean };
function checks(row: PorchRow, now: number): Check[] {
  const offline = row.lastSeenAt !== undefined && now - row.lastSeenAt > offlineAfter;
  const app = `${row.androidBedside ? "Android" : "iOS"} ${row.bedsideVersion ?? "· app not reported"}`;
  const bedsideCheck: Check = row.lastSeenAt === undefined ? { level: "none", label: "Bedside", value: "Never seen" }
    : { level: offline ? "bad" : "ok", flag: offline, label: "Bedside",
      value: <>{offline ? <b>Offline for {plural(Math.floor((now - row.lastSeenAt) / 86400), "day", "days")}</b> : `Seen ${ago(row.lastSeenAt, now)}`} · {app}</> };
  const phone = row.phone;
  const phoneCheck: Check = offline ? { level: "none", label: "Phone", value: <span className="muted">Unknown while offline</span> }
    : !phone ? { level: "none", label: "Phone", value: <span className="muted">None reported</span> }
    : phone.connected ? { level: "ok", label: "Phone", value: `Connected · ${phoneKind(phone.kind)}` }
    : phone.noticed ? { level: "warn", flag: true, label: "Phone", value: <><b>Not connected</b> for {howLong(now - phone.since)} · {phoneKind(phone.kind)}</> }
    // Out, but not yet long enough to tell anyone.
    : { level: "none", label: "Phone", value: `Not connected for ${howLong(now - phone.since)} · ${phoneKind(phone.kind)}` };
  return [bedsideCheck, phoneCheck,
    { level: row.porchNumber ? "ok" : "none", label: "Porch number", value: row.porchNumber ? phoneNumber(row.porchNumber) : <span className="muted">{row.numberPending ? "Being set up" : "None"}</span> },
    { level: row.familyPhones ? "ok" : "none", label: "Family phones", value: phones(row, "None") }];
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
/** From (or to) how many different people, for a total's tooltip, such as "from 5 callers, 14 answered". */
function detail(tally: Tally, [word, one, many]: [string, string, string], extra?: (plus: string) => string) {
  if (!tally.count) return undefined;
  const plus = tally.partial ? "+" : "", peoplePlus = tally.partial || tally.peoplePartial ? "+" : "";
  return `${word} ${tally.people}${peoplePlus} ${tally.people === 1 ? one : many}${extra ? `, ${extra(plus)}` : ""}${peoplePlus ? `. ${full}` : ""}`;
}
function sum(rows: UsageRow[], pick: (row: UsageRow) => Tally): Tally {
  return { count: rows.reduce((n, row) => n + pick(row).count, 0), people: 0, ...(rows.some(row => pick(row).partial) ? { partial: true as const } : {}) };
}
/** The list's activity columns, each a total and, with Trends on, its trend line. */
const columns: { name: string; color: TrendSeries["color"]; tally: (u: UsageRow) => Tally; line: (u: UsageRow) => number[]; detail: (u: UsageRow) => string | undefined }[] = [
  { name: "Calls in", color: "s1", tally: u => u.callsReceived, line: u => u.trend.callsIn,
    detail: u => detail(u.callsReceived, ["from", "caller", "callers"], plus => `${u.callsReceived.answered}${plus} answered`) },
  { name: "Calls out", color: "s2", tally: u => u.callsMade, line: u => u.trend.callsMade, detail: u => detail(u.callsMade, ["to", "contact", "contacts"]) },
  { name: "Messages", color: "s3", tally: messages, line: u => u.trend.messages,
    detail: u => messages(u).count ? `${u.audioMessages.count} audio, ${u.videoMessages.count} video${u.audioMessages.voicemails ? `, ${plural(u.audioMessages.voicemails, "phone voicemail", "phone voicemails")}` : ""}` : undefined },
  { name: "Texts", color: "s4", tally: u => u.texts, line: u => u.trend.texts, detail: u => detail(u.texts, ["from", "sender", "senders"]) },
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
  // Porches that need a look come first, offline ones before those whose phone is out; the rest stay newest first.
  const rank = (row: PorchRow) => { const level = problem(row, now)?.level; return level === "bad" ? 0 : level === "warn" ? 1 : 2; };
  const listed = rows.flatMap(row => { const u = usageByID.get(row.id); return u ? [{ row, u }] : []; })
    .map((item, index) => ({ ...item, index })).sort((a, b) => rank(a.row) - rank(b.row) || a.index - b.index);
  const shown = listed.map(({ u }) => u);
  const needs = listed.flatMap(({ row }) => { const p = problem(row, now); return p ? [{ row, p }] : []; });
  const today = pacificDay(now), historyStarts = now - usageHistorySeconds;
  const preset = "preset" in range ? usagePresets.find(p => p.key === range.preset) : undefined;
  // Numbers, or each activity column as a trend line beside its total. Links keep the range and this choice.
  const trends = params.view === "trends", trendsQuery: Record<string, string> = trends ? { view: "trends" } : {};
  const rangeQuery: Record<string, string> = "custom" in range ? { from: range.custom.from, to: range.custom.to } : { range: range.preset };
  const porches = (query: Record<string, string>) => `/porches?${new URLSearchParams(query)}`;
  // A Porch opened from Needs a look, by its Show link.
  const opened = typeof params.open === "string" ? params.open : undefined;
  const dates = `${day(range.from)} – ${range.to >= now ? "now" : day(range.to - 1)}`;
  // Each trend line's points: a day each (named by the day most of it falls on) or a week each.
  const points = trendPoints(range);
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
              <li><b>Phone not connected</b>: the bedside is on, but its desk phone hasn&rsquo;t answered for 10 minutes. Its caregivers were told.</li>
              <li><b>Setup not finished</b>: the Porch doesn&rsquo;t have its number or a family phone yet.</li>
              <li><b>App not reported</b>: the bedside&rsquo;s app is from before Porch reported its version, or it hasn&rsquo;t checked in since updating.</li>
            </ul>
          </Help>
        </div>
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
                <li>Hover a total in a Porch&rsquo;s details for how many people it was with.</li>
                <li>Calls come from each Porch&rsquo;s call history, which keeps its newest 100 calls for up to 90 days. Texts, and who left phone voicemail, are counted from November 2026.</li>
                <li><b>+</b> means some of the range may be missing from Porch&rsquo;s records, so the count is a minimum. Callers who hide their number aren&rsquo;t counted as senders.</li>
                <li>Days are in Pacific time.</li>
              </ul>
            </Help>
          </div>
        )}
      </div>
      {"error" in range && range.error && <p className="error" role="alert">{range.error} Showing {preset?.label.toLowerCase()} instead.</p>}
      {rows.length > 0 && range.from < historyStarts && <p className="muted">Calls, texts and phone voicemail senders only go back 90 days, to {day(historyStarts)}.</p>}

      {needs.length > 0 && (
        <section className="attn" aria-labelledby="attn-title">
          <h2 id="attn-title">Needs a look <span className="count">{needs.length}</span></h2>
          <ul>
            {needs.map(({ row, p }) => (
              <li key={row.id}>
                <span className="name">{row.bedsideName}</span>
                <span>{pill(p, true)}</span>
                <Link href={`${porches({ ...rangeQuery, ...trendsQuery, open: row.id })}#porch-${row.id}`} aria-label={`Show ${row.bedsideName}`}>Show</Link>
              </li>
            ))}
          </ul>
        </section>
      )}

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
                <details key={row.id} id={`porch-${row.id}`} className="porch" open={opened === row.id}>
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
                    <section>
                      <h3>Health</h3>
                      <ul className="checks">
                        {checks(row, now).map(check => (
                          <li key={check.label} className={check.flag ? `flag ${check.level}` : undefined}>
                            <span className={`dot ${check.level}`} aria-hidden="true" /><span className="k">{check.label}</span><span className="v">{check.value}</span>
                          </li>
                        ))}
                      </ul>
                      <p className="setup muted">{row.setUpAt ? `Set up ${day(row.setUpAt)}` : "Set up before this list"}</p>
                    </section>
                    <section>
                      <div className="acthead">
                        <h3>{preset?.label ?? dates}</h3>
                        <span className="muted subline">{contacts ? `${plural(contacts, "contact", "contacts")}, ${u.activeContacts}${activePartial(u) ? "+" : ""} active` : "No contacts"}</span>
                      </div>
                      {any ? (
                        <TrendChart labels={labels} description={`${row.bedsideName}: calls in, calls out, messages and texts ${points.seconds === 86400 ? "a day" : "a week"}, ${dates}`}
                          series={columns.map(c => ({ name: c.name, color: c.color, values: c.line(u), total: total(c.tally(u)), detail: c.detail(u) }))} />
                      ) : <p className="quiet">{unsure ? "No calls, messages or texts found, but some of this range may be missing from Porch’s records."
                        : "No calls, messages or texts in this range."}</p>}
                    </section>
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
