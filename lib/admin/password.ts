import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";

/** The admin password is kept only as a scrypt hash, in `PORCH_ADMIN_PASSWORD_HASH`: `scrypt:N:r:p:salt:key`, with the
 * salt and key in base64url. `scripts/admin-password.mjs` makes one. Colons, not `$`, so a `.env` file can't expand it. */
export const minimumPasswordLength = 15;
export const maximumPasswordLength = 1024;
type Cost = { N: number; r: number; p: number };
const standardCost: Cost = { N: 32768, r: 8, p: 1 };

function derive(password: string, salt: Buffer, cost: Cost) {
  return new Promise<Buffer>((resolve, reject) => scrypt(password.normalize("NFKC"), salt, 32, { ...cost, maxmem: 256 * cost.N * cost.r },
    (error, key) => error ? reject(error) : resolve(key)));
}
function parse(stored: string) {
  const parts = stored.split(":");
  if (parts.length !== 6 || parts[0] !== "scrypt") return undefined;
  const [N, r, p] = parts.slice(1, 4).map(Number);
  // Within what a server can work out quickly, so a bad setting can't stall sign-in.
  if (![N, r, p].every(Number.isSafeInteger) || N < 1024 || N > 131072 || (N & (N - 1)) !== 0 || r < 1 || r > 16 || p < 1 || p > 4) return undefined;
  const salt = Buffer.from(parts[4], "base64url"), key = Buffer.from(parts[5], "base64url");
  return salt.length >= 16 && key.length === 32 ? { cost: { N, r, p }, salt, key } : undefined;
}

export async function hashPassword(password: string, cost = standardCost) {
  const salt = randomBytes(16);
  const key = await derive(password, salt, cost);
  return ["scrypt", cost.N, cost.r, cost.p, salt.toString("base64url"), key.toString("base64url")].join(":");
}
export const validPasswordHash = (stored: string | undefined): stored is string => !!stored && !!parse(stored);
export async function checkPassword(password: string, stored: string) {
  const parsed = parse(stored);
  if (!parsed || password.length > maximumPasswordLength) return false;
  return timingSafeEqual(await derive(password, parsed.salt, parsed.cost), parsed.key);
}
