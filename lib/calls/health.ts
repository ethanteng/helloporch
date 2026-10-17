import { callJSON } from "./server.ts";
import { config } from "../family/household.ts";
import { familyStore, type FamilyStore } from "../family/store.ts";
import { apnsAuthorization, voipConfigured } from "../family/push.ts";

// Release verification only: no household lookup, token issuance, or phone call.
export async function callingHealth(store?: FamilyStore) {
  try {
    config();
    if (!voipConfigured()) throw new Error("Push configuration missing");
    apnsAuthorization();
    await (store ?? familyStore()).get("release-health");
    const commit = process.env.PORCH_DEPLOYMENT_COMMIT ?? process.env.VERCEL_GIT_COMMIT_SHA;
    if (!commit || !/^[a-f0-9]{40}$/.test(commit)) throw new Error("Release identity missing");
    return callJSON({ ok: true, commit, callingConfigured: true, storageReachable: true, pushConfigured: true });
  } catch {
    return callJSON({ ok: false, error: "The calling deployment is not ready." }, 503);
  }
}
