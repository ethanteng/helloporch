/** A signed-in admin, made only by `auth.ts` after checking the session cookie or the password. Every admin page and
 * action needs one, so nothing that reads or changes households runs for someone signed out. */
export class AdminSession {
  readonly key: string; readonly raw: string; readonly expiresAt: number;
  private constructor(key: string, raw: string, expiresAt: number) { this.key = key; this.raw = raw; this.expiresAt = expiresAt; }
  /** For `auth.ts` only. */
  static issue(key: string, raw: string, expiresAt: number) { const session = new AdminSession(key, raw, expiresAt); issued.add(session); return session; }
}
const issued = new WeakSet<AdminSession>();

export class AdminError extends Error {
  status: number;
  constructor(message: string, status = 400) { super(message); this.status = status; }
}
export function assertAdmin(session: AdminSession) {
  if (!issued.has(session)) throw new AdminError("Sign in first.", 401);
}
