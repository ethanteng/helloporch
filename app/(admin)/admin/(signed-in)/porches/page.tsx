import type { Metadata } from "next";
import { listPorches, type PorchRow } from "../../../../../lib/admin/porches.ts";
import { adminRequest, requireAdmin } from "../../../../../lib/admin/request.ts";
import { ago, day } from "../../_ui/format";

export const metadata: Metadata = { title: "Porches" };

// A bedside that hasn't checked in for a day is likely off, unplugged or offline.
const offlineAfter = 86400;
const phoneNumber = (number: string) => number.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");

function seen(row: PorchRow, now: number) {
  if (row.lastSeenAt === undefined) return <span className="muted">Never</span>;
  if (now - row.lastSeenAt > offlineAfter) return <span className="tag warn">Offline for {Math.floor((now - row.lastSeenAt) / 86400)} days</span>;
  return ago(row.lastSeenAt, now);
}

export default async function PorchesPage() {
  const session = await requireAdmin();
  const { store, now } = await adminRequest();
  const rows = await listPorches(session, store);
  return (
    <>
      <h1>Porches</h1>
      <p className="lead">Every household, ours included. Messages, family names, keypads and calls stay private to each family.</p>
      {rows.length ? (
        <div className="table">
          <table>
            <thead><tr><th>Porch for</th><th>Porch number</th><th>Set up</th><th>Bedside last seen</th><th>Family phones</th><th>Setup</th></tr></thead>
            <tbody>
              {rows.map(row => (
                <tr key={row.id}>
                  <td title={row.id}>{row.bedsideName}{row.invitationLabel && <span className="sub">{row.invitationLabel}</span>}</td>
                  <td>{row.porchNumber ? phoneNumber(row.porchNumber) : row.numberPending ? <span className="muted">Being set up</span> : <span className="muted">None</span>}</td>
                  <td>{row.setUpAt ? day(row.setUpAt) : <span className="muted">Before this list</span>}</td>
                  <td>{seen(row, now)}</td>
                  <td>{row.familyPhones}</td>
                  <td>{row.setupFinished ? <span className="tag good">Finished</span> : <span className="tag warn">Not finished</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <p className="empty">No Porches yet.</p>}
    </>
  );
}
