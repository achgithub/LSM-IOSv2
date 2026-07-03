// Global client-facing outage flag — NOT to be confused with the nightly
// data-sync "maintenance" cron (sync.ts:runMaintenance, MAINTENANCE_WINDOW_UTC).
// This flag exists purely to tell every client "the service is deliberately
// down right now", independent of that unrelated data-refresh job.
//
// Single KV key, shared by both this Worker (SCORES binding) and worker-api/
// (FLAGS binding, pointing at the same underlying namespace per region) — one
// write from worker-dash reaches every deployment in that region.

import type { Context, Next } from "hono";

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

const DEFAULT_MESSAGE = "We're doing scheduled maintenance — back shortly.";

// Hono middleware: mounted first, ahead of every route. /health and /admin/*
// always bypass it, so ops tooling and the toggle itself never lock out.
export async function outageGate(c: Context<{ Bindings: Env }>, next: Next) {
  if (c.req.path === "/health" || c.req.path.startsWith("/admin")) return next();

  const flag = await getOutageFlag(c.env.SCORES);
  if (flag.on) return c.json({ error: "maintenance", message: flag.message ?? DEFAULT_MESSAGE }, 503);

  return next();
}
