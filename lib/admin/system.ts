import { holdersKey } from "../family/numbers.ts";
import type { FamilyStore } from "../family/store.ts";
import { callingHealth } from "../calls/health.ts";
import { assertAdmin, type AdminSession } from "./session.ts";

export type SystemStatus = { numbersInUse: number; numberLimit?: number; ready: boolean; commit?: string };

export async function systemStatus(session: AdminSession, store: FamilyStore): Promise<SystemStatus> {
  assertAdmin(session);
  const limit = Number(process.env.PORCH_MAX_PHONE_NUMBERS);
  const [holders, health] = await Promise.all([store.get(holdersKey), callingHealth(store).then(response => response.json())]);
  return { numbersInUse: (JSON.parse(holders ?? "[]") as string[]).length, ...(Number.isSafeInteger(limit) && limit >= 1 ? { numberLimit: limit } : {}),
    ready: health.ok === true, ...(typeof health.commit === "string" ? { commit: health.commit } : {}) };
}
