import { Hono } from "hono";

// ── Games / players / picks / predictions (v2 Layer 2) ───────────────────────
// NEW in v2: v1 kept all game state on-device, so these endpoints did not exist.
// This is the manager-facing surface — the LSM app (not the PWA) calls these.
// The PWA's player-facing submission surface lives in ./submissions.ts.
//
// SKELETON: handlers are stubbed (501) pending the multi-league shard rewrite.
// Unlike v1, `c.env.DB` here is a REGIONAL SHARD holding many leagues, so every
// query is scoped by league_id / game_id rather than relying on a per-league DB.
// See docs/lsm-v2-architecture.md §2 and worker/schema.sql (Layer 2).
export const games = new Hono<{ Bindings: Env }>();

const notImplemented = (what: string) => (c: any) =>
  c.json({ error: "not implemented", todo: what }, 501);

// Games -----------------------------------------------------------------------
// POST /games                 create a game (mode: 'lms' | 'predictor', league_id, settings)
// GET  /games                 list the manager's games
// GET  /games/:id             one game with its players
// PATCH/games/:id             rename / change status / edit settings
games.post("/", notImplemented("create game"));
games.get("/", notImplemented("list games"));
games.get("/:id", notImplemented("get game + players"));
games.patch("/:id", notImplemented("update game"));

// Players ---------------------------------------------------------------------
// POST /games/:id/players     add a player (mints a submission_token for them)
// PATCH/games/:id/players/:pid set status (eliminate, for LMS) / mark left
games.post("/:id/players", notImplemented("add player + mint token"));
games.patch("/:id/players/:pid", notImplemented("update player status"));

// Picks (LMS) -----------------------------------------------------------------
// POST /games/:id/picks       manager-typed pick (skips the queue, writes through)
// POST /games/:id/rounds/:r/resolve   resolve a round against fixtures, set results
games.post("/:id/picks", notImplemented("manager pick write-through"));
games.post("/:id/rounds/:r/resolve", notImplemented("resolve LMS round"));

// Predictions (Predictor) -----------------------------------------------------
// POST /games/:id/predictions manager-typed prediction (write-through)
// POST /games/:id/score       score finished fixtures, award points, refresh table
// GET  /games/:id/table       the running Predictor standings table
games.post("/:id/predictions", notImplemented("manager prediction write-through"));
games.post("/:id/score", notImplemented("award Predictor points"));
games.get("/:id/table", notImplemented("Predictor standings table"));
