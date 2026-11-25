import type { Member } from "./household.ts";

/** A family phone's Do Not Disturb, as its newest check-in said (see `noteDoNotDisturb`). `on`: until they turn it off.
 * `hours`: every day from `start` until `end`, whole hours on the phone's own clock in `timeZone`. A start after the end
 * runs past midnight, and the same hour for both is all day, as the bedside's message hours are.
 * While it applies, Porch calls don't ring the phone: the bedside offers to leave a message instead, never their regular
 * phone, nobody on a call can ring them in, and the notice of a message comes quietly. Their own calls still go out. */
export type DoNotDisturb = { on: boolean; hours?: { start: number; end: number }; timeZone?: string };

/** The `errorCode` of a call the bedside can't make because of it, which the bedside answers by offering a message. */
export const doNotDisturbCode = "doNotDisturb";

const hourOf = (value: unknown): value is number => Number.isInteger(value) && (value as number) >= 0 && (value as number) <= 23;

/** One per time zone: every check-in by the bedside asks about each family member. */
const formatters = new Map<string, Intl.DateTimeFormat>();
/** The hour of the day, 0–23, at `now` in an IANA time zone such as "America/Los_Angeles", or nothing for one this
 * server doesn't know. */
function hourIn(timeZone: string, now: number): number | undefined {
  try {
    let formatter = formatters.get(timeZone);
    if (!formatter) {
      formatter = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hourCycle: "h23" });
      if (formatters.size < 1000) formatters.set(timeZone, formatter);
    }
    const parts = formatter.formatToParts(new Date(now * 1000));
    const hour = Number(parts.find(part => part.type === "hour")?.value);
    return hourOf(hour) ? hour : undefined;
  } catch { return undefined; }
}

/** What a check-in says, or nothing when it doesn't say or says it wrong. Hours need a time zone this server knows. */
function parse(value: unknown): DoNotDisturb | undefined {
  if (value === null || typeof value !== "object") return undefined;
  const { on, hours, timeZone } = value as Record<string, unknown>;
  if (typeof on !== "boolean") return undefined;
  if (hours === undefined || hours === null) return { on };
  if (typeof hours !== "object") return undefined;
  const { start, end } = hours as Record<string, unknown>;
  if (!hourOf(start) || !hourOf(end)) return undefined;
  if (typeof timeZone !== "string" || timeZone.length > 64 || hourIn(timeZone, 0) === undefined) return undefined;
  return { on, hours: { start, end }, timeZone };
}

/** A family phone's check-in carries its Do Not Disturb, which is kept as it says, and forgotten once it's all off. A
 * check-in that doesn't say, such as from an app from before Do Not Disturb, or one that says it wrong, changes nothing,
 * so a poll never fails over it. The caller passes only the newest check-in, as for availability. */
export function noteDoNotDisturb(member: Member, value: unknown) {
  if (member.role !== "family") return;
  const setting = parse(value);
  if (!setting) return;
  if (!setting.on && !setting.hours) delete member.doNotDisturb;
  else member.doNotDisturb = setting;
}

/** Whether Porch calls shouldn't ring this family member now. */
export function inDoNotDisturb(member: Member, now: number): boolean {
  const setting = member.doNotDisturb;
  if (!setting || member.role !== "family") return false;
  if (setting.on) return true;
  if (!setting.hours || !setting.timeZone) return false;
  const { start, end } = setting.hours;
  if (start === end) return true;
  const hour = hourIn(setting.timeZone, now);
  if (hour === undefined) return false;
  return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}
