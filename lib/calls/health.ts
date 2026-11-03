import { callJSON } from "./server.ts";
import { config } from "../family/household.ts";
import { familyStore, type FamilyStore } from "../family/store.ts";
import { apnsAuthorization, apnsConfigured, fcmAssertion, fcmConfigured } from "../family/push.ts";

// Release verification only: no household lookup, token issuance, or phone call.
export async function callingHealth(store?: FamilyStore) {
  let androidKeyBroken = false;
  try {
    config();
    if (!apnsConfigured()) throw new Error("Push configuration missing");
    apnsAuthorization();
    // Android push is optional until Firebase is set up, but a key that's there must sign.
    const androidPushConfigured = fcmConfigured();
    if (androidPushConfigured) {
      try { fcmAssertion(); } catch (error) { androidKeyBroken = true; throw error; }
    }
    await (store ?? familyStore()).get("release-health");
    const commit = process.env.PORCH_DEPLOYMENT_COMMIT ?? process.env.VERCEL_GIT_COMMIT_SHA;
    if (!commit || !/^[a-f0-9]{40}$/.test(commit)) throw new Error("Release identity missing");
    return callJSON({ ok: true, commit, callingConfigured: true, storageReachable: true, pushConfigured: true, androidPushConfigured });
  } catch {
    // The System page says when the Firebase key is what's wrong, rather than other push setup.
    return callJSON({ ok: false, error: "The calling deployment is not ready.", ...(androidKeyBroken ? { androidPushConfigured: false } : {}) }, 503);
  }
}
