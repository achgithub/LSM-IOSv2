import { Hono } from "hono";
import { validateSubmissionPayload, referencedFixtureIds } from "../validation/submissionPayload";

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
// is registered in index.ts, ahead of the global outage gate — see the comment
// there for why it can't live here.

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

// POST /links/revoke-by-name
// Self-heal path for a manager who has lost their local record of a token
// (e.g. app reinstall wipes the on-device roster, but the Keychain-backed
// managerToken survives, so /links still 409s on remint). Scoped to the
// caller's own managerToken — a manager can only revoke a link that was
// minted with that same managerToken, never an arbitrary player's link.
submissions.post("/links/revoke-by-name", async (c) => {
  const body = await c.req.json<{ playerName: string; managerToken?: string }>();
  const playerName = body?.playerName?.trim();
  const managerToken = body?.managerToken?.toLowerCase().trim();
  if (!playerName) return c.json({ error: "playerName is required" }, 400);
  if (!managerToken) return c.json({ error: "managerToken is required" }, 400);

  const result = await c.env.DB.prepare(
    `UPDATE player_tokens SET revoked_at = ?
     WHERE player_name = ? AND manager_token = ? AND revoked_at IS NULL`
  ).bind(now(), playerName, managerToken).run();
  if (result.meta.changes === 0) {
    return c.json({ error: "No active link for this player under this manager" }, 404);
  }
  return c.json({ ok: true });
});

// POST /games/:gameToken/push
// Upsert the open round and (re)enroll every player who has a token.
// Body: { mode, roundNumber, deadline?, gameName?, fixtures, jokerEnabled?, extra?,
//         previousResultsRoundNumber?, previousResults?, managerSuffix?, players }
// `extra` is an opaque, mode-specific JSON string (e.g. Killer's
// {"phase":"build"}) — stored and returned unread/unvalidated, exactly like
// fixtures/payload_json elsewhere in this file. Null/omitted for LMS/Predictor.
// `previousResults` (a pre-serialized JSON array string, same convention as
// `extra`) is the most-recently-closed round's outcome (survived/eliminated,
// points, lives/hits — opaque per mode) for `previousResultsRoundNumber`,
// piggybacked on whichever push happens next: a new round opening, a
// game-complete event with no new round, or a manual "resend" retry. Not a
// separate endpoint — always rides along with the same round_pushes upsert
// this route already does.
submissions.post("/games/:gameToken/push", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  // fixtureId/opponentName are set when a team plays twice in the round
  // (rearranged fixtures) — disambiguates which fixture occurrence this is.
  interface EligibleTeam { id: number; name: string; fixtureId?: number; opponentName?: string }
  interface PushPlayer {
    token: string;
    localPlayerId: string;
    // Roster member's current name — carried on every push so an in-app
    // rename refreshes player_tokens.player_name without a dedicated call.
    playerName?: string | null;
    eligibleTeams?: EligibleTeam[] | null;
  }
  const body = await c.req.json<{
    mode: string;
    roundNumber: number;
    deadline?: string | null;
    gameName?: string | null;
    fixtures: unknown[];
    jokerEnabled?: boolean;
    extra?: string | null;
    previousResultsRoundNumber?: number | null;
    previousResults?: string | null;
    managerSuffix?: string | null;
    managerName?: string | null;
    managerToken?: string | null;
    players: PushPlayer[];
  }>();
  const {
    mode, roundNumber, deadline, gameName, fixtures, jokerEnabled, extra,
    previousResultsRoundNumber, previousResults, managerSuffix, managerName, managerToken, players,
  } = body ?? {};
  if (!mode || roundNumber == null || !Array.isArray(fixtures)) {
    return c.json({ error: "mode, roundNumber, and fixtures are required" }, 400);
  }

  const ts = now();
  const mgrToken = managerToken?.toLowerCase() ?? null;

  await c.env.DB.prepare(
    `INSERT INTO round_pushes (game_token, mode, round_number, deadline, game_name, fixtures_json, joker_enabled, manager_token, updated_at, extra_json)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (game_token) DO UPDATE SET
       mode = excluded.mode,
       round_number = excluded.round_number,
       deadline = excluded.deadline,
       game_name = excluded.game_name,
       fixtures_json = excluded.fixtures_json,
       joker_enabled = excluded.joker_enabled,
       manager_token = COALESCE(round_pushes.manager_token, excluded.manager_token),
       updated_at = excluded.updated_at,
       extra_json = excluded.extra_json`
  ).bind(gameToken, mode, roundNumber, deadline ?? null, gameName ?? null, JSON.stringify(fixtures), jokerEnabled ? 1 : 0, mgrToken, ts, extra ?? null).run();

  if (mgrToken) await ensureManagerLifecycle(c.env, mgrToken);

  if (previousResultsRoundNumber != null && previousResults) {
    // `previousResults` arrives already JSON.stringify'd by the client (same
    // convention as `extra`) — stored verbatim, no re-serialization needed.
    await c.env.DB.prepare(
      `INSERT INTO round_results (game_token, round_number, mode, results_json, created_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (game_token, round_number) DO UPDATE SET
         mode = excluded.mode,
         results_json = excluded.results_json,
         created_at = excluded.created_at`
    ).bind(gameToken, previousResultsRoundNumber, mode, previousResults, ts).run();

    // Keep the last 2 results rows per game (matches submissions' retention).
    if (previousResultsRoundNumber > 1) {
      await c.env.DB.prepare(
        `DELETE FROM round_results WHERE game_token = ? AND round_number < ?`
      ).bind(gameToken, previousResultsRoundNumber - 1).run();
    }
  }

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

      const newName = p.playerName?.trim() || null;
      if (mgrName && newName) {
        await c.env.DB.prepare(
          `UPDATE player_tokens SET manager_name = ?, player_name = ? WHERE token = ?`
        ).bind(mgrName, newName, tk).run();
      } else if (mgrName) {
        await c.env.DB.prepare(
          `UPDATE player_tokens SET manager_name = ? WHERE token = ?`
        ).bind(mgrName, tk).run();
      } else if (newName) {
        await c.env.DB.prepare(
          `UPDATE player_tokens SET player_name = ? WHERE token = ?`
        ).bind(newName, tk).run();
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

// DELETE /games/:gameToken
// Called when the manager deletes the game on-device. Removes this game's
// round/enrollment/submission rows. Does NOT touch player_tokens — those are
// one global link per player, shared across all of a player's games.
submissions.delete("/games/:gameToken", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  await c.env.DB.batch([
    c.env.DB.prepare(`DELETE FROM round_pushes WHERE game_token = ?`).bind(gameToken),
    c.env.DB.prepare(`DELETE FROM game_enrollments WHERE game_token = ?`).bind(gameToken),
    c.env.DB.prepare(`DELETE FROM submissions WHERE game_token = ?`).bind(gameToken),
  ]);
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

  await c.env.DB.prepare(
    `UPDATE player_tokens SET last_used_at = ? WHERE token = ?`
  ).bind(new Date().toISOString(), token).run();

  const enrollments = await c.env.DB.prepare(
    `SELECT ge.game_token, ge.eligible_team_ids_json, ge.manager_suffix, ge.local_player_id,
            rp.mode, rp.round_number, rp.deadline, rp.game_name, rp.fixtures_json, rp.joker_enabled, rp.extra_json
     FROM game_enrollments ge
     JOIN round_pushes rp ON rp.game_token = ge.game_token
     WHERE ge.token = ?`
  ).bind(token).all();

  const games = await Promise.all((enrollments.results ?? []).map(async (row: any) => {
    const prior = await c.env.DB.prepare(
      `SELECT round_number, status, submitted_at, payload_json
       FROM submissions WHERE token = ? AND game_token = ? AND round_number = ?`
    ).bind(token, row.game_token, row.round_number).first<any>();

    // Last-2-rounds submission history — the `submissions` table already
    // retains the prior round's rows (pruned at round_number < current - 2 on
    // push), this just surfaces what's already there. "What did I submit."
    const historyRows = await c.env.DB.prepare(
      `SELECT round_number, status, submitted_at, payload_json
       FROM submissions
       WHERE token = ? AND game_token = ? AND round_number < ? AND round_number >= ?
       ORDER BY round_number DESC`
    ).bind(token, row.game_token, row.round_number, Math.max(1, row.round_number - 2)).all();

    // "What actually happened" — survived/eliminated, points, lives/hits —
    // fetched independently of `historyRows` since a player can have a
    // result for a round without ever having submitted anything there (e.g.
    // the manager entered their pick manually). Merged below by round number.
    const resultsRows = await c.env.DB.prepare(
      `SELECT round_number, results_json
       FROM round_results
       WHERE game_token = ? AND round_number < ? AND round_number >= ?
       ORDER BY round_number DESC`
    ).bind(row.game_token, row.round_number, Math.max(1, row.round_number - 2)).all();
    const resultByRound = new Map<number, unknown>();
    for (const r of (resultsRows.results ?? []) as { round_number: number; results_json: string }[]) {
      const entries = JSON.parse(r.results_json) as { playerId?: string }[];
      const mine = entries.find((e) => e.playerId?.toLowerCase() === (row.local_player_id ?? "").toLowerCase());
      if (mine) resultByRound.set(r.round_number, mine);
    }

    const game: Record<string, unknown> = {
      gameToken: row.game_token,
      mode: row.mode,
      roundNumber: row.round_number,
      deadline: row.deadline,
      gameName: row.game_name ?? null,
      fixtures: JSON.parse(row.fixtures_json),
      jokerEnabled: row.joker_enabled === 1,
      managerSuffix: row.manager_suffix ?? null,
      // Lets the PWA identify "me" in a mode-agnostic per-player roster (e.g.
      // Killer's opponent list) without a separate lookup.
      localPlayerId: row.local_player_id ?? null,
    };
    if (row.eligible_team_ids_json) {
      game.eligibleTeams = JSON.parse(row.eligible_team_ids_json);
    }
    if (row.extra_json) {
      game.extra = row.extra_json;
    }
    if (prior) {
      game.priorSubmission = {
        roundNumber: prior.round_number,
        status: prior.status,
        submittedAt: prior.submitted_at,
        payload: JSON.parse(prior.payload_json),
      };
    }
    const historyByRound = new Map<number, Record<string, unknown>>();
    for (const h of (historyRows.results ?? []) as { round_number: number; status: string; submitted_at: string; payload_json: string }[]) {
      historyByRound.set(h.round_number, {
        roundNumber: h.round_number,
        status: h.status,
        submittedAt: h.submitted_at,
        payload: JSON.parse(h.payload_json),
      });
    }
    for (const [roundNum, result] of resultByRound) {
      const existing = historyByRound.get(roundNum);
      if (existing) {
        existing.result = result;
      } else {
        historyByRound.set(roundNum, { roundNumber: roundNum, result });
      }
    }
    if (historyByRound.size > 0) {
      game.history = Array.from(historyByRound.values()).sort(
        (a, b) => (b.roundNumber as number) - (a.roundNumber as number)
      );
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
// All modes may optionally include `roundNumber` (the round the client loaded
// against) — if present and stale, the submission is rejected with 409 rather
// than silently landing against whatever round is now live.
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
    `SELECT round_number, mode, deadline, fixtures_json FROM round_pushes WHERE game_token = ?`
  ).bind(gameToken).first<{ round_number: number; mode: string; deadline: string | null; fixtures_json: string }>();
  if (!push) return c.json({ error: "No active round for this game." }, 404);

  // If the client tells us which round it loaded against, reject a submission
  // that's fallen behind — otherwise a stale tab (round N still open in the
  // browser after the manager has moved on to round N+1) silently overwrites
  // whatever was already submitted for the new round via the upsert below.
  // Optional/backwards-compatible: an old cached PWA build that doesn't send
  // roundNumber still gets today's behavior.
  const submittedRoundNumber = typeof body.roundNumber === "number" ? body.roundNumber : null;
  if (submittedRoundNumber !== null && submittedRoundNumber !== push.round_number) {
    return c.json({ error: "round_moved_on", currentRound: push.round_number }, 409);
  }

  // `deadline` was previously display-only — a submission arriving after it
  // (e.g. a tab left open past cutoff) was silently accepted. Reject it
  // server-side instead of relying on the PWA's own clock, which the client
  // controls.
  if (push.deadline && Date.now() > new Date(push.deadline).getTime()) {
    return c.json({ error: "deadline_passed", deadline: push.deadline }, 403);
  }

  // This endpoint is unauthenticated by design (anonymous player token, no
  // login) — anyone who guesses or leaks a token can POST arbitrary JSON
  // here, so unlike the JWT-gated manager push above, the shape/range of
  // this body is worth policing before it's persisted and later trusted by
  // the manager's approve flow. Validates against `push.mode`, which comes
  // from the trusted round_pushes row, not from this body. Stores the
  // whitelisted, sanitized value — not the raw body — as a second layer of
  // defense against unexpected extra fields.
  const validation = validateSubmissionPayload(push.mode, body);
  if (!validation.ok) return c.json({ error: validation.error }, 400);

  // A round number can match while the fixtures underneath it have already
  // moved on in some edge case (or a client is simply sending fabricated
  // ids) — cross-check every fixtureId the payload references is actually
  // part of the round currently pushed for this game.
  let pushedFixtureIds: Set<number>;
  try {
    const fixtures = JSON.parse(push.fixtures_json) as Array<{ fixtureId: number }>;
    pushedFixtureIds = new Set(fixtures.map((f) => f.fixtureId));
  } catch {
    pushedFixtureIds = new Set();
  }
  const badFixtureId = referencedFixtureIds(push.mode, validation.value).find((id) => !pushedFixtureIds.has(id));
  if (badFixtureId !== undefined) {
    return c.json({ error: `fixtureId ${badFixtureId} is not part of the current round` }, 400);
  }

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
  ).bind(id, token, gameToken, push.round_number, JSON.stringify(validation.value), ts).run();

  return c.json({ ok: true });
});
