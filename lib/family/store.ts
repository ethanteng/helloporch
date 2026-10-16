// Shared, persistent state. No process-memory fallback is used in production.
export interface FamilyStore {
  get(key: string): Promise<string | null>;
  create(key: string, value: string, seconds?: number): Promise<boolean>;
  compareAndSet(key: string, previous: string, value: string): Promise<boolean>;
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
  async compareAndSet(key: string, previous: string, value: string) {
    return await this.command(["EVAL", "if redis.call('GET',KEYS[1]) ~= ARGV[1] then return 0 end redis.call('SET',KEYS[1],ARGV[2]); return 1", 1, this.prefix + key, previous, value]) === 1;
  }
}

export function familyStore(): FamilyStore {
  const url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN;
  if (!url || !token || !url.startsWith("https://")) throw new Error("Family storage not configured");
  return new RedisFamilyStore(url, token, process.env.PORCH_FAMILY_STORE_PREFIX ?? "porch:family:v1:");
}
