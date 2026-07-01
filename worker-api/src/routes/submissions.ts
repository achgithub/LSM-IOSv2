import { Hono } from "hono";
import { cors } from "hono/cors";

// ── Submissions (the anonymous PWA approval queue) — Phase 5 ─────────────────
//
// Phase 4: one global token per player (was per-game-player).
// Phase 5: joker support for Predictor; manager_suffix on enrollments so the
// PWA can identify which manager owns each game, and the iOS app can validate
// approvals against the local manager UUID.
//
// Two audiences:
//
//   PLAYER (PWA, anonymous) — /s/:token. GET returns all active games with
//   jokerEnabled and managerSuffix per game. POST /s/:token/games/:gameToken
//   submits for one specific game (LMS: {teamId}, Predictor: {scores, jokerFixtureId?}).
//
//   MANAGER (LSM app) — mints tokens per roster member, pushes rounds,
//   reviews queues, approves/rejects. Revoke kills the token everywhere.

export const submissions = new Hono<{ Bindings: Env }>();

// CORS for player-facing PWA routes (cross-origin from submit.sportsmanager.site)
submissions.use("/s/*", cors({
  origin: "https://submit.sportsmanager.site",
  allowMethods: ["GET", "POST", "OPTIONS"],
  allowHeaders: ["Content-Type"],
}));

// ─── helpers ─────────────────────────────────────────────────────────────────

function now(): string {
  return new Date().toISOString();
}

async function ensureManagerLifecycle(env: Env, managerToken: string): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO manager_lifecycle (manager_token, created_at) VALUES (?, ?)`
  ).bind(managerToken, new Date().toISOString()).run();
}

// ─── Manager-facing ──────────────────────────────────────────────────────────

// POST /links
// Mint a global player token. Returns 409 if a non-revoked token already exists
// for this player name — prevents credential harvesting by unauthenticated callers.
submissions.post("/links", async (c) => {
  const body = await c.req.json<{ playerName: string; managerToken?: string; managerName?: string }>();
  const playerName = body?.playerName?.trim();
  if (!playerName) return c.json({ error: "playerName is required" }, 400);

  const existing = await c.env.DB.prepare(
    `SELECT 1 FROM player_tokens WHERE player_name = ? AND revoked_at IS NULL LIMIT 1`
  ).bind(playerName).first();

  if (existing) return c.json({ error: "A submission link already exists for this player. Revoke it first, then create a new one." }, 409);

  const token = crypto.randomUUID().toLowerCase();
  const managerToken = body?.managerToken?.toLowerCase() ?? null;
  const managerName = body?.managerName?.trim() ?? null;
  await c.env.DB.prepare(
    `INSERT INTO player_tokens (token, player_name, manager_name, created_at, manager_token) VALUES (?, ?, ?, ?, ?)`
  ).bind(token, playerName, managerName, now(), managerToken).run();

  if (managerToken) await ensureManagerLifecycle(c.env, managerToken);

  return c.json({ token });
});

// POST /links/:token/revoke
submissions.post("/links/:token/revoke", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const result = await c.env.DB.prepare(
    `UPDATE player_tokens SET revoked_at = ? WHERE token = ? AND revoked_at IS NULL`
  ).bind(now(), token).run();
  if (result.meta.changes === 0) return c.json({ error: "token not found or already revoked" }, 404);
  return c.json({ ok: true });
});

// POST /games/:gameToken/push
// Upsert the open round and (re)enroll every player who has a token.
// Body: { mode, roundNumber, deadline?, gameName?, fixtures, jokerEnabled?, managerSuffix?, players }
submissions.post("/games/:gameToken/push", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  // fixtureId/opponentName are set when a team plays twice in the round
  // (rearranged fixtures) — disambiguates which fixture occurrence this is.
  interface EligibleTeam { id: number; name: string; fixtureId?: number; opponentName?: string }
  interface PushPlayer {
    token: string;
    localPlayerId: string;
    eligibleTeams?: EligibleTeam[] | null;
  }
  const body = await c.req.json<{
    mode: string;
    roundNumber: number;
    deadline?: string | null;
    gameName?: string | null;
    fixtures: unknown[];
    jokerEnabled?: boolean;
    managerSuffix?: string | null;
    managerName?: string | null;
    managerToken?: string | null;
    players: PushPlayer[];
  }>();
  const { mode, roundNumber, deadline, gameName, fixtures, jokerEnabled, managerSuffix, managerName, managerToken, players } = body ?? {};
  if (!mode || roundNumber == null || !Array.isArray(fixtures)) {
    return c.json({ error: "mode, roundNumber, and fixtures are required" }, 400);
  }

  const ts = now();
  const mgrToken = managerToken?.toLowerCase() ?? null;

  await c.env.DB.prepare(
    `INSERT INTO round_pushes (game_token, mode, round_number, deadline, game_name, fixtures_json, joker_enabled, manager_token, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (game_token) DO UPDATE SET
       mode = excluded.mode,
       round_number = excluded.round_number,
       deadline = excluded.deadline,
       game_name = excluded.game_name,
       fixtures_json = excluded.fixtures_json,
       joker_enabled = excluded.joker_enabled,
       manager_token = COALESCE(round_pushes.manager_token, excluded.manager_token),
       updated_at = excluded.updated_at`
  ).bind(gameToken, mode, roundNumber, deadline ?? null, gameName ?? null, JSON.stringify(fixtures), jokerEnabled ? 1 : 0, mgrToken, ts).run();

  if (mgrToken) await ensureManagerLifecycle(c.env, mgrToken);

  // Prune submissions older than 2 rounds (aligned with Predictor publish retention).
  if (roundNumber > 2) {
    await c.env.DB.prepare(
      `DELETE FROM submissions WHERE game_token = ? AND round_number < ?`
    ).bind(gameToken, roundNumber - 2).run();
  }

  const suffix = managerSuffix?.toLowerCase() ?? null;
  const mgrName = managerName?.trim() ?? null;

  if (Array.isArray(players)) {
    for (const p of players) {
      const tk = p.token.toLowerCase();
      const pid = p.localPlayerId.toLowerCase();
      const eligJson = p.eligibleTeams != null ? JSON.stringify(p.eligibleTeams) : null;
      const exists = await c.env.DB.prepare(
        `SELECT 1 FROM player_tokens WHERE token = ? AND revoked_at IS NULL`
      ).bind(tk).first();
      if (!exists) continue;

      await c.env.DB.prepare(
        `INSERT INTO game_enrollments (token, game_token, local_player_id, eligible_team_ids_json, manager_suffix)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (token, game_token) DO UPDATE SET
           local_player_id = excluded.local_player_id,
           eligible_team_ids_json = excluded.eligible_team_ids_json,
           manager_suffix = excluded.manager_suffix`
      ).bind(tk, gameToken, pid, eligJson, suffix).run();

      if (mgrName) {
        await c.env.DB.prepare(
          `UPDATE player_tokens SET manager_name = ? WHERE token = ?`
        ).bind(mgrName, tk).run();
      }
    }
  }

  return c.json({ ok: true });
});

// GET /games/:gameToken/submissions?round=N
submissions.get("/games/:gameToken/submissions", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const round = c.req.query("round");

  let rows;
  if (round) {
    const rn = parseInt(round, 10);
    rows = await c.env.DB.prepare(
      `SELECT s.id, s.token, pt.player_name, ge.local_player_id, ge.manager_suffix,
              s.round_number, s.payload_json, s.status, s.submitted_at, s.decided_at
       FROM submissions s
       JOIN game_enrollments ge ON ge.token = s.token AND ge.game_token = s.game_token
       JOIN player_tokens pt ON pt.token = s.token
       WHERE s.game_token = ? AND s.round_number = ?
       ORDER BY s.submitted_at ASC`
    ).bind(gameToken, rn).all();
  } else {
    rows = await c.env.DB.prepare(
      `SELECT s.id, s.token, pt.player_name, ge.local_player_id, ge.manager_suffix,
              s.round_number, s.payload_json, s.status, s.submitted_at, s.decided_at
       FROM submissions s
       JOIN game_enrollments ge ON ge.token = s.token AND ge.game_token = s.game_token
       JOIN player_tokens pt ON pt.token = s.token
       WHERE s.game_token = ?
       ORDER BY s.submitted_at ASC`
    ).bind(gameToken).all();
  }

  return c.json({
    submissions: (rows.results ?? []).map((r: any) => ({
      id: r.id,
      token: r.token,
      playerName: r.player_name,
      localPlayerId: r.local_player_id,
      managerSuffix: r.manager_suffix,
      roundNumber: r.round_number,
      payload: JSON.parse(r.payload_json as string),
      status: r.status,
      submittedAt: r.submitted_at,
      decidedAt: r.decided_at,
    })),
  });
});

// POST /games/:gameToken/submissions/:id/approve
submissions.post("/games/:gameToken/submissions/:id/approve", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const id = c.req.param("id").toLowerCase();
  const ts = now();
  const result = await c.env.DB.prepare(
    `UPDATE submissions SET status = 'approved', decided_at = ?
     WHERE id = ? AND game_token = ? AND status = 'pending'`
  ).bind(ts, id, gameToken).run();
  if (result.meta.changes === 0) return c.json({ error: "submission not found or already decided" }, 404);

  const row = await c.env.DB.prepare(
    `SELECT s.id, ge.local_player_id, ge.manager_suffix, s.round_number, s.payload_json
     FROM submissions s
     JOIN game_enrollments ge ON ge.token = s.token AND ge.game_token = s.game_token
     WHERE s.id = ? AND s.game_token = ?`
  ).bind(id, gameToken).first<any>();

  if (!row) return c.json({ error: "not found after update" }, 500);
  return c.json({
    id: row.id,
    localPlayerId: row.local_player_id,
    managerSuffix: row.manager_suffix,
    roundNumber: row.round_number,
    payload: JSON.parse(row.payload_json),
  });
});

// POST /games/:gameToken/submissions/:id/reject
submissions.post("/games/:gameToken/submissions/:id/reject", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const id = c.req.param("id").toLowerCase();
  const ts = now();
  const result = await c.env.DB.prepare(
    `UPDATE submissions SET status = 'rejected', decided_at = ?
     WHERE id = ? AND game_token = ? AND status = 'pending'`
  ).bind(ts, id, gameToken).run();
  if (result.meta.changes === 0) return c.json({ error: "submission not found or already decided" }, 404);
  return c.json({ ok: true });
});

// ─── Player-facing (PWA) ─────────────────────────────────────────────────────

// GET /s/:token
// Returns all active games for this player. Each game includes jokerEnabled and
// managerSuffix so the PWA can display identity and render the joker control.
submissions.get("/s/:token", async (c) => {
  const token = c.req.param("token").toLowerCase();

  const pt = await c.env.DB.prepare(
    `SELECT token, player_name, manager_name, revoked_at FROM player_tokens WHERE token = ?`
  ).bind(token).first<any>();

  if (!pt) return c.json({ error: "Link not found." }, 404);
  if (pt.revoked_at) return c.json({ error: "This link has been revoked." }, 404);

  const enrollments = await c.env.DB.prepare(
    `SELECT ge.game_token, ge.eligible_team_ids_json, ge.manager_suffix,
            rp.mode, rp.round_number, rp.deadline, rp.game_name, rp.fixtures_json, rp.joker_enabled
     FROM game_enrollments ge
     JOIN round_pushes rp ON rp.game_token = ge.game_token
     WHERE ge.token = ?`
  ).bind(token).all();

  const games = await Promise.all((enrollments.results ?? []).map(async (row: any) => {
    const prior = await c.env.DB.prepare(
      `SELECT round_number, status, submitted_at, payload_json
       FROM submissions WHERE token = ? AND game_token = ? AND round_number = ?`
    ).bind(token, row.game_token, row.round_number).first<any>();

    const game: Record<string, unknown> = {
      gameToken: row.game_token,
      mode: row.mode,
      roundNumber: row.round_number,
      deadline: row.deadline,
      gameName: row.game_name ?? null,
      fixtures: JSON.parse(row.fixtures_json),
      jokerEnabled: row.joker_enabled === 1,
      managerSuffix: row.manager_suffix ?? null,
    };
    if (row.eligible_team_ids_json) {
      game.eligibleTeams = JSON.parse(row.eligible_team_ids_json);
    }
    if (prior) {
      game.priorSubmission = {
        roundNumber: prior.round_number,
        status: prior.status,
        submittedAt: prior.submitted_at,
        payload: JSON.parse(prior.payload_json),
      };
    }
    return game;
  }));

  return c.json({ playerName: pt.player_name, managerName: pt.manager_name ?? null, games });
});

// POST /s/:token/games/:gameToken
// Submit (or resubmit) for one specific game.
// LMS body: { teamId, teamName?, fixtureId? } — fixtureId disambiguates a team
// playing twice in the round.
// Predictor body: { scores: [{fixtureId, home, away, isJoker?}] }
submissions.post("/s/:token/games/:gameToken", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const gameToken = c.req.param("gameToken").toLowerCase();
  const body = await c.req.json<Record<string, unknown>>();

  const enrollment = await c.env.DB.prepare(
    `SELECT ge.game_token
     FROM game_enrollments ge
     JOIN player_tokens pt ON pt.token = ge.token
     WHERE ge.token = ? AND ge.game_token = ? AND pt.revoked_at IS NULL`
  ).bind(token, gameToken).first();
  if (!enrollment) return c.json({ error: "Link not found, revoked, or not enrolled in this game." }, 404);

  const push = await c.env.DB.prepare(
    `SELECT round_number FROM round_pushes WHERE game_token = ?`
  ).bind(gameToken).first<{ round_number: number }>();
  if (!push) return c.json({ error: "No active round for this game." }, 404);

  const ts = now();
  const id = crypto.randomUUID().toLowerCase();
  await c.env.DB.prepare(
    `INSERT INTO submissions (id, token, game_token, round_number, payload_json, status, submitted_at)
     VALUES (?, ?, ?, ?, ?, 'pending', ?)
     ON CONFLICT (token, game_token, round_number) DO UPDATE SET
       id = excluded.id,
       payload_json = excluded.payload_json,
       status = 'pending',
       submitted_at = excluded.submitted_at,
       decided_at = NULL`
  ).bind(id, token, gameToken, push.round_number, JSON.stringify(body), ts).run();

  return c.json({ ok: true });
});
