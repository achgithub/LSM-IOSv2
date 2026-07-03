// Global client-facing outage flag, shared with worker/'s src/outage.ts via
// the same underlying KV namespace per region (this Worker's FLAGS binding
// points at the same ID as worker/'s SCORES binding for that region) — a
// single write from worker-dash reaches every route in both Workers at once.

export const OUTAGE_KEY = "outage:flag";

export interface OutageFlag {
  on: boolean;
  message?: string;
}

export async function getOutageFlag(kv: KVNamespace): Promise<OutageFlag> {
  const raw = await kv.get(OUTAGE_KEY);
  if (!raw) return { on: false };
  try {
    const parsed = JSON.parse(raw);
    return { on: !!parsed.on, message: typeof parsed.message === "string" ? parsed.message : undefined };
  } catch {
    return { on: false };
  }
}

export async function setOutageFlag(kv: KVNamespace, on: boolean, message?: string): Promise<void> {
  await kv.put(OUTAGE_KEY, JSON.stringify({ on, message }));
}
