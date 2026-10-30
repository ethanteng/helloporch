import type { Metadata } from "next";
import { listInvitations, type InvitationRow } from "../../../../lib/admin/invitations.ts";
import { adminRequest, requireAdmin } from "../../../../lib/admin/request.ts";
import { day } from "../_ui/format";
import InvitationActions from "../_ui/InvitationActions";
import InvitationForm from "../_ui/InvitationForm";
import { InvitationLinks, LatestLink } from "../_ui/Links";

export const metadata: Metadata = { title: "Invitations" };

function status(row: InvitationRow) {
  if (row.state === "set up") return <span className="tag good">Set up {row.setUpAt ? day(row.setUpAt) : ""}</span>;
  if (row.state === "waiting") return <span className="tag">Waiting · until {day(row.expiresAt)}</span>;
  if (row.state === "expired") return <span className="tag muted">Expired {day(row.expiresAt)}</span>;
  return <span className="tag muted">Cancelled</span>;
}

export default async function InvitationsPage() {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  const rows = await listInvitations(session, store, now);
  const waiting = rows.filter(row => row.state === "waiting").map(row => row.id);
  return (
    <InvitationLinks waiting={waiting}>
      <h1>Invite a new family</h1>
      <p className="lead">Type who it&apos;s for. You get a private link to send them by text or email. It sets up one bedside iPad and works for 14 days.</p>
      <InvitationForm />
      <LatestLink />
      <h2>Invitations</h2>
      {rows.length ? (
        <div className="table">
          <table>
            <thead><tr><th>For</th><th>Status</th><th>Made</th><th><span className="visually-hidden">Actions</span></th></tr></thead>
            <tbody>
              {rows.map(row => (
                <tr key={row.id}>
                  <td>{row.label}</td>
                  <td>{status(row)}</td>
                  <td>{day(row.createdAt)}</td>
                  <td className="actions"><InvitationActions id={row.id} state={row.state} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <p className="empty">No invitations yet.</p>}
    </InvitationLinks>
  );
}
