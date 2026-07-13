// ── LSM Cron handler ──────────────────────────────────────────────────────────
// runDailySync (per-league football-data.org refresh), called from index.ts
// scheduled. The daily D1/R2 cleanup job moved to worker-api/src/cron.ts (#6)
// — it operates on authority-only tables (player_tokens, manager_backups,
// manager_lifecycle, …) that don't exist in this shard's schema.

import { regionSecret } from "./auth";
import { getAllLeagues } from "./db";
import { FootballDataProvider } from "./football";
import { runMaintenance } from "./sync";

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
