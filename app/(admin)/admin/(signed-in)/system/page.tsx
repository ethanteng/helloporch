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
          <dd className="note">{status.ready ? `Calling, storage and Apple push are configured. Release ${status.commit?.slice(0, 7)}.`
            : status.androidPush === false ? "The Firebase key doesn't work, so release checks fail until it's fixed."
            : "Calling, storage or Apple push configuration is missing. See /api/calls/health on the calling server."}</dd>
        </div>
        {status.androidPush !== undefined && (
          <div>
            <dt>Android push</dt>
            <dd>{status.androidPush ? <span className="tag good">Ready</span> : <span className="tag warn">{status.ready ? "Not set up" : "Key doesn't work"}</span>}</dd>
            <dd className="note">{status.androidPush ? "Android phones and tablets can be rung when Porch isn't open."
              : status.ready ? "Android devices ring only while Porch is open. Add FCM_PROJECT_ID, FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY from a Firebase service account."
              : "FCM_PRIVATE_KEY can't sign. Copy private_key from the service account's JSON key again."}</dd>
          </div>
        )}
      </dl>
    </>
  );
}
