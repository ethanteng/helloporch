import type { Metadata } from "next";
import { adminRequest, requireAdmin } from "../../../../../lib/admin/request.ts";
import { systemStatus } from "../../../../../lib/admin/system.ts";

export const metadata: Metadata = { title: "System" };

export default async function SystemPage() {
  const session = await requireAdmin();
  const { store } = await adminRequest();
  const status = await systemStatus(session, store);
  return (
    <>
      <h1>System</h1>
      <dl className="facts">
        <div>
          <dt>Porch numbers</dt>
          <dd>{status.numberLimit ? `${status.numbersInUse} of ${status.numberLimit}` : status.numbersInUse}</dd>
          <dd className="note">{status.numberLimit ? "Setup stops buying numbers at the limit, PORCH_MAX_PHONE_NUMBERS." : "No limit is set, so setup can't buy numbers yet. Set PORCH_MAX_PHONE_NUMBERS to allow it."}</dd>
        </div>
        <div>
          <dt>Calling server</dt>
          <dd>{status.ready ? <span className="tag good">Ready</span> : <span className="tag warn">Not ready</span>}</dd>
          <dd className="note">{status.ready ? `Calling, storage and push are configured. Release ${status.commit?.slice(0, 7)}.` : "Calling, storage or push configuration is missing. See /api/calls/health on the calling server."}</dd>
        </div>
      </dl>
    </>
  );
}
