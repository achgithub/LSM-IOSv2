// ── LSM Cron handlers ─────────────────────────────────────────────────────────
// Two exports: runDailyCleanup (game/token/backup retention) + runDailySync
// (per-league football-data.org refresh). Both called from index.ts scheduled.

import { regionSecret } from "./auth";
import { getAllLeagues } from "./db";
import { FootballDataProvider } from "./football";
import { runMaintenance } from "./sync";

// ── Daily Cleanup (Phase 6) ───────────────────────────────────────────────────
//
// Built but NOT yet activated. To activate, add to wrangler.jsonc under the
// relevant env's "triggers":
//   "triggers": { "crons": ["0 3 * * *"] }   // 3am UTC daily
//
// Retention policy summary:
//   Submissions:      keep last 2 rounds per game (prune on each new round push
//                     AND here as a safety net)
//   Revoked tokens:   hard-delete 30 days after revocation (cascade cleans enrollments)
//   Abandoned games:  warn at 45 days, delete at 60 (measured by round_pushes.updated_at)
//   Unsubscribe:      iOS sets scheduled_delete_at = now + 14d; cron executes deletion
//   R2 backups:       keep last 2 per manager; delete older blobs

export async function runDailyCleanup(env: Env): Promise<void> {
  const log = (msg: string) => console.log(JSON.stringify({ cron: "daily-cleanup", msg }));
  log("starting");

  // ── 1. Submission pruning (safety net — primary pruning happens on push) ───
  // Delete submissions more than 2 rounds behind the current open round per game.
  const gamePushes = await env.DB.prepare(
    `SELECT game_token, round_number FROM round_pushes`
  ).all<{ game_token: string; round_number: number }>();

  for (const { game_token, round_number } of gamePushes.results ?? []) {
    if (round_number <= 2) continue;
    const cutoff = round_number - 2;
    const r = await env.DB.prepare(
      `DELETE FROM submissions WHERE game_token = ? AND round_number < ?`
    ).bind(game_token, cutoff).run();
    if (r.meta.changes > 0) log(`pruned ${r.meta.changes} old submissions for game ${game_token}`);
  }

  // ── 2. Revoked token hard-delete (30 days after revocation) ───────────────
  // ON DELETE CASCADE on game_enrollments.token handles enrollment cleanup.
  const revokedResult = await env.DB.prepare(
    `DELETE FROM player_tokens
     WHERE revoked_at IS NOT NULL
       AND revoked_at < datetime('now', '-30 days')`
  ).run();
  if (revokedResult.meta.changes > 0) log(`deleted ${revokedResult.meta.changes} revoked tokens`);

  // ── 3. Abandonment warnings (45 days since last round push) ───────────────
  const warnResult = await env.DB.prepare(
    `UPDATE round_pushes
     SET warned_at = datetime('now')
     WHERE updated_at < datetime('now', '-45 days')
       AND warned_at IS NULL
       AND manager_token IS NOT NULL`
  ).run();
  if (warnResult.meta.changes > 0) log(`warned ${warnResult.meta.changes} abandoned games`);

  // ── 4. Abandonment deletion (60 days since last round push) ───────────────
  const abandonedGames = await env.DB.prepare(
    `SELECT game_token FROM round_pushes
     WHERE updated_at < datetime('now', '-60 days')`
  ).all<{ game_token: string }>();

  for (const { game_token } of abandonedGames.results ?? []) {
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM submissions       WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM game_enrollments  WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM round_pushes      WHERE game_token = ?`).bind(game_token),
    ]);
    log(`deleted abandoned game ${game_token}`);
  }

  // ── 5. Manager scheduled deletes (unsubscribe grace period expired) ────────
  const dueForDelete = await env.DB.prepare(
    `SELECT manager_token FROM manager_lifecycle
     WHERE scheduled_delete_at IS NOT NULL
       AND scheduled_delete_at < datetime('now')`
  ).all<{ manager_token: string }>();

  for (const { manager_token } of dueForDelete.results ?? []) {
    await deleteManagerData(env, manager_token, log);
  }

  // ── 6. R2 backup pruning (keep last 2 per manager) ────────────────────────
  const managers = await env.DB.prepare(
    `SELECT DISTINCT manager_token FROM manager_backups`
  ).all<{ manager_token: string }>();

  for (const { manager_token } of managers.results ?? []) {
    const backups = await env.DB.prepare(
      `SELECT restore_code FROM manager_backups
       WHERE manager_token = ?
       ORDER BY backed_up_at DESC`
    ).bind(manager_token).all<{ restore_code: string }>();

    const toDelete = (backups.results ?? []).slice(2);
    for (const { restore_code } of toDelete) {
      await env.BACKUPS.delete(`backups/${restore_code}.json`);
      await env.DB.prepare(
        `DELETE FROM manager_backups WHERE manager_token = ? AND restore_code = ?`
      ).bind(manager_token, restore_code).run();
      log(`deleted old backup ${restore_code} for manager ${manager_token}`);
    }
  }

  log("done");
}

// ── Daily Sync ────────────────────────────────────────────────────────────────
// Runs runMaintenance for every league in this shard — same as sync-if-due but
// called directly from the cron scheduled handler rather than over HTTP.
// FOOTBALL_DATA_TOKEN must be set as a secret; if unset the sync is skipped.

export async function runDailySync(env: Env): Promise<void> {
  const log = (msg: string) => console.log(JSON.stringify({ cron: "daily-sync", msg }));
  const footballToken = regionSecret(env, "FOOTBALL_DATA_TOKEN");
  if (!footballToken) { log("FOOTBALL_DATA_TOKEN not set, skipping"); return; }

  const leagues = await getAllLeagues(env.DB);
  for (const league of leagues) {
    log(`syncing ${league.id}`);
    const provider = new FootballDataProvider(footballToken, league.football_data_code, league.id);
    try {
      await runMaintenance(env.DB, env.SCORES, provider, league.id);
      log(`done ${league.id}`);
    } catch (err) {
      log(`failed ${league.id}: ${String(err)}`);
    }
  }
}

// Purge all D1 and R2 data for one manager (used by both scheduled delete and
// potential future manual admin endpoint).
export async function deleteManagerData(env: Env, managerToken: string, log: (m: string) => void): Promise<void> {
  // Game data: submissions → enrollments → round_pushes (in that order to
  // avoid FK issues; submissions and enrollments reference game_token directly).
  const games = await env.DB.prepare(
    `SELECT game_token FROM round_pushes WHERE manager_token = ?`
  ).bind(managerToken).all<{ game_token: string }>();

  for (const { game_token } of games.results ?? []) {
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM submissions       WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM game_enrollments  WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM round_pushes      WHERE game_token = ?`).bind(game_token),
    ]);
  }

  // Player tokens (CASCADE removes game_enrollments for any not yet deleted).
  await env.DB.prepare(
    `DELETE FROM player_tokens WHERE manager_token = ?`
  ).bind(managerToken).run();

  // R2 backups.
  const backups = await env.DB.prepare(
    `SELECT restore_code FROM manager_backups WHERE manager_token = ?`
  ).bind(managerToken).all<{ restore_code: string }>();

  for (const { restore_code } of backups.results ?? []) {
    await env.BACKUPS.delete(`backups/${restore_code}.json`);
  }

  // Lifecycle and backup audit rows.
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM manager_backups  WHERE manager_token = ?`).bind(managerToken),
    env.DB.prepare(`DELETE FROM manager_lifecycle WHERE manager_token = ?`).bind(managerToken),
  ]);

  log(`deleted all data for manager ${managerToken}`);
}
