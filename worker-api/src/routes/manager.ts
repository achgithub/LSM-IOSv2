import { Hono } from "hono";
import { resolveManagerDB } from "../shardRouter";

// ── Manager lifecycle (Phase 6) ───────────────────────────────────────────────
//
// Tracks per-manager cloud data lifecycle: subscription state, abandonment
// warnings, and scheduled deletion after unsubscribe.
//
// The manager_token is a client-generated UUID (stored in iOS @AppStorage),
// never tied to PII. It's the anonymous key that links round_pushes,
// player_tokens to one subscriber.
//
// Token is passed via X-Manager-Token header (not the URL path) so it stays
// out of server logs and Cloudflare access logs.
//
// Retention policy:
//   Active:            data lives indefinitely while pushes happen ≤ 60 days apart
//   Warned:            no push for 45 days → warned_at set; iOS shows banner
//   Abandoned delete:  no push for 60 days → cron deletes all data
//   Unsubscribed:      iOS calls /unsubscribe → scheduled_delete_at = now + 14d
//   Grace delete:      cron deletes when scheduled_delete_at has passed

export const manager = new Hono<{ Bindings: Env }>();

function now(): string { return new Date().toISOString(); }

function addDays(date: string, days: number): string {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

function tokenFromHeader(c: any): string | null {
  return c.req.header("X-Manager-Token")?.toLowerCase() ?? null;
}

function shardHeader(c: any): string | null {
  return c.req.header("X-Shard-Id") ?? null;
}

// GET /manager/status
// Returns the lifecycle state for the iOS Cloud Settings screen.
// Called when the Cloud Settings section is opened — not on every app launch.
manager.get("/status", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const { db } = await resolveManagerDB(c.env, shardHeader(c), token);

  const row = await db.prepare(
    `SELECT manager_token, created_at, unsubscribed_at, scheduled_delete_at
     FROM manager_lifecycle WHERE manager_token = ?`
  ).bind(token).first<any>();

  if (!row) return c.json({ state: "not_found" });

  if (row.scheduled_delete_at) {
    const deleteAt = new Date(row.scheduled_delete_at);
    const daysLeft = Math.ceil((deleteAt.getTime() - Date.now()) / 86_400_000);
    return c.json({
      state: "pending_delete",
      scheduledDeleteAt: row.scheduled_delete_at,
      daysUntilDeletion: Math.max(0, daysLeft),
    });
  }

  // Check if they have been warned (abandoned path)
  const warnedPush = await db.prepare(
    `SELECT warned_at FROM round_pushes WHERE manager_token = ? AND warned_at IS NOT NULL LIMIT 1`
  ).bind(token).first<any>();

  if (warnedPush) {
    return c.json({ state: "warned", warnedAt: warnedPush.warned_at });
  }

  return c.json({ state: "active" });
});

// POST /manager/unsubscribe
// Called by the iOS app when RevenueCat reports the cloud bundle has lapsed.
// Idempotent — safe to call multiple times; only sets scheduled_delete_at once.
manager.post("/unsubscribe", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const { db } = await resolveManagerDB(c.env, shardHeader(c), token);

  const ts = now();
  const deleteAt = addDays(ts, 14);

  // Upsert lifecycle row, only setting scheduled_delete_at if not already set.
  await db.prepare(
    `INSERT INTO manager_lifecycle (manager_token, created_at, unsubscribed_at, scheduled_delete_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT (manager_token) DO UPDATE SET
       unsubscribed_at    = COALESCE(manager_lifecycle.unsubscribed_at, excluded.unsubscribed_at),
       scheduled_delete_at = COALESCE(manager_lifecycle.scheduled_delete_at, excluded.scheduled_delete_at)`
  ).bind(token, ts, ts, deleteAt).run();

  return c.json({ ok: true, scheduledDeleteAt: deleteAt });
});

// GET /manager/games
// Lists this manager's games (current round summary only) — feeds the
// per-game sync picker on a newly linked device (see routes/account.ts).
// Not a restore browser: just enough to let the user pick which game to
// pull down next via /manager/games/:gameToken/sync.
manager.get("/games", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const { db } = await resolveManagerDB(c.env, shardHeader(c), token);

  const rows = await db.prepare(
    `SELECT game_token, mode, game_name, round_number, deadline, updated_at
     FROM round_pushes WHERE manager_token = ? ORDER BY updated_at DESC`
  ).bind(token).all<{
    game_token: string; mode: string; game_name: string | null;
    round_number: number; deadline: string | null; updated_at: string;
  }>();

  const games = (rows.results ?? []).map((r) => ({
    gameToken: r.game_token,
    mode: r.mode,
    gameName: r.game_name,
    roundNumber: r.round_number,
    deadline: r.deadline,
    updatedAt: r.updated_at,
  }));
  return c.json({ games });
});

// GET /manager/games/:gameToken/sync
// Pulls one game's syncable state: the current open round (round_pushes is
// overwrite-in-place, so this is the only round ever recoverable) plus the
// full score history (round_results keeps a row per round), enrolled
// players, and this round's already-approved submissions (a player's pick/
// prediction that's already locked in — still-pending ones stay reachable
// via the existing GET /games/:gameToken/submissions approval queue, which
// only needs gameToken + round, so they don't need duplicating here).
// Verifies the requesting manager_token actually owns this game before
// returning anything — an X-Manager-Token header is a claim, not proof, so
// it can't be trusted on its own for a cross-manager read.
//
// `gameConfigJson` can be null — games pushed before this column existed
// (migrations/0007_add_round_pushes_game_config_json.sql) have none, and
// neither do games whose owning device never relaunched after that shipped
// to run the one-time backfill (see PWARoundPusher on iOS). `syncable:
// false` tells the client not to attempt reconstruction rather than
// guessing at scoring-critical config (LMS draw/postponed rules, Predictor/
// Killer point values, etc.) that was never sent to the server at all.
manager.get("/games/:gameToken/sync", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const gameToken = c.req.param("gameToken");
  const { db } = await resolveManagerDB(c.env, shardHeader(c), token);

  const push = await db.prepare(
    `SELECT mode, round_number, deadline, game_name, fixtures_json, joker_enabled, manager_token, extra_json, game_config_json, updated_at
     FROM round_pushes WHERE game_token = ?`
  ).bind(gameToken).first<{
    mode: string; round_number: number; deadline: string | null; game_name: string | null;
    fixtures_json: string; joker_enabled: number; manager_token: string | null;
    extra_json: string | null; game_config_json: string | null; updated_at: string;
  }>();

  // Same response whether the game doesn't exist or belongs to someone else
  // — doesn't matter here (game_tokens are unguessable UUIDs, not an
  // enumeration surface like the account/email routes), but there's no
  // reason to distinguish the two either.
  if (!push || push.manager_token !== token) {
    return c.json({ error: "not authorized for this game" }, 403);
  }

  const resultsRows = await db.prepare(
    `SELECT round_number, mode, results_json, created_at FROM round_results
     WHERE game_token = ? ORDER BY round_number ASC`
  ).bind(gameToken).all<{ round_number: number; mode: string; results_json: string; created_at: string }>();

  const playerRows = await db.prepare(
    `SELECT pt.token, pt.player_name, ge.local_player_id, ge.eligible_team_ids_json, ge.manager_suffix
     FROM game_enrollments ge JOIN player_tokens pt ON pt.token = ge.token
     WHERE ge.game_token = ?`
  ).bind(gameToken).all<{
    token: string; player_name: string; local_player_id: string;
    eligible_team_ids_json: string | null; manager_suffix: string | null;
  }>();

  // Only the currently-open round's approved submissions — past rounds are
  // already summarized in round_results, and pending ones are covered by
  // the existing approval-queue route (see comment above).
  const approvedRows = await db.prepare(
    `SELECT s.token, s.payload_json FROM submissions s
     WHERE s.game_token = ? AND s.round_number = ? AND s.status = 'approved'`
  ).bind(gameToken, push.round_number).all<{ token: string; payload_json: string }>();

  return c.json({
    syncable: push.game_config_json != null,
    gameConfigJson: push.game_config_json,
    currentRound: {
      mode: push.mode,
      roundNumber: push.round_number,
      deadline: push.deadline,
      gameName: push.game_name,
      fixturesJson: push.fixtures_json,
      jokerEnabled: !!push.joker_enabled,
      extraJson: push.extra_json,
      updatedAt: push.updated_at,
    },
    results: (resultsRows.results ?? []).map((r) => ({
      roundNumber: r.round_number,
      mode: r.mode,
      resultsJson: r.results_json,
      createdAt: r.created_at,
    })),
    players: (playerRows.results ?? []).map((p) => ({
      token: p.token,
      playerName: p.player_name,
      localPlayerId: p.local_player_id,
      eligibleTeamIdsJson: p.eligible_team_ids_json,
      managerSuffix: p.manager_suffix,
    })),
    approvedSubmissions: (approvedRows.results ?? []).map((r) => ({
      token: r.token,
      payloadJson: r.payload_json,
    })),
  });
});

// POST /manager/resubscribe
// Called if the manager re-subscribes within the grace period — clears the
// pending deletion so the cron doesn't remove active data.
manager.post("/resubscribe", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const { db } = await resolveManagerDB(c.env, shardHeader(c), token);

  await db.prepare(
    `UPDATE manager_lifecycle
     SET unsubscribed_at = NULL, scheduled_delete_at = NULL
     WHERE manager_token = ?`
  ).bind(token).run();
  return c.json({ ok: true });
});

// POST /manager/entitlements
// Body: { maxPWALinks: number | null }. Called once per app launch (and on
// purchase/restore) after Entitlements.apply(tier:) resolves — the server has
// no other way to know a manager's PWA link cap, since tier/entitlement is a
// client-side (StoreKit) concept. Used only by the cron's over-cap sweep; it
// never triggers a deletion itself. If the manager is currently in an
// over-cap grace and this report shows them back under cap (e.g. they
// revoked links or re-upgraded), the grace is cancelled immediately rather
// than waiting for the next cron run — same eager-cancel pattern as resubscribe.
manager.post("/entitlements", async (c) => {
  const token = tokenFromHeader(c);
  if (!token) return c.json({ error: "missing X-Manager-Token" }, 400);
  const { db } = await resolveManagerDB(c.env, shardHeader(c), token);

  const body = await c.req.json<{ maxPWALinks?: number | null }>().catch(() => null);
  const maxPWALinks = typeof body?.maxPWALinks === "number" ? body.maxPWALinks : null;
  const ts = now();

  await db.prepare(
    `INSERT INTO manager_lifecycle (manager_token, created_at, max_pwa_links)
     VALUES (?, ?, ?)
     ON CONFLICT (manager_token) DO UPDATE SET max_pwa_links = excluded.max_pwa_links`
  ).bind(token, ts, maxPWALinks).run();

  if (maxPWALinks != null) {
    const activeCount = await db.prepare(
      `SELECT COUNT(*) AS n FROM player_tokens WHERE manager_token = ? AND revoked_at IS NULL`
    ).bind(token).first<{ n: number }>();

    if ((activeCount?.n ?? 0) <= maxPWALinks) {
      await db.prepare(
        `UPDATE manager_lifecycle SET link_cap_warned_at = NULL
         WHERE manager_token = ? AND link_cap_warned_at IS NOT NULL`
      ).bind(token).run();
    }
  }

  return c.json({ ok: true });
});
