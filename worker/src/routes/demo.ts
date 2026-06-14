import { Hono } from "hono";
import { requireAdmin } from "../auth";
import {
  advanceClock,
  clearDemoClock,
  getDemoClock,
  PHASES,
  setDemoClock,
  type DemoClock,
  type DemoPhase,
} from "../demo";
import { getLeagueConfig } from "../types";

// Demo-clock control (spec testing aid). GET status is open; mutations need the
// admin bearer token.
//
//   GET  /admin/demo                       → current clock
//   POST /admin/demo/start?matchday=1      → begin demo at MD1, phase "scheduled"
//   POST /admin/demo/advance               → step scheduled→live→finished→next MD
//   POST /admin/demo/set?matchday=&phase=  → jump to an exact point
//   POST /admin/demo/stop                  → clear the clock (back to real data)
export const demo = new Hono<{ Bindings: Env }>();

demo.use("/*", async (c, next) => {
  if (c.req.method !== "GET" && !requireAdmin(c.env, c.req.header("Authorization"))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  await next();
});

demo.get("/", async (c) => {
  return c.json({ demo: await getDemoClock(c.env.SCORES) });
});

demo.post("/start", async (c) => {
  const md = Number(c.req.query("matchday") ?? "1");
  if (!Number.isInteger(md) || md < 1) {
    return c.json({ error: "matchday must be a positive integer" }, 400);
  }
  const clock: DemoClock = { matchday: md, phase: "scheduled" };
  await setDemoClock(c.env.SCORES, clock);
  return c.json({ ok: true, demo: clock });
});

demo.post("/advance", async (c) => {
  const clock = await getDemoClock(c.env.SCORES);
  if (!clock) return c.json({ error: "demo not started — call /admin/demo/start first" }, 400);
  const next = advanceClock(clock, getLeagueConfig(c.env).roundsPerSeason);
  await setDemoClock(c.env.SCORES, next);
  return c.json({ ok: true, demo: next });
});

demo.post("/set", async (c) => {
  const md = Number(c.req.query("matchday") ?? "");
  const phase = c.req.query("phase") as DemoPhase | undefined;
  if (!Number.isInteger(md) || md < 1) {
    return c.json({ error: "matchday must be a positive integer" }, 400);
  }
  if (!phase || !PHASES.includes(phase)) {
    return c.json({ error: "phase must be scheduled|live|finished" }, 400);
  }
  const clock: DemoClock = { matchday: md, phase };
  await setDemoClock(c.env.SCORES, clock);
  return c.json({ ok: true, demo: clock });
});

demo.post("/stop", async (c) => {
  await clearDemoClock(c.env.SCORES);
  return c.json({ ok: true, demo: null });
});
