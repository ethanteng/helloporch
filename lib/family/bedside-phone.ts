import { isCaregiver, type Household } from "./household.ts";

/** How the bedside's desk phone reaches it: a Cell2Jack it talks to itself (Porch's driver on an iPad with an M chip,
 * or USB on an Android tablet), or the Porch phone adapter, which an iPad sees as a keyboard. The adapter knows whether
 * its Cell2Jack answers but doesn't tell the iPad, so through it Porch only knows whether the adapter is plugged in. */
export type BedsidePhoneKind = "cell2jack" | "adapter";
/** The desk phone as the bedside last reported it (see `notePhone`). `since`: when it last went in or out, or when it
 * was seen out again after a gap. `reportedAt`: the newest report. `noticedAt`: when caregivers were told it's out, once
 * it had been for `phoneNoticeAfter`, and `notified`: which of them got that notification, so only they hear it's back. */
export type BedsidePhone = { kind: BedsidePhoneKind; connected: boolean; since: number; reportedAt?: number; noticedAt?: number; notified?: string[] };
/** What the bedside sends with each check-in: its phone, or null when no phone is set up there. */
export type BedsidePhoneReport = { kind: BedsidePhoneKind; connected: boolean } | null;
/** A notice to send once a check-in is saved: the phone has been out long enough, or it's back after one was sent. */
export type PhoneNotice = { state: "out" } | { state: "back"; to: string[]; outFor: number };

/** Long enough that a quick replug, or the few seconds the Cell2Jack takes to answer when Porch opens, says nothing. */
export const phoneNoticeAfter = 600;
/** The bedside reports every few seconds while Porch is on screen and nothing otherwise. Reports further apart than this
 * left a time Porch couldn't see, when the phone may have been plugged back in, so the clock starts again. */
export const phoneReportGap = 60;

export function bedsidePhoneReport(value: unknown): BedsidePhoneReport | undefined {
  if (value === null) return null;
  if (!value || typeof value !== "object") return undefined;
  const { kind, connected } = value as Record<string, unknown>;
  if ((kind !== "cell2jack" && kind !== "adapter") || typeof connected !== "boolean") return undefined;
  return { kind, connected };
}

/** Keeps the bedside's report of its phone. A phone that goes out starts the clock; after `phoneNoticeAfter` of reports
 * that it's still out, caregivers are told once. A gap in the reports, as while Porch was off screen, starts the clock
 * again: the phone may have been back meanwhile. When it's back, the caregivers who were told hear that too. No phone set
 * up there, as when a caregiver turned the phone keypad off, forgets it all. */
export function notePhone(house: Household, report: BedsidePhoneReport, now: number): PhoneNotice | undefined {
  if (!report) { delete house.bedsidePhone; return undefined; }
  const current = house.bedsidePhone;
  if (!current || current.connected !== report.connected) {
    house.bedsidePhone = { kind: report.kind, connected: report.connected, since: now, reportedAt: now };
    if (!current?.noticedAt || !report.connected) return undefined;
    const caregivers = new Set(house.members.filter(m => !m.revoked && m.role === "family" && isCaregiver(m)).map(m => m.id));
    const to = (current.notified ?? []).filter(id => caregivers.has(id));
    return to.length ? { state: "back", to, outFor: now - current.since } : undefined;
  }
  const gap = now - (current.reportedAt ?? current.since);
  current.kind = report.kind; current.reportedAt = now;
  if (!current.connected && current.noticedAt === undefined && gap > phoneReportGap) { current.since = now; return undefined; }
  if (!current.connected && current.noticedAt === undefined && now - current.since >= phoneNoticeAfter) {
    current.noticedAt = now;
    current.notified = house.members.filter(m => !m.revoked && m.role === "family" && m.caregiver && m.alerts).map(m => m.id);
    return { state: "out" };
  }
  return undefined;
}

/** The phone that's been out long enough to tell caregivers, as their phones show it: since when, and how it's plugged
 * in, so the steps to check match. */
export function publicBedsidePhone(house: Household) {
  const phone = house.bedsidePhone;
  if (!phone || phone.connected || phone.noticedAt === undefined) return undefined;
  return { since: phone.since, kind: phone.kind };
}

/** "25 minutes", "3 hours", "2 days": roughly how long, for a notice. */
export function roughly(seconds: number) {
  const minutes = Math.max(1, Math.round(seconds / 60));
  if (minutes < 60) return `${minutes} ${minutes === 1 ? "minute" : "minutes"}`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `${hours} ${hours === 1 ? "hour" : "hours"}`;
  return `${Math.round(hours / 24)} days`;
}
