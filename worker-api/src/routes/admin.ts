// Admin — ops endpoints for this authority Worker.
//   GET  /admin/outage
//   POST /admin/outage?value=on|off&message=...
//   GET  /admin/cleanup-preview?days=N   — dry run, deletes nothing
//   Authorization: Bearer <ADMIN_TOKEN>

import { Hono } from "hono";
import { requireAdmin } from "../auth";
import { getOutageFlag, setOutageFlag } from "../outage";
import { DEFAULT_RETENTION_DAYS, previewStaleData } from "../retention";

export const admin = new Hono<{ Bindings: Env }>();

admin.get("/outage", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);
  return c.json(await getOutageFlag(c.env.FLAGS));
});

admin.post("/outage", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);
  const value = c.req.query("value");
  if (value !== "on" && value !== "off") return c.json({ error: "value must be on|off" }, 400);
  const message = c.req.query("message");
  await setOutageFlag(c.env.FLAGS, value === "on", message ?? undefined);
  return c.json({ ok: true, ...(await getOutageFlag(c.env.FLAGS)) });
});

// Dry-run only — runs the exact same WHERE clauses the real cleanup cron
// uses, but never deletes anything. `days` lets you measure the blast radius
// at different retention windows (e.g. ?days=45 or ?days=60) before trusting
// the default.
admin.get("/cleanup-preview", async (c) => {
  if (!requireAdmin(c.env, c.req.header("Authorization"))) return c.json({ error: "unauthorized" }, 401);
  const daysParam = c.req.query("days");
  const days = daysParam ? parseInt(daysParam, 10) : DEFAULT_RETENTION_DAYS;
  if (!Number.isFinite(days) || days < 0) return c.json({ error: "days must be a non-negative number" }, 400);
  return c.json(await previewStaleData(c.env, days));
});
