// Registry worker — two jobs, both league-count-agnostic:
//   1. Serve the league manifest the iOS app fetches in the background
//      (Leagues.swift), so adding a league never requires an app update.
//   2. Run the ONLY Cloudflare Cron Trigger in the whole system, fanning out
//      POST /admin/sync-if-due to every league. Each league worker self-gates
//      on its own MAINTENANCE_WINDOW_UTC (see worker/src/routes/admin.ts), so
//      this stays a flat 1 trigger regardless of how many leagues exist.

const MANIFEST_KEY = "manifest";

interface ManifestLeague {
  id: string;
  name: string;
  shortName: string;
  workerBaseURL: string;
  teamsCount: number;
  devOnly?: boolean;
}

interface Manifest {
  app: { name: string; season: string; allowRepeatDefault: boolean };
  homeLeagueId: string;
  leagues: ManifestLeague[];
}

async function getManifest(env: Env): Promise<Manifest | null> {
  const raw = await env.MANIFEST.get(MANIFEST_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as Manifest;
  } catch {
    return null;
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/leagues.json") {
      const manifest = await getManifest(env);
      if (!manifest || manifest.leagues.length === 0) {
        return new Response(JSON.stringify({ error: "manifest unavailable" }), {
          status: 404,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(JSON.stringify(manifest), {
        headers: {
          "content-type": "application/json",
          "cache-control": "max-age=300",
        },
      });
    }
    return new Response(JSON.stringify({ error: "not found" }), {
      status: 404,
      headers: { "content-type": "application/json" },
    });
  },

  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const manifest = await getManifest(env);
    if (!manifest) {
      console.error(JSON.stringify({ msg: "orchestrator: no manifest, skipping fan-out" }));
      return;
    }
    const results = await Promise.allSettled(
      manifest.leagues
        .filter((league) => !league.devOnly)
        .map((league) =>
          fetch(`${league.workerBaseURL}/admin/sync-if-due`, {
            method: "POST",
            headers: { Authorization: `Bearer ${env.OPS_SYNC_TOKEN}` },
          }).then((res) => ({ id: league.id, status: res.status })),
        ),
    );
    console.log(JSON.stringify({ msg: "orchestrator fan-out", results }));
  },
} satisfies ExportedHandler<Env>;
