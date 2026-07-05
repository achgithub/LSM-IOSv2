// Cloudflare Access gates this at the edge, but that policy lives outside
// this repo (Zero Trust dashboard config, not version-controlled) — verify
// its JWT in-code too, so a misconfigured/disabled Access policy fails
// closed instead of silently exposing the outage kill-switch and
// league-data sync/wipe actions below. See access-auth.ts.
import { verifyAccessJWT } from "./access-auth";

interface Env {
  UK_DB: D1Database;
  EU_DB: D1Database;
  UK_KV: KVNamespace;
  EU_KV: KVNamespace;
  // Dash-only tokens — same value as the shard's UK_ADMIN_TOKEN / EU_ADMIN_TOKEN
  // but named separately so rotation is unambiguous (WRK_ = this Worker's copy).
  // Needed only to proxy /admin/sync + /admin/probe-standings; phase writes
  // go direct to KV and don't require these.
  WRK_UK_ADMIN_TOKEN?: string;
  WRK_EU_ADMIN_TOKEN?: string;
  // This Access application's team domain + Audience (AUD) tag — both from
  // the Zero Trust dashboard (Access > Applications > this app > Overview).
  // Team domain isn't secret (it's in the login redirect URL); AUD is set
  // via `wrangler secret put CF_ACCESS_AUD`.
  CF_ACCESS_TEAM_DOMAIN?: string;
  CF_ACCESS_AUD?: string;
}

type Shard = "uk" | "eu";
type SyncRow    = { dataset: string; synced_at: string; row_count: number };
type GateState  = { call: number; refresh: number; ts: string | null };
type StatusRow  = { status: string; cnt: number };
type NextFixRow = { kickoff: string; matchday: number | null };
type SeasonPhase = "live" | "closed";

const GATES = ["scores", "fixtures", "standings"] as const;
type GateName = typeof GATES[number];

const SHARD_URLS: Record<Shard, string> = {
  uk: "https://uk-api.sportsmanager.site",
  eu: "https://eu-api.sportsmanager.site",
};

const LEAGUES = [
  { key: "pl",  name: "Premier League", id: "PL",  shard: "uk" as Shard },
  { key: "elc", name: "Championship",   id: "ELC", shard: "uk" as Shard },
  { key: "pd",  name: "La Liga",        id: "PD",  shard: "eu" as Shard },
  { key: "bl1", name: "Bundesliga",     id: "BL1", shard: "eu" as Shard },
  { key: "sa",  name: "Serie A",        id: "SA",  shard: "eu" as Shard },
  { key: "fl1", name: "Ligue 1",        id: "FL1", shard: "eu" as Shard },
  { key: "ded", name: "Eredivisie",     id: "DED", shard: "eu" as Shard },
];

function shardDb(env: Env, shard: Shard): D1Database {
  return shard === "uk" ? env.UK_DB : env.EU_DB;
}

function shardKv(env: Env, shard: Shard): KVNamespace {
  return shard === "uk" ? env.UK_KV : env.EU_KV;
}

function shardToken(env: Env, shard: Shard): string | undefined {
  return shard === "uk" ? env.WRK_UK_ADMIN_TOKEN : env.WRK_EU_ADMIN_TOKEN;
}

function parseInt0(v: string | null): number {
  const n = parseInt(v ?? "0", 10);
  return Number.isFinite(n) ? n : 0;
}

// Phase key is now league-scoped (v2: "{leagueId}:season:phase").
async function fetchPhase(kv: KVNamespace, leagueId: string): Promise<SeasonPhase> {
  const v = await kv.get(`${leagueId}:season:phase`);
  return v === "closed" ? v : "live";
}

// Global client-facing outage flag, shared with worker/'s + worker-api/'s
// src/outage.ts via the same underlying KV namespace per shard — writing it
// here (UK_KV + EU_KV) reaches every route in both Worker types at once.
// Deliberately global, not per-league — see docs/app-attest-status.md.
type OutageFlag = { on: boolean; message?: string };
const OUTAGE_KEY = "outage:flag";

async function fetchOutage(env: Env): Promise<OutageFlag> {
  const raw = await env.UK_KV.get(OUTAGE_KEY);
  if (!raw) return { on: false };
  try {
    const parsed = JSON.parse(raw);
    return { on: !!parsed.on, message: typeof parsed.message === "string" ? parsed.message : undefined };
  } catch {
    return { on: false };
  }
}

async function setOutage(env: Env, on: boolean, message: string | undefined): Promise<OutageFlag> {
  const flag: OutageFlag = { on, message };
  const value = JSON.stringify(flag);
  await Promise.all([env.UK_KV.put(OUTAGE_KEY, value), env.EU_KV.put(OUTAGE_KEY, value)]);
  return flag;
}

function seasonOfDate(d: Date): number {
  const month = d.getUTCMonth() + 1;
  return month >= 7 ? d.getUTCFullYear() : d.getUTCFullYear() - 1;
}

// All fixtures queries are now league-scoped (WHERE league_id = ?).
async function fetchSeason(db: D1Database, leagueId: string): Promise<number | null> {
  const next = await db
    .prepare(`SELECT kickoff FROM fixtures WHERE league_id = ? AND status NOT IN ('FINISHED','CANCELLED') ORDER BY kickoff ASC LIMIT 1`)
    .bind(leagueId)
    .first<{ kickoff: string }>();
  if (next) return seasonOfDate(new Date(next.kickoff));
  const latest = await db
    .prepare(`SELECT kickoff FROM fixtures WHERE league_id = ? ORDER BY kickoff DESC LIMIT 1`)
    .bind(leagueId)
    .first<{ kickoff: string }>();
  return latest ? seasonOfDate(new Date(latest.kickoff)) : null;
}

async function fetchLeague(db: D1Database, kv: KVNamespace, leagueId: string) {
  const kvKeys = [
    `${leagueId}:scores`,
    `${leagueId}:season:phase`,
    ...GATES.flatMap((g) => [`${leagueId}:${g}:call`, `${leagueId}:${g}:refresh`, `${leagueId}:${g}:ts`]),
  ];
  const [syncResult, statusResult, nextFixResult, ...kvVals] = await Promise.all([
    db.prepare("SELECT dataset, synced_at, row_count FROM sync_meta WHERE league_id = ? ORDER BY dataset").bind(leagueId).all<SyncRow>(),
    db.prepare("SELECT status, COUNT(*) as cnt FROM fixtures WHERE league_id = ? GROUP BY status ORDER BY cnt DESC").bind(leagueId).all<StatusRow>(),
    db.prepare("SELECT kickoff, matchday FROM fixtures WHERE league_id = ? AND status IN ('SCHEDULED','TIMED') ORDER BY kickoff ASC LIMIT 1").bind(leagueId).first<NextFixRow>(),
    ...kvKeys.map((k) => kv.get(k)),
  ]);

  const [scoresRaw, phaseRaw, ...gateVals] = kvVals;
  const phase: SeasonPhase = phaseRaw === "closed" ? phaseRaw : "live";

  const gates: Record<GateName, GateState> = {} as Record<GateName, GateState>;
  GATES.forEach((g, i) => {
    const base = i * 3;
    gates[g] = {
      call:    parseInt0(gateVals[base]     ?? null),
      refresh: parseInt0(gateVals[base + 1] ?? null),
      ts:      gateVals[base + 2]           ?? null,
    };
  });

  return {
    sync: syncResult.results,
    statusCounts: statusResult.results,
    nextFixture: nextFixResult ?? null,
    scoresCacheBytes: scoresRaw ? scoresRaw.length : null,
    gates,
    phase,
  };
}

function iconSvg(): Response {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="80" fill="#0d0d0d"/>
  <text x="256" y="320" font-family="ui-monospace,monospace" font-size="200" font-weight="bold"
        fill="#e0e0e0" text-anchor="middle">⚽</text>
</svg>`;
  return new Response(svg, {
    headers: { "Content-Type": "image/svg+xml", "Cache-Control": "public, max-age=86400" },
  });
}

function manifestJson(): Response {
  const m = {
    name: "LMS Dashboard", short_name: "LMS", start_url: "/",
    display: "standalone", background_color: "#0d0d0d", theme_color: "#0d0d0d",
    icons: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any maskable" }],
  };
  return new Response(JSON.stringify(m), {
    headers: { "Content-Type": "application/manifest+json", "Cache-Control": "public, max-age=3600" },
  });
}

function serviceWorkerJs(): Response {
  const sw = `self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',(e)=>e.waitUntil(clients.claim()));
self.addEventListener('fetch',(e)=>e.respondWith(fetch(e.request)));`;
  return new Response(sw, { headers: { "Content-Type": "application/javascript" } });
}

function shellHtml(): Response {
  const rows = LEAGUES.map((l) => {
    const search = (l.name + " " + l.key + " " + l.shard).toLowerCase();
    return `
      <tr class="league-row" data-key="${l.key}" data-search="${search}" data-phase="">
        <td>${l.name}</td>
        <td class="code">${l.key.toUpperCase()}</td>
        <td class="code shard-col">${l.shard.toUpperCase()}</td>
        <td id="season-${l.key}" class="season-col">—</td>
        <td><button id="toggle-${l.key}" class="api-toggle" onclick="toggleApi('${l.key}')">…</button></td>
        <td><button class="details-btn" onclick="toggleDetails('${l.key}')">Details ▾</button></td>
      </tr>
      <tr id="detail-row-${l.key}" class="detail-row" hidden>
        <td colspan="6">
          <div id="d-${l.key}" class="league-data">—</div>
          <h3>Season actions</h3>
          <div class="toggle-hint">Blocked = zero upstream calls, regardless of TTL/cron; serves
          whatever's cached, however stale. Use it for a season-end freeze (most common) or to
          ride out a worker deploy/incident without users seeing errors.</div>
          <div class="season-actions">
            <input id="year-${l.key}" type="number" placeholder="auto (current season)" style="width:9em">
            <button onclick="probeSeason('${l.key}')">Probe (read-only check)</button>
            <button onclick="syncSeason('${l.key}')">Sync now (cutover — replaces D1, switch unchanged)</button>
          </div>
          <div id="season-msg-${l.key}" class="season-msg"></div>
        </td>
      </tr>`;
  }).join("");

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>LMS Dashboard v2</title>
  <link rel="manifest" href="/manifest.json">
  <meta name="theme-color" content="#0d0d0d">
  <link rel="apple-touch-icon" href="/icon.svg">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="LMS">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: ui-monospace, monospace; background: #0d0d0d; color: #e0e0e0;
           padding: 1.5rem; font-size: 14px; max-width: 960px; }
    h1 { font-size: 1.2rem; margin-bottom: 1.2rem; color: #fff; }
    h3 { font-size: 0.75rem; color: #555; text-transform: uppercase; letter-spacing: 0.06em;
         margin: 0.8rem 0 0.4rem; }
    button { background: #1a1a1a; color: #e0e0e0; border: 1px solid #333;
             padding: 0.3rem 0.9rem; font-family: inherit; font-size: 12px;
             cursor: pointer; border-radius: 4px; }
    button:active { background: #222; }
    button:disabled { opacity: 0.4; cursor: default; }
    .league-data { color: #555; font-size: 12px; }
    .toolbar { display: flex; gap: 0.6rem; margin-bottom: 1rem; flex-wrap: wrap; }
    #filter { flex: 1; min-width: 12em; }
    table { width: 100%; border-collapse: collapse; }
    #overview-table { margin-bottom: 1.5rem; }
    th, td { text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid #1a1a1a; }
    th { color: #444; font-weight: normal; font-size: 11px; text-transform: uppercase; }
    td.code { color: #888; letter-spacing: 0.05em; }
    td.num { color: #6cf; }
    td.ts  { color: #888; }
    .missing { color: #553; }
    .shard-col { color: #555; font-size: 11px; }
    .badge { display: inline-block; margin-top: 0.6rem; padding: 0.3rem 0.6rem;
             border-radius: 4px; font-size: 11px; }
    .badge-live   { background: #0d1a0d; color: #4a4; border: 1px solid #1a331a; }
    .badge-flight { background: #1a0a0a; color: #f66; border: 1px solid #330000; }
    .season { color: #e0e0e0; margin-top: 0.6rem; font-size: 13px; }
    .next   { color: #888; font-size: 12px; margin-top: 0.2rem; margin-bottom: 0.2rem; }
    .fetched { color: #333; font-size: 11px; margin-top: 0.6rem; }
    .toggle-hint { font-size: 11px; color: #777; line-height: 1.4; margin-bottom: 0.6rem; }
    .api-toggle { min-width: 8em; font-size: 11px; font-weight: bold;
                  padding: 0.35rem 0.6rem; border-radius: 6px; cursor: pointer; }
    .api-toggle.live    { background: #0d1a0d; color: #4f4; border: 1px solid #2a5; }
    .api-toggle.closed  { background: #260d0d; color: #f55; border: 1px solid #722; }
    .season-actions { display: flex; gap: 0.5rem; margin-bottom: 0.5rem; flex-wrap: wrap; }
    input, select { background: #1a1a1a; color: #e0e0e0; border: 1px solid #333; border-radius: 4px;
            padding: 0.3rem 0.5rem; font-family: inherit; font-size: 12px; }
    .season-msg { font-size: 11px; color: #888; white-space: pre-wrap; }
    .outage-bar { display: flex; align-items: center; gap: 0.6rem; margin-bottom: 1rem;
                  flex-wrap: wrap; padding: 0.6rem; border: 1px solid #260d0d; border-radius: 6px; }
    #outage-message { flex: 1; min-width: 14em; }
    .detail-row td { padding-top: 0.8rem; padding-bottom: 1rem; background: #111; }
    .count { color: #555; font-size: 12px; margin-left: 0.4rem; }
  </style>
</head>
<body>
  <h1>⚽ LMS Dashboard <span style="color:#444;font-size:0.75rem">v2</span></h1>
  <div class="outage-bar">
    <button id="outage-toggle" class="api-toggle" onclick="toggleOutage()">…</button>
    <input id="outage-message" type="text" placeholder="Message shown to clients (optional)">
    <span id="outage-msg" class="season-msg"></span>
  </div>
  <div class="toolbar">
    <input id="filter" type="text" placeholder="Filter by league, code or shard…" oninput="applyFilter()">
    <select id="shardFilter" onchange="applyFilter()">
      <option value="all">All shards</option>
      <option value="uk">UK shard</option>
      <option value="eu">EU shard</option>
    </select>
    <select id="statusFilter" onchange="applyFilter()">
      <option value="all">All statuses</option>
      <option value="live">🟢 Live only</option>
      <option value="closed">🔴 Blocked only</option>
    </select>
    <span class="count" id="rowCount"></span>
  </div>
  <table id="overview-table">
    <thead><tr><th>League</th><th>Code</th><th>Shard</th><th>Season</th><th>Status</th><th></th></tr></thead>
    <tbody id="overview-body">${rows}</tbody>
  </table>
  <script>
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js');

    const loaded = new Set();

    function esc(s) {
      return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }
    function fmt(iso) {
      if (!iso) return '—';
      return new Date(iso).toLocaleString('en-GB', {
        day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit',
        timeZone:'UTC', timeZoneName:'short'
      });
    }
    function fmtSeason(season) {
      if (season === null || season === undefined) return '—';
      return season + '/' + String(season + 1).slice(-2);
    }

    function setOutageButton(on) {
      const btn = document.getElementById('outage-toggle');
      btn.textContent = on ? '🔴 OUTAGE ON — click to end' : '🟢 Service normal — click to start outage';
      btn.className = 'api-toggle ' + (on ? 'closed' : 'live');
      btn.dataset.on = on ? '1' : '';
    }

    async function loadOutage() {
      try {
        const d = await fetch('/outage').then(r => r.json());
        setOutageButton(d.on);
        document.getElementById('outage-message').value = d.message || '';
      } catch (e) {
        document.getElementById('outage-msg').textContent = 'Error loading outage state: ' + e.message;
      }
    }

    async function toggleOutage() {
      const btn = document.getElementById('outage-toggle');
      const next = btn.dataset.on ? 'off' : 'on';
      const message = document.getElementById('outage-message').value.trim();
      if (next === 'on' && !confirm('This blocks every client (iOS + PWA + web) across every league right now. Continue?')) return;
      btn.disabled = true;
      const msg = document.getElementById('outage-msg');
      try {
        const q = '?value=' + next + (message ? '&message=' + encodeURIComponent(message) : '');
        const r = await fetch('/action/outage' + q, { method: 'POST' }).then(r => r.json());
        setOutageButton(r.on);
        msg.textContent = r.on ? 'Outage is ON — all clients are seeing a maintenance message.' : 'Outage is OFF — normal service.';
      } catch (e) {
        msg.textContent = 'Error: ' + e.message;
      } finally {
        btn.disabled = false;
      }
    }

    async function loadOverview() {
      try {
        const d = await fetch('/overview').then(r => r.json());
        d.leagues.forEach(l => {
          setToggle(l.key, l.phase);
          document.querySelector('tr[data-key="' + l.key + '"]').dataset.phase = l.phase;
          document.getElementById('season-' + l.key).textContent = fmtSeason(l.season);
        });
        applyFilter();
      } catch (e) {
        document.getElementById('rowCount').textContent = 'Error loading overview: ' + e.message;
      }
    }

    function applyFilter() {
      const q = document.getElementById('filter').value.toLowerCase();
      const shard = document.getElementById('shardFilter').value;
      const status = document.getElementById('statusFilter').value;
      let shown = 0;
      document.querySelectorAll('#overview-body > tr.league-row').forEach(tr => {
        const matchesText = tr.dataset.search.includes(q);
        const matchesShard = shard === 'all' || tr.dataset.search.includes(shard);
        const matchesStatus = status === 'all' || tr.dataset.phase === status;
        const visible = matchesText && matchesShard && matchesStatus;
        tr.style.display = visible ? '' : 'none';
        if (visible) shown++;
        const detail = document.getElementById('detail-row-' + tr.dataset.key);
        if (detail && !visible) detail.hidden = true;
      });
      document.getElementById('rowCount').textContent = shown + ' league' + (shown === 1 ? '' : 's');
    }

    async function toggleDetails(key) {
      const row = document.getElementById('detail-row-' + key);
      row.hidden = !row.hidden;
      if (!row.hidden && !loaded.has(key)) {
        loaded.add(key);
        await load(key);
      }
    }

    async function load(key) {
      const out = document.getElementById('d-' + key);
      out.textContent = 'Loading…';
      try {
        const d = await fetch('/data/' + key).then(r => r.json());
        setToggle(key, d.phase);
        document.querySelector('tr[data-key="' + key + '"]').dataset.phase = d.phase;

        const datasets = ['fixtures','standings','teams'];
        const syncRows = datasets.map(ds => {
          const r = d.sync.find(s => s.dataset === ds);
          return r
            ? '<tr><td>'+esc(ds)+'</td><td class="num">'+esc(r.row_count)+'</td><td class="ts">'+esc(fmt(r.synced_at))+'</td></tr>'
            : '<tr><td>'+esc(ds)+'</td><td colspan="2" class="missing">no sync yet</td></tr>';
        }).join('');

        const finished  = d.statusCounts.find(s => s.status === 'FINISHED')?.cnt  ?? 0;
        const inPlay    = d.statusCounts.find(s => s.status === 'IN_PLAY')?.cnt   ?? 0;
        const total     = d.statusCounts.reduce((a, s) => a + s.cnt, 0);
        const nextFix   = d.nextFixture
          ? 'Next: matchday '+esc(d.nextFixture.matchday)+' · '+esc(fmt(d.nextFixture.kickoff))
          : 'No upcoming fixtures';
        const seasonLine = '<div class="season">'
          + esc(finished)+' played · '+(inPlay ? esc(inPlay)+' live · ' : '')
          + esc(total - finished - inPlay)+' remaining'
          + '</div><div class="next">'+nextFix+'</div>';

        const gateRows = ['scores','fixtures','standings'].map(g => {
          const gate = d.gates[g];
          const inFlight = gate.call > gate.refresh;
          const status = inFlight ? '<span style="color:#f66">in flight</span>' : '<span style="color:#4a4">settled</span>';
          return '<tr><td>'+esc(g)+'</td><td class="num">'+esc(gate.call)+'/'+esc(gate.refresh)+'</td>'
            + '<td>'+status+'</td><td class="ts">'+esc(fmt(gate.ts))+'</td></tr>';
        }).join('');

        const cacheNote = d.scoresCacheBytes !== null
          ? '<span class="badge badge-live">Scores cache: '+esc((d.scoresCacheBytes/1024).toFixed(1))+' KB</span>'
          : '<span class="badge badge-flight">Scores cache: empty</span>';

        out.innerHTML =
          '<h3>D1 — sync</h3>'
          + '<table><thead><tr><th>Dataset</th><th>Rows</th><th>Last synced</th></tr></thead><tbody>'+syncRows+'</tbody></table>'
          + seasonLine
          + '<h3>KV — gates</h3>'
          + '<table><thead><tr><th>Resource</th><th>call/refresh</th><th>Status</th><th>Last reset</th></tr></thead><tbody>'+gateRows+'</tbody></table>'
          + '<div style="margin-top:0.5rem">'+cacheNote+'</div>'
          + '<div class="fetched">Fetched '+esc(d.fetchedAt)+' · <a href="#" onclick="loaded.delete(\\''+key+'\\'); load(\\''+key+'\\'); return false;" style="color:#6cf">Refresh</a></div>';
      } catch(e) {
        out.textContent = 'Error: ' + e.message;
      }
    }

    function setToggle(key, phase) {
      const btn = document.getElementById('toggle-' + key);
      const isLive = phase !== 'closed';
      btn.textContent = isLive ? '🟢 LIVE' : '🔴 BLOCKED';
      btn.title = isLive ? 'Tap to block' : 'Tap to go live';
      btn.className = 'api-toggle ' + (isLive ? 'live' : 'closed');
      btn.dataset.phase = isLive ? 'live' : 'closed';
    }

    async function toggleApi(key) {
      const btn = document.getElementById('toggle-' + key);
      const next = btn.dataset.phase === 'closed' ? 'live' : 'closed';
      try {
        const r = await fetch('/action/' + key + '/phase?value=' + next, { method: 'POST' }).then(r => r.json());
        if (!r.ok) { alert('Error: ' + (r.error || 'unknown')); return; }
        setToggle(key, r.phase);
        document.querySelector('tr[data-key="' + key + '"]').dataset.phase = r.phase;
        applyFilter();
        const msg = document.getElementById('season-msg-' + key);
        if (msg) msg.textContent = r.phase === 'closed'
          ? 'Blocked — serving cached data only, no upstream calls.'
          : 'Live — normal polling resumed.';
      } catch (e) { alert('Error: ' + e.message); }
    }

    async function probeSeason(key) {
      const msg = document.getElementById('season-msg-' + key);
      const year = document.getElementById('year-' + key).value;
      msg.textContent = 'Probing ' + (year || 'current season') + ' upstream (read-only)…';
      try {
        const q = year ? ('?season=' + year) : '';
        const r = await fetch('/action/' + key + '/probe' + q, { method: 'POST' }).then(r => r.json());
        msg.textContent = r.ok
          ? 'Season ' + r.season + ': ' + r.rowCount + ' rows. Sample team ids: ' + (r.sampleTeamIds || []).join(', ')
          : 'Probe failed: ' + (r.error || 'unknown');
      } catch (e) { msg.textContent = 'Error: ' + e.message; }
    }

    async function syncSeason(key) {
      const msg = document.getElementById('season-msg-' + key);
      const year = document.getElementById('year-' + key).value;
      if (!confirm('Sync ' + (year || 'current season') + ' for ' + key.toUpperCase() + ' now?\\n\\nThis REPLACES teams/fixtures/standings in D1 with exactly this fetch — any other season currently stored is dropped. Phase is left exactly as it is — this does not go Live.')) return;
      msg.textContent = 'Syncing ' + (year || 'current season') + '…';
      try {
        const q = year ? ('?season=' + year) : '';
        const r = await fetch('/action/' + key + '/sync' + q, { method: 'POST' }).then(r => r.json());
        msg.textContent = r.ok ? 'Synced: ' + JSON.stringify(r.synced) + '.' : 'Sync failed: ' + JSON.stringify(r);
        loaded.delete(key);
        if (r.ok) {
          fetch('/overview').then(r => r.json()).then(d => {
            const row = d.leagues.find(l => l.key === key);
            if (row) document.getElementById('season-' + key).textContent = fmtSeason(row.season);
          });
        }
      } catch (e) { msg.textContent = 'Error: ' + e.message; }
    }

    loadOverview();
    loadOutage();
  </script>
</body>
</html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

// Phase writes go direct to KV (key is now league-scoped: "{leagueId}:season:phase").
// This is equivalent to the v1 approach — no need to proxy to the shard Worker.
async function setPhase(kv: KVNamespace, leagueId: string, value: string): Promise<Response> {
  if (value !== "live" && value !== "closed") {
    return Response.json({ ok: false, error: "value must be live|closed" }, { status: 400 });
  }
  await kv.put(`${leagueId}:season:phase`, value);
  return Response.json({ ok: true, phase: value });
}

// Sync/probe proxy to the shard Worker — it holds FOOTBALL_DATA_TOKEN.
// v2 uses a single URL per shard with ?league= routing (no per-league URLs).
async function proxySync(url: string, token: string | undefined, leagueId: string, season: string | null): Promise<Response> {
  if (!token) return Response.json({ ok: false, error: "WRK admin token not configured for this shard" }, { status: 500 });
  const q = season ? `&season=${encodeURIComponent(season)}` : "";
  try {
    const upstream = await fetch(`${url}/admin/sync?league=${leagueId}&what=all${q}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    });
    const body = await upstream.json() as { ok?: boolean; error?: string };
    if (!upstream.ok) return Response.json({ ok: false, error: body.error ?? `HTTP ${upstream.status} from shard` }, { status: upstream.status });
    return Response.json(body);
  } catch (err) {
    return Response.json({ ok: false, error: `Shard unreachable: ${String(err)}` }, { status: 502 });
  }
}

async function proxyProbe(url: string, token: string | undefined, leagueId: string, season: string | null): Promise<Response> {
  if (!token) return Response.json({ ok: false, error: "WRK admin token not configured for this shard" }, { status: 500 });
  const q = season ? `&season=${encodeURIComponent(season)}` : "";
  try {
    const upstream = await fetch(`${url}/admin/probe-standings?league=${leagueId}${q}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const body = await upstream.json() as { ok: boolean; error?: string; season?: number; rowCount?: number; rows?: { teamId: number }[] };
    if (!upstream.ok) return Response.json({ ok: false, error: body.error ?? `HTTP ${upstream.status} from shard` }, { status: upstream.status });
    return Response.json({
      ok: body.ok, error: body.error, season: body.season, rowCount: body.rowCount,
      sampleTeamIds: body.rows?.slice(0, 5).map((r) => r.teamId),
    });
  } catch (err) {
    return Response.json({ ok: false, error: `Shard unreachable: ${String(err)}` }, { status: 502 });
  }
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const accessJwt = req.headers.get("Cf-Access-Jwt-Assertion");
    if (!(await verifyAccessJWT(accessJwt, env.CF_ACCESS_TEAM_DOMAIN, env.CF_ACCESS_AUD))) {
      return new Response("Unauthorized", { status: 403 });
    }

    const { pathname, searchParams } = new URL(req.url);

    if (pathname === "/manifest.json") return manifestJson();
    if (pathname === "/sw.js")         return serviceWorkerJs();
    if (pathname === "/icon.svg")      return iconSvg();

    if (pathname === "/outage") return Response.json(await fetchOutage(env));

    if (pathname === "/action/outage" && req.method === "POST") {
      const value = searchParams.get("value");
      if (value !== "on" && value !== "off") {
        return Response.json({ ok: false, error: "value must be on|off" }, { status: 400 });
      }
      const flag = await setOutage(env, value === "on", searchParams.get("message") ?? undefined);
      return Response.json({ ok: true, ...flag });
    }

    // Overview: one KV read + one indexed D1 lookup per league, in parallel.
    if (pathname === "/overview") {
      const rows = await Promise.all(
        LEAGUES.map(async (l) => ({
          key:    l.key,
          name:   l.name,
          shard:  l.shard,
          phase:  await fetchPhase(shardKv(env, l.shard), l.id),
          season: await fetchSeason(shardDb(env, l.shard), l.id),
        })),
      );
      return Response.json({ leagues: rows });
    }

    if (pathname.startsWith("/data/")) {
      const key = pathname.slice(6);
      const league = LEAGUES.find((l) => l.key === key);
      if (!league) return new Response("not found", { status: 404 });
      const data = await fetchLeague(shardDb(env, league.shard), shardKv(env, league.shard), league.id);
      return Response.json({
        fetchedAt: new Date().toLocaleString("en-GB", {
          day: "2-digit", month: "short", year: "numeric",
          hour: "2-digit", minute: "2-digit", timeZone: "UTC", timeZoneName: "short",
        }),
        ...data,
      });
    }

    const actionMatch = pathname.match(/^\/action\/([a-z0-9]+)\/(phase|sync|probe)$/);
    if (actionMatch && req.method === "POST") {
      const [, key, action] = actionMatch;
      const league = LEAGUES.find((l) => l.key === key);
      if (!league) return new Response("not found", { status: 404 });
      if (action === "phase") return setPhase(shardKv(env, league.shard), league.id, searchParams.get("value") ?? "");
      const season = searchParams.get("season");
      const token  = shardToken(env, league.shard);
      const url    = SHARD_URLS[league.shard];
      if (action === "sync") return proxySync(url, token, league.id, season);
      return proxyProbe(url, token, league.id, season);
    }

    return shellHtml();
  },
} satisfies ExportedHandler<Env>;
