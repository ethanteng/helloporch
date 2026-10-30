// Times show in Pacific time, where the admin page is used.
const dateTime = new Intl.DateTimeFormat("en-US", { timeZone: "America/Los_Angeles", month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" });
const date = new Intl.DateTimeFormat("en-US", { timeZone: "America/Los_Angeles", month: "short", day: "numeric", year: "numeric" });
export const when = (seconds: number) => dateTime.format(new Date(seconds * 1000));
export const day = (seconds: number) => date.format(new Date(seconds * 1000));
export function ago(seconds: number, now: number) {
  const elapsed = Math.max(0, now - seconds);
  if (elapsed < 120) return "just now";
  if (elapsed < 7200) return `${Math.floor(elapsed / 60)} minutes ago`;
  if (elapsed < 172800) return `${Math.floor(elapsed / 3600)} hours ago`;
  return `${Math.floor(elapsed / 86400)} days ago`;
}
