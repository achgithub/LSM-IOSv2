// Admin — ops endpoints for this authority Worker.
//   GET  /admin/outage
//   POST /admin/outage?value=on|off&message=...
//   Authorization: Bearer <ADMIN_TOKEN>

import { Hono } from "hono";
import { requireAdmin } from "../auth";
import { getOutageFlag, setOutageFlag } from "../outage";

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
