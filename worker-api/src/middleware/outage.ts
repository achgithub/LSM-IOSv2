// Hono middleware: 503s every route except /health and /admin/* when the
// global outage flag is on. See ../outage.ts.

import type { Context, Next } from "hono";
import { getOutageFlag } from "../outage";

const DEFAULT_MESSAGE = "We're doing scheduled maintenance — back shortly.";

export async function outageGate(c: Context<{ Bindings: Env }>, next: Next) {
  if (c.req.path === "/health" || c.req.path.startsWith("/admin")) return next();

  const flag = await getOutageFlag(c.env.FLAGS);
  if (flag.on) return c.json({ error: "maintenance", message: flag.message ?? DEFAULT_MESSAGE }, 503);

  return next();
}
