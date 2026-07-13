// ── Retention queries ─────────────────────────────────────────────────────────
// Shared, read-only "what's stale" queries used by both the real cleanup
// (cron.ts) and the manual dry-run preview (routes/admin.ts's
// GET /admin/cleanup-preview). Keeping the WHERE clauses in one place means
// the preview can never drift from what the cron actually deletes.

export const DEFAULT_RETENTION_DAYS = 100;
// round_pushes gets a warning stamped this many days before it's eligible for
// deletion — chosen to match the same 14-day grace window used everywhere
// else (manager unsubscribe, player-token over-cap).
export const WARN_LEAD_DAYS = 14;
// Grace window for the player-token over-cap cascade (a downgrade drops a
// manager below their tier's maxPWALinks) — same 14-day pattern as unsubscribe.
export const LINK_CAP_GRACE_DAYS = 14;

export interface StalePreview {
  days: number;
  revokedPlayerTokens: { count: number; sample: string[] };
  roundPushesToWarn: { count: number; sample: string[] };
  abandonedGames: { count: number; sample: string[] };
  stalePublishLinks: { count: number; sample: string[] };
  staleAttestDevices: { count: number; sample: string[] };
  // Not day-parameterized — these are always "what's due right now" regardless
  // of the `days` argument, included so the preview gives the full picture.
  managerDeletesDue: { count: number; sample: string[] };
  managersOverCap: { count: number; sample: string[] };
  managersOverCapGraceExpired: { count: number; sample: string[] };
}

const SAMPLE_SIZE = 20;

async function countAndSample<T extends Record<string, unknown>>(
  db: D1Database, sql: string, bindArgs: unknown[], column: string,
): Promise<{ count: number; sample: string[] }> {
  const rows = await db.prepare(sql).bind(...bindArgs).all<T>();
  const values = (rows.results ?? []).map((r) => String(r[column]));
  return { count: values.length, sample: values.slice(0, SAMPLE_SIZE) };
}

// Read-only — computes what WOULD be affected at the given retention window,
// without deleting anything. Used by the manual dash preview.
export async function previewStaleData(env: Env, days: number = DEFAULT_RETENTION_DAYS): Promise<StalePreview> {
  const warnDays = Math.max(days - WARN_LEAD_DAYS, 0);

  const overCapWhere = `
    max_pwa_links IS NOT NULL
    AND (SELECT COUNT(*) FROM player_tokens pt
         WHERE pt.manager_token = manager_lifecycle.manager_token AND pt.revoked_at IS NULL) > max_pwa_links`;

  const [
    revokedPlayerTokens,
    roundPushesToWarn,
    abandonedGames,
    stalePublishLinks,
    staleAttestDevices,
    managerDeletesDue,
    managersOverCap,
    managersOverCapGraceExpired,
  ] = await Promise.all([
    countAndSample(
      env.DB,
      `SELECT token FROM player_tokens WHERE revoked_at IS NOT NULL AND revoked_at < datetime('now', ?)`,
      [`-${days} days`], "token",
    ),
    countAndSample(
      env.DB,
      `SELECT game_token FROM round_pushes WHERE updated_at < datetime('now', ?) AND warned_at IS NULL AND manager_token IS NOT NULL`,
      [`-${warnDays} days`], "game_token",
    ),
    countAndSample(
      env.DB,
      `SELECT game_token FROM round_pushes WHERE updated_at < datetime('now', ?)`,
      [`-${days} days`], "game_token",
    ),
    countAndSample(
      env.DB,
      `SELECT id FROM publish_links WHERE updated_at < datetime('now', ?)`,
      [`-${days} days`], "id",
    ),
    countAndSample(
      env.DB,
      `SELECT key_id FROM attest_devices WHERE updated_at < datetime('now', ?)`,
      [`-${days} days`], "key_id",
    ),
    countAndSample(
      env.DB,
      `SELECT manager_token FROM manager_lifecycle WHERE scheduled_delete_at IS NOT NULL AND scheduled_delete_at < datetime('now')`,
      [], "manager_token",
    ),
    countAndSample(
      env.DB,
      `SELECT manager_token FROM manager_lifecycle WHERE ${overCapWhere}`,
      [], "manager_token",
    ),
    countAndSample(
      env.DB,
      `SELECT manager_token FROM manager_lifecycle
       WHERE link_cap_warned_at IS NOT NULL AND link_cap_warned_at < datetime('now', ?) AND ${overCapWhere}`,
      [`-${LINK_CAP_GRACE_DAYS} days`], "manager_token",
    ),
  ]);

  return {
    days,
    revokedPlayerTokens,
    roundPushesToWarn,
    abandonedGames,
    stalePublishLinks,
    staleAttestDevices,
    managerDeletesDue,
    managersOverCap,
    managersOverCapGraceExpired,
  };
}
