import type { Metadata } from "next";
import { readActivity } from "../../../../../lib/admin/activity.ts";
import { adminRequest, requireAdmin } from "../../../../../lib/admin/request.ts";
import { signOutEverywhereAction } from "../../actions";
import { when } from "../../_ui/format";

export const metadata: Metadata = { title: "Activity" };

export default async function ActivityPage() {
  const session = await requireAdmin();
  const { store } = await adminRequest();
  const entries = await readActivity(session, store);
  return (
    <>
      <h1>Activity</h1>
      <p className="lead">Everything done on the admin page, newest first. The last 500 entries are kept.</p>
      {entries.length ? (
        <ol className="log">
          {entries.map((entry, index) => (
            <li key={`${entry.at}-${index}`}><time>{when(entry.at)}</time> {entry.action}{entry.detail && <>: <strong>{entry.detail}</strong></>}</li>
          ))}
        </ol>
      ) : <p className="empty">Nothing yet.</p>}
      <h2>Sessions</h2>
      <p>Each sign-in lasts 12 hours. Signing out everywhere ends every session, including this one. So does changing the password.</p>
      <form action={signOutEverywhereAction}><button type="submit" className="secondary">Sign out everywhere</button></form>
    </>
  );
}
