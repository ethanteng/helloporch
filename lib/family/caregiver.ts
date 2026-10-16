import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { familyStore, type FamilyStore } from "./store.ts";
export class CaregiverAuthError extends Error { status: number; constructor(message: string, status: number) { super(message); this.status = status; } }
const digest = (value: string) => createHmac("sha256", process.env.LIVEKIT_API_SECRET ?? "").update(`porch-caregiver.${value}`).digest();
const equal = (a: string, b: string) => timingSafeEqual(digest(a), digest(b));
function legacy(code: string) {
  const expected = process.env.PORCH_CONTACT_SETUP_CODE ?? "";
  return expected.length >= 16 && expected !== process.env.PORCH_CALL_ACCESS_CODE && equal(code, expected);
}
async function save(store: FamilyStore, key: string, update: (raw: string | null) => string) {
  for (let n = 0; n < 12; n++) {
    const raw = await store.get(key), next = update(raw);
    if (raw === null ? await store.create(key, next) : await store.compareAndSet(key, raw, next)) return;
  }
  throw new CaregiverAuthError("Caregiver verification is busy. Try again.", 409);
}
export async function checkCaregiverCode(request: Request, store?: FamilyStore, now = Math.floor(Date.now() / 1000)) {
  const code = request.headers.get("X-Porch-Setup-Code") ?? "";
  // Existing long secrets remain valid for migration and recovery, never for family invitations.
  if (legacy(code)) return;
  if (!/^\d{6}$/.test(code)) throw new CaregiverAuthError("Enter your six-digit caregiver PIN.", 403);
  store ??= familyStore();
  // Global attempt reservation is atomic across instances and IPs. Five guesses per 15 minutes.
  await save(store, "security:pin-attempts", raw => {
    const current = raw ? JSON.parse(raw) : { attempts: 0, resetAt: now + 900 };
    if (current.resetAt <= now) { current.attempts = 0; current.resetAt = now + 900; }
    if (current.attempts >= 5) throw new CaregiverAuthError("Too many PIN attempts. Wait 15 minutes before trying again.", 429);
    current.attempts += 1;
    return JSON.stringify(current);
  });
  const stored = await store.get("security:caregiver-pin");
  const pin = stored ? JSON.parse(stored) : null;
  if (!pin || !equal(pin.digest, digest(`${pin.salt}.${code}`).toString("hex"))) throw new CaregiverAuthError("The caregiver PIN is incorrect.", 403);
  await save(store, "security:pin-attempts", () => JSON.stringify({ attempts: 0, resetAt: now + 900 }));
}
export async function configureCaregiverPIN(request: Request, pin: unknown, store: FamilyStore, now: number) {
  if (typeof pin !== "string" || !/^\d{6}$/.test(pin)) throw new CaregiverAuthError("Choose a six-digit caregiver PIN.", 400);
  await checkCaregiverCode(request, store, now);
  const salt = randomBytes(16).toString("hex");
  await save(store, "security:caregiver-pin", () => JSON.stringify({ salt, digest: digest(`${salt}.${pin}`).toString("hex") }));
}
