import { Hono } from "hono";

// ── Submissions (the anonymous PWA approval queue) — Phase 3 ─────────────────
//
// Two audiences:
//
//   PLAYER (PWA, anonymous) — reaches routes via their unguessable per-game
//   token (/s/:token). They see what's actionable for their game right now and
//   POST a submission. A submission lands as 'pending'; the manager approves it
//   to create the real on-device Pick/Prediction. No email, no login.
//
//   MANAGER (LSM app) — mints/revokes tokens per player, pushes the current
//   round after openRound, reviews the queue, and approves/rejects. The
//   payload returned on approve is everything the app needs to write the local
//   Pick/Prediction without a second round-trip.
//
// Not attest-gated (consistent with backup/publish — deferred to App Store
// release, same accepted-tradeoff framing). All tokens lowercased on every
// read/write path — same case-mismatch lesson as Phase 2 publish.
//
// game_token is a client-generated UUID minted by the iOS app on the first
// round push for a game (stored as Game.cloudGameTokenRaw on-device).

export const submissions = new Hono<{ Bindings: Env }>();

// ─── helpers ─────────────────────────────────────────────────────────────────

function now(): string {
  return new Date().toISOString();
}

// ─── Manager-facing ──────────────────────────────────────────────────────────

// POST /games/:gameToken/links
// Mint (or regenerate) a player link. If a link already exists for this
// (game_token, local_player_id) it is replaced — the old token is immediately
// invalid (overwritten, not kept). Returns { token }.
submissions.post("/games/:gameToken/links", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const body = await c.req.json<{ localPlayerId: string; playerName: string }>();
  const { localPlayerId, playerName } = body ?? {};
  if (!localPlayerId || !playerName) {
    return c.json({ error: "localPlayerId and playerName are required" }, 400);
  }
  const pid = localPlayerId.toLowerCase();
  const token = crypto.randomUUID().toLowerCase();

  // Revoke any existing token for this player in this game before inserting
  await c.env.DB.prepare(
    `UPDATE player_links SET revoked_at = ? WHERE game_token = ? AND local_player_id = ? AND revoked_at IS NULL`
  )
    .bind(now(), gameToken, pid)
    .run();

  await c.env.DB.prepare(
    `INSERT INTO player_links (token, game_token, local_player_id, player_name, created_at)
     VALUES (?, ?, ?, ?, ?)`
  )
    .bind(token, gameToken, pid, playerName, now())
    .run();

  return c.json({ token });
});

// POST /games/:gameToken/links/:token/revoke
// Revoke a player link immediately. The player's /s/:token page returns 404.
submissions.post("/games/:gameToken/links/:token/revoke", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const token = c.req.param("token").toLowerCase();
  const result = await c.env.DB.prepare(
    `UPDATE player_links SET revoked_at = ? WHERE token = ? AND game_token = ? AND revoked_at IS NULL`
  )
    .bind(now(), token, gameToken)
    .run();
  if (result.meta.changes === 0) return c.json({ error: "token not found or already revoked" }, 404);
  return c.json({ ok: true });
});

// POST /games/:gameToken/push
// Upsert the current open round for a game, and refresh eligible_team_ids_json
// for every included player token (LMS: their available teams; Predictor: null).
// Called after GameLogicService.openRound and after "Edit Fixtures" resets.
// Only players with an existing (active) token are updated; no new tokens are
// minted here.
submissions.post("/games/:gameToken/push", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  interface EligibleTeam { id: number; name: string }
  interface PushPlayer {
    token: string;
    eligibleTeams?: EligibleTeam[] | null;
  }
  const body = await c.req.json<{
    mode: string;
    roundNumber: number;
    deadline?: string | null;
    fixtures: unknown[];
    players: PushPlayer[];
  }>();
  const { mode, roundNumber, deadline, fixtures, players } = body ?? {};
  if (!mode || roundNumber == null || !Array.isArray(fixtures)) {
    return c.json({ error: "mode, roundNumber, and fixtures are required" }, 400);
  }

  const ts = now();
  await c.env.DB.prepare(
    `INSERT INTO round_pushes (game_token, mode, round_number, deadline, fixtures_json, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT (game_token) DO UPDATE SET
       mode = excluded.mode,
       round_number = excluded.round_number,
       deadline = excluded.deadline,
       fixtures_json = excluded.fixtures_json,
       updated_at = excluded.updated_at`
  )
    .bind(gameToken, mode, roundNumber, deadline ?? null, JSON.stringify(fixtures), ts)
    .run();

  if (Array.isArray(players)) {
    for (const p of players) {
      const tk = p.token.toLowerCase();
      const eligJson = p.eligibleTeams != null ? JSON.stringify(p.eligibleTeams) : null;
      await c.env.DB.prepare(
        `UPDATE player_links SET eligible_team_ids_json = ? WHERE token = ? AND game_token = ? AND revoked_at IS NULL`
      )
        .bind(eligJson, tk, gameToken)
        .run();
    }
  }

  return c.json({ ok: true });
});

// GET /games/:gameToken/submissions?round=N
// List submissions for the current (or specified) round, joined with player names.
submissions.get("/games/:gameToken/submissions", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const round = c.req.query("round");

  let rows;
  if (round) {
    const rn = parseInt(round, 10);
    rows = await c.env.DB.prepare(
      `SELECT s.id, s.token, pl.player_name, pl.local_player_id,
              s.round_number, s.payload_json, s.status, s.submitted_at, s.decided_at
       FROM submissions s
       JOIN player_links pl ON pl.token = s.token
       WHERE pl.game_token = ? AND s.round_number = ?
       ORDER BY s.submitted_at ASC`
    )
      .bind(gameToken, rn)
      .all();
  } else {
    rows = await c.env.DB.prepare(
      `SELECT s.id, s.token, pl.player_name, pl.local_player_id,
              s.round_number, s.payload_json, s.status, s.submitted_at, s.decided_at
       FROM submissions s
       JOIN player_links pl ON pl.token = s.token
       WHERE pl.game_token = ?
       ORDER BY s.submitted_at ASC`
    )
      .bind(gameToken)
      .all();
  }

  return c.json({
    submissions: (rows.results ?? []).map((r: any) => ({
      id: r.id,
      token: r.token,
      playerName: r.player_name,
      localPlayerId: r.local_player_id,
      roundNumber: r.round_number,
      payload: JSON.parse(r.payload_json as string),
      status: r.status,
      submittedAt: r.submitted_at,
      decidedAt: r.decided_at,
    })),
  });
});

// POST /games/:gameToken/submissions/:id/approve
// Mark a submission approved. The game_token in the path must match the
// submission's parent player_link — prevents a player from self-approving by
// replaying the submission id they received from POST /s/:token.
// Returns the full row so iOS can write the local Pick/Prediction immediately.
submissions.post("/games/:gameToken/submissions/:id/approve", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const id = c.req.param("id").toLowerCase();
  const ts = now();
  // Scope the UPDATE to submissions whose player_link belongs to this game.
  const result = await c.env.DB.prepare(
    `UPDATE submissions SET status = 'approved', decided_at = ?
     WHERE id = ? AND status = 'pending'
       AND EXISTS (
         SELECT 1 FROM player_links pl
         WHERE pl.token = submissions.token AND pl.game_token = ?
       )`
  )
    .bind(ts, id, gameToken)
    .run();
  if (result.meta.changes === 0) return c.json({ error: "submission not found or already decided" }, 404);

  const row = await c.env.DB.prepare(
    `SELECT s.id, s.token, pl.player_name, pl.local_player_id,
            s.round_number, s.payload_json, s.status, s.decided_at
     FROM submissions s
     JOIN player_links pl ON pl.token = s.token
     WHERE s.id = ? AND pl.game_token = ?`
  )
    .bind(id, gameToken)
    .first<any>();

  if (!row) return c.json({ error: "not found after update" }, 500);
  return c.json({
    id: row.id,
    localPlayerId: row.local_player_id,
    roundNumber: row.round_number,
    payload: JSON.parse(row.payload_json),
  });
});

// POST /games/:gameToken/submissions/:id/reject
// Mark a submission rejected. Same game-scope guard as approve.
submissions.post("/games/:gameToken/submissions/:id/reject", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const id = c.req.param("id").toLowerCase();
  const ts = now();
  const result = await c.env.DB.prepare(
    `UPDATE submissions SET status = 'rejected', decided_at = ?
     WHERE id = ? AND status = 'pending'
       AND EXISTS (
         SELECT 1 FROM player_links pl
         WHERE pl.token = submissions.token AND pl.game_token = ?
       )`
  )
    .bind(ts, id, gameToken)
    .run();
  if (result.meta.changes === 0) return c.json({ error: "submission not found or already decided" }, 404);
  return c.json({ ok: true });
});

// ─── Player-facing (PWA) ─────────────────────────────────────────────────────

// GET /s/:token
// What's actionable for this player right now. Returns the open round for their
// game (mode, fixtures, eligible teams for LMS) plus any prior submission.
// 404 if revoked or no active round push for this game.
submissions.get("/s/:token", async (c) => {
  const token = c.req.param("token").toLowerCase();

  const link = await c.env.DB.prepare(
    `SELECT token, game_token, local_player_id, player_name, eligible_team_ids_json, revoked_at
     FROM player_links WHERE token = ?`
  )
    .bind(token)
    .first<any>();

  if (!link) return c.json({ error: "Link not found." }, 404);
  if (link.revoked_at) return c.json({ error: "This link has been revoked." }, 404);

  const push = await c.env.DB.prepare(
    `SELECT mode, round_number, deadline, fixtures_json FROM round_pushes WHERE game_token = ?`
  )
    .bind(link.game_token)
    .first<any>();

  if (!push) return c.json({ error: "No active round for this game yet." }, 404);

  const prior = await c.env.DB.prepare(
    `SELECT id, round_number, payload_json, status, submitted_at
     FROM submissions WHERE token = ? AND round_number = ?`
  )
    .bind(token, push.round_number)
    .first<any>();

  const response: Record<string, unknown> = {
    playerName: link.player_name,
    mode: push.mode,
    roundNumber: push.round_number,
    deadline: push.deadline,
    fixtures: JSON.parse(push.fixtures_json),
  };
  if (link.eligible_team_ids_json) {
    response.eligibleTeams = JSON.parse(link.eligible_team_ids_json);
  }
  if (prior) {
    response.priorSubmission = {
      roundNumber: prior.round_number,
      status: prior.status,
      submittedAt: prior.submitted_at,
    };
  }
  return c.json(response);
});

// POST /s/:token
// Submit (or resubmit) for the current round. Resubmitting while pending
// replaces the existing row (latest wins). Body: LMS {teamId} or Predictor
// {scores:[{fixtureId,home,away}]}.
submissions.post("/s/:token", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const body = await c.req.json<Record<string, unknown>>();

  const link = await c.env.DB.prepare(
    `SELECT game_token FROM player_links WHERE token = ? AND revoked_at IS NULL`
  )
    .bind(token)
    .first<any>();
  if (!link) return c.json({ error: "Link not found or revoked." }, 404);

  const push = await c.env.DB.prepare(
    `SELECT mode, round_number FROM round_pushes WHERE game_token = ?`
  )
    .bind(link.game_token)
    .first<any>();
  if (!push) return c.json({ error: "No active round for this game." }, 404);

  const ts = now();
  const id = crypto.randomUUID().toLowerCase();
  await c.env.DB.prepare(
    `INSERT INTO submissions (id, token, round_number, payload_json, status, submitted_at)
     VALUES (?, ?, ?, ?, 'pending', ?)
     ON CONFLICT (token, round_number) DO UPDATE SET
       id = excluded.id,
       payload_json = excluded.payload_json,
       status = 'pending',
       submitted_at = excluded.submitted_at,
       decided_at = NULL`
  )
    .bind(id, token, push.round_number, JSON.stringify(body), ts)
    .run();

  return c.json({ ok: true });
});
