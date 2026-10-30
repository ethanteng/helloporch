// Shared, persistent state. No process-memory fallback is used in production.
export interface FamilyStore {
  get(key: string): Promise<string | null>;
  create(key: string, value: string, seconds?: number): Promise<boolean>;
  /** `seconds`, when given, is how long the new value lives, as for `create`. */
  compareAndSet(key: string, previous: string, value: string, seconds?: number): Promise<boolean>;
}

export class RedisFamilyStore implements FamilyStore {
  private url: string; private token: string; private prefix: string;
  constructor(url: string, token: string, prefix = "porch:family:v1:") { this.url = url; this.token = token; this.prefix = prefix; }
  private async command(args: (string | number)[]) {
    const response = await fetch(this.url, { method: "POST", headers: { Authorization: `Bearer ${this.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(args), signal: AbortSignal.timeout(8000), cache: "no-store" });
    const body = await response.json();
    if (!response.ok || body.error) throw new Error("Family storage unavailable");
    return body.result;
  }
  async get(key: string): Promise<string | null> { return this.command(["GET", this.prefix + key]); }
  async create(key: string, value: string, seconds?: number) {
    return await this.command(["SET", this.prefix + key, value, "NX", ...(seconds ? ["EX", seconds] : [])]) === "OK";
  }
  async compareAndSet(key: string, previous: string, value: string, seconds?: number) {
    if (seconds) return await this.command(["EVAL", "if redis.call('GET',KEYS[1]) ~= ARGV[1] then return 0 end redis.call('SET',KEYS[1],ARGV[2],'EX',ARGV[3]); return 1", 1, this.prefix + key, previous, value, seconds]) === 1;
    return await this.command(["EVAL", "if redis.call('GET',KEYS[1]) ~= ARGV[1] then return 0 end redis.call('SET',KEYS[1],ARGV[2]); return 1", 1, this.prefix + key, previous, value]) === 1;
  }
}

export function familyStore(): FamilyStore {
  const url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN;
  if (!url || !token || !url.startsWith("https://")) throw new Error("Family storage not configured");
  return new RedisFamilyStore(url, token, process.env.PORCH_FAMILY_STORE_PREFIX ?? "porch:family:v1:");
}

/** Changes the JSON value at `key`, starting from `empty` when there's none, and retries when another request changed it
 * first. `change` returns the new value, or `undefined` to leave it as it is. `seconds`, when given, is how long the
 * saved value lives. */
export async function updateJSON<T>(store: FamilyStore, key: string, empty: T, change: (value: T) => T | undefined, seconds?: number): Promise<T> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const raw = await store.get(key);
    const value: T = raw === null ? empty : JSON.parse(raw);
    const updated = change(value);
    if (updated === undefined) return value;
    const saved = JSON.stringify(updated);
    if (raw === null ? await store.create(key, saved, seconds) : await store.compareAndSet(key, raw, saved, seconds)) return updated;
  }
  throw new Error("Porch is busy. Please try again.");
}
