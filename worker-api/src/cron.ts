// ── LSM API Cron handler ──────────────────────────────────────────────────────
// Moved here from worker/src/cron.ts (#6) — this cleanup operates on
// player_tokens, round_pushes, game_enrollments, submissions, manager_backups,
// manager_lifecycle, publish_links and attest_devices, which only exist in the
// authority (worker-api) schema, not the sports-shard (worker) one. Called
// from index.ts scheduled.

import { DEFAULT_RETENTION_DAYS, LINK_CAP_GRACE_DAYS, WARN_LEAD_DAYS } from "./retention";

// ── Daily Cleanup (Phase 6) ───────────────────────────────────────────────────
//
// Built but NOT yet activated (#12 — parked until current test cycle finishes).
// To activate, add to wrangler.jsonc under the relevant env's "triggers":
//   "triggers": { "crons": ["0 3 * * *"] }   // 3am UTC daily
//
// Retention policy summary (all age-based thresholds unified to 100 days —
// see routes/admin.ts's GET /admin/cleanup-preview for a dry-run of these
// same numbers before they're ever activated):
//   Submissions:      keep last 2 rounds per game (prune on each new round push
//                     AND here as a safety net)
//   Revoked tokens:   hard-delete 100 days after revocation (cascade cleans enrollments)
//   Abandoned games:  warn at 86 days, delete at 100 (measured by round_pushes.updated_at)
//   Publish links:    delete 100 days after last (re)publish, + its R2 blob
//   Attest devices:   delete 100 days after last assertion
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

  // ── 2. Revoked token hard-delete (100 days after revocation) ──────────────
  // ON DELETE CASCADE on game_enrollments.token handles enrollment cleanup.
  const revokedResult = await env.DB.prepare(
    `DELETE FROM player_tokens
     WHERE revoked_at IS NOT NULL
       AND revoked_at < datetime('now', ?)`
  ).bind(`-${DEFAULT_RETENTION_DAYS} days`).run();
  if (revokedResult.meta.changes > 0) log(`deleted ${revokedResult.meta.changes} revoked tokens`);

  // ── 3. Abandonment warnings (86 days since last round push — 14 days ─────
  // before the 100-day delete, matching the grace window used everywhere else).
  const warnResult = await env.DB.prepare(
    `UPDATE round_pushes
     SET warned_at = datetime('now')
     WHERE updated_at < datetime('now', ?)
       AND warned_at IS NULL
       AND manager_token IS NOT NULL`
  ).bind(`-${DEFAULT_RETENTION_DAYS - WARN_LEAD_DAYS} days`).run();
  if (warnResult.meta.changes > 0) log(`warned ${warnResult.meta.changes} abandoned games`);

  // ── 4. Abandonment deletion (100 days since last round push) ─────────────
  const abandonedGames = await env.DB.prepare(
    `SELECT game_token FROM round_pushes
     WHERE updated_at < datetime('now', ?)`
  ).bind(`-${DEFAULT_RETENTION_DAYS} days`).all<{ game_token: string }>();

  for (const { game_token } of abandonedGames.results ?? []) {
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM submissions       WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM game_enrollments  WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM round_pushes      WHERE game_token = ?`).bind(game_token),
      env.DB.prepare(`DELETE FROM round_results     WHERE game_token = ?`).bind(game_token),
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

  // ── 7. Stale publish links (100 days since last (re)publish) ──────────────
  const stalePublishLinks = await env.DB.prepare(
    `SELECT id, r2_key FROM publish_links WHERE updated_at < datetime('now', ?)`
  ).bind(`-${DEFAULT_RETENTION_DAYS} days`).all<{ id: string; r2_key: string }>();

  for (const { id, r2_key } of stalePublishLinks.results ?? []) {
    await env.BACKUPS.delete(r2_key);
    await env.DB.prepare(`DELETE FROM publish_links WHERE id = ?`).bind(id).run();
    log(`deleted stale publish link ${id}`);
  }

  // ── 8. Stale attest devices (100 days since last assertion) ───────────────
  const staleDevices = await env.DB.prepare(
    `DELETE FROM attest_devices WHERE updated_at < datetime('now', ?)`
  ).bind(`-${DEFAULT_RETENTION_DAYS} days`).run();
  if (staleDevices.meta.changes > 0) log(`deleted ${staleDevices.meta.changes} stale attest devices`);

  // ── 9. Player-token over-cap cascade ───────────────────────────────────────
  // A tier downgrade (e.g. league_7 → league_5) can drop a manager below their
  // new maxPWALinks without them ever reopening the app to notice. The client
  // reports its cap via POST /manager/entitlements; this is the only place
  // that acts on it. Over cap + no grace yet → start the 14-day clock. Over
  // cap + grace expired → revoke the excess, least-recently-used first (never
  // opened links go first). Back under cap → cancel any running grace.
  const capRows = await env.DB.prepare(
    `SELECT ml.manager_token, ml.max_pwa_links, ml.link_cap_warned_at,
            (SELECT COUNT(*) FROM player_tokens pt
             WHERE pt.manager_token = ml.manager_token AND pt.revoked_at IS NULL) AS active_count
     FROM manager_lifecycle ml
     WHERE ml.max_pwa_links IS NOT NULL`
  ).all<{ manager_token: string; max_pwa_links: number; link_cap_warned_at: string | null; active_count: number }>();

  for (const row of capRows.results ?? []) {
    const { manager_token, max_pwa_links, link_cap_warned_at, active_count } = row;

    if (active_count <= max_pwa_links) {
      if (link_cap_warned_at) {
        await env.DB.prepare(
          `UPDATE manager_lifecycle SET link_cap_warned_at = NULL WHERE manager_token = ?`
        ).bind(manager_token).run();
        log(`cancelled link-cap grace for manager ${manager_token} (back under cap)`);
      }
      continue;
    }

    if (!link_cap_warned_at) {
      await env.DB.prepare(
        `UPDATE manager_lifecycle SET link_cap_warned_at = datetime('now') WHERE manager_token = ?`
      ).bind(manager_token).run();
      log(`started link-cap grace for manager ${manager_token} (${active_count} links, cap ${max_pwa_links})`);
      continue;
    }

    const graceExpired = await env.DB.prepare(
      `SELECT 1 FROM manager_lifecycle
       WHERE manager_token = ? AND link_cap_warned_at < datetime('now', ?)`
    ).bind(manager_token, `-${LINK_CAP_GRACE_DAYS} days`).first();
    if (!graceExpired) continue;

    const excess = active_count - max_pwa_links;
    const toRevoke = await env.DB.prepare(
      `SELECT token FROM player_tokens
       WHERE manager_token = ? AND revoked_at IS NULL
       ORDER BY last_used_at IS NOT NULL ASC, last_used_at ASC
       LIMIT ?`
    ).bind(manager_token, excess).all<{ token: string }>();

    const ts = new Date().toISOString();
    for (const { token } of toRevoke.results ?? []) {
      await env.DB.prepare(`UPDATE player_tokens SET revoked_at = ? WHERE token = ?`).bind(ts, token).run();
    }
    await env.DB.prepare(
      `UPDATE manager_lifecycle SET link_cap_warned_at = NULL WHERE manager_token = ?`
    ).bind(manager_token).run();
    log(`revoked ${toRevoke.results?.length ?? 0} over-cap links for manager ${manager_token}`);
  }

  log("done");
}

// Purge all D1 and R2 data for one manager (used by both scheduled delete and
// the admin panel).
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
      env.DB.prepare(`DELETE FROM round_results     WHERE game_token = ?`).bind(game_token),
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

  // Publish links (+ their R2 blobs) — only findable via manager_token now
  // that publish.ts stamps it (see #12 discussion on manager linkage).
  const publishLinks = await env.DB.prepare(
    `SELECT id, r2_key FROM publish_links WHERE manager_token = ?`
  ).bind(managerToken).all<{ id: string; r2_key: string }>();

  for (const { id, r2_key } of publishLinks.results ?? []) {
    await env.BACKUPS.delete(r2_key);
    await env.DB.prepare(`DELETE FROM publish_links WHERE id = ?`).bind(id).run();
  }

  // Attest devices — same manager_token linkage.
  await env.DB.prepare(`DELETE FROM attest_devices WHERE manager_token = ?`).bind(managerToken).run();

  // Lifecycle and backup audit rows.
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM manager_backups  WHERE manager_token = ?`).bind(managerToken),
    env.DB.prepare(`DELETE FROM manager_lifecycle WHERE manager_token = ?`).bind(managerToken),
  ]);

  log(`deleted all data for manager ${managerToken}`);
}
