// Cloud Publish viewer — Cloudflare Pages Function at /l/:region/:id.
//
// The region in the URL identifies which authority worker to call for PIN
// validation. Each regional authority owns its own publish_links rows; the
// snapshot blob lives in the shared BACKUPS R2 bucket. No WORKER_BASE_URL
// env var needed — the authority URL is derived from the region path segment.

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}

function nonce() {
  return crypto.randomUUID().replaceAll("-", "");
}

function formatDate(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return escapeHtml(value);
  return escapeHtml(date.toLocaleString("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }));
}

function sharedHead(title, scriptNonce) {
  return `<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0B1220">
<title>${escapeHtml(title)}</title>
<style>
:root{--bg:#0B1220;--panel:#121C2E;--panel-strong:#17243A;--line:rgba(248,250,252,.14);--line-strong:rgba(248,250,252,.26);--text:#F8FAFC;--muted:#94A3B8;--blue:#3DA8FF;--predictor:#38BDF8;--success:#22C55E;--error:#EF4444;--radius:8px;color-scheme:dark;font-size:17px}
:root.large-text{font-size:20px}
*{box-sizing:border-box}
html{min-height:100%;background:var(--bg)}
body{min-height:100vh;margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;color:var(--text);background:linear-gradient(180deg,rgba(11,18,32,.76),rgba(11,18,32,.96) 44%,#0B1220),url("/background.png") top center/cover no-repeat fixed,var(--bg)}
button,input{font:inherit}
button{cursor:pointer}
button:focus-visible,input:focus-visible{outline:3px solid rgba(61,168,255,.9);outline-offset:3px}
.shell{width:min(100%,58rem);min-height:100vh;margin:0 auto;padding:max(1rem,env(safe-area-inset-top)) clamp(.85rem,3vw,1.5rem) max(1.25rem,env(safe-area-inset-bottom));display:grid;align-content:start;gap:1rem}
.brand{display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.85rem;border:1px solid var(--line);border-radius:var(--radius);background:rgba(18,28,46,.84);backdrop-filter:blur(14px)}
.brand-lockup{display:flex;align-items:center;gap:.75rem;min-width:0}
.brand img{width:3.25rem;height:3.25rem;border-radius:var(--radius);flex:0 0 auto}
p,h1,h2,h3{margin:0}
.wordmark{color:var(--blue);font-size:.74rem;font-weight:900;letter-spacing:.14em}
.app-title{margin-top:.1rem;font-size:clamp(1.05rem,4.2vw,1.35rem);font-weight:850}
.text-toggle{min-height:3rem;padding:.55rem .8rem;border:1px solid var(--line-strong);border-radius:var(--radius);background:rgba(248,250,252,.08);color:var(--text);font-weight:750;white-space:nowrap}
.text-toggle[aria-pressed=true]{border-color:rgba(61,168,255,.75);background:rgba(61,168,255,.16)}
.hero,.panel{border:1px solid var(--line);border-radius:var(--radius);background:rgba(18,28,46,.92);box-shadow:0 1rem 2.5rem rgba(0,0,0,.22)}
.hero,.panel{padding:clamp(1rem,4vw,1.35rem)}
.hero{display:grid;gap:.55rem;border-color:rgba(56,189,248,.28)}
.eyebrow{color:var(--predictor);font-size:.78rem;font-weight:900;letter-spacing:.13em;text-transform:uppercase}
h1{font-size:clamp(1.9rem,8vw,3rem);line-height:1.08}
h2{font-size:clamp(1.35rem,5vw,2rem)}
h3{font-size:1.05rem}
.muted{color:var(--muted);line-height:1.45}
.error{border-color:rgba(239,68,68,.55);color:#FCA5A5}
.form{display:grid;gap:.85rem;margin-top:.35rem}
label{display:grid;gap:.35rem;color:var(--muted);font-weight:750}
input{width:100%;min-height:3.35rem;border:1px solid var(--line-strong);border-radius:var(--radius);padding:.65rem .75rem;background:rgba(11,18,32,.72);color:var(--text);font-size:1.25rem;font-weight:800;letter-spacing:.08em;text-align:center}
.btn{min-height:3.1rem;border:1px solid rgba(56,189,248,.7);border-radius:var(--radius);padding:.75rem 1rem;background:linear-gradient(180deg,rgba(56,189,248,.95),rgba(2,132,199,.95));color:#06121E;font-weight:900}
.grid{display:grid;gap:1rem}
.results-grid{display:grid;gap:1rem}
.row-list{display:grid;gap:.55rem;margin-top:.85rem}
.standing-row,.fixture-row,.points-row{display:grid;grid-template-columns:auto minmax(0,1fr) auto;align-items:center;gap:.7rem;padding:.75rem;border:1px solid var(--line);border-radius:var(--radius);background:rgba(248,250,252,.055)}
.rank{display:inline-grid;place-items:center;min-width:2.2rem;height:2.2rem;border-radius:999px;border:1px solid rgba(56,189,248,.45);background:rgba(56,189,248,.13);color:var(--text);font-weight:900}
.rank.top{border-color:rgba(56,189,248,.85);background:rgba(56,189,248,.22)}
.name{font-weight:850;overflow-wrap:anywhere}
.score,.pts{font-weight:900;color:var(--predictor);white-space:nowrap}
.section-head{display:flex;align-items:end;justify-content:space-between;gap:1rem;margin-bottom:.85rem}
.round-card{display:grid;gap:.8rem}
.split{display:grid;gap:1rem}
.legal{padding:.5rem;color:#64748B;font-size:.82rem;text-align:center}
@media (min-width:760px){.results-grid{grid-template-columns:minmax(18rem,.85fr) minmax(24rem,1.15fr);align-items:start}.wide{grid-column:1/-1}.split{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:420px){.brand{align-items:stretch;flex-direction:column}.standing-row,.fixture-row,.points-row{grid-template-columns:auto minmax(0,1fr)}.score,.pts{grid-column:2}.section-head{display:grid}}
</style>
<script nonce="${scriptNonce}">
(() => {
  const key = "lsm.largeText";
  const apply = (on) => {
    document.documentElement.classList.toggle("large-text", on);
    const btn = document.getElementById("text-size-toggle");
    if (btn) {
      btn.setAttribute("aria-pressed", String(on));
      btn.textContent = on ? "Text: Large" : "Larger text";
    }
  };
  try { apply(localStorage.getItem(key) === "true"); } catch { apply(false); }
  addEventListener("DOMContentLoaded", () => {
    const btn = document.getElementById("text-size-toggle");
    if (!btn) return;
    btn.addEventListener("click", () => {
      const on = !document.documentElement.classList.contains("large-text");
      try { localStorage.setItem(key, String(on)); } catch {}
      apply(on);
    });
    apply(document.documentElement.classList.contains("large-text"));
  });
})();
</script>
</head>`;
}

function brandHeader() {
  return `<header class="brand">
  <div class="brand-lockup">
    <img src="/logo.png" alt="" width="56" height="56">
    <div>
      <p class="wordmark">SPORTS MANAGER</p>
      <p class="app-title">Predictor League</p>
    </div>
  </div>
  <button id="text-size-toggle" class="text-toggle" type="button" aria-pressed="false">Larger text</button>
</header>`;
}

function pinFormPage({ error } = {}, scriptNonce) {
  return `<!doctype html>
<html lang="en">
${sharedHead("LSM Predictor League", scriptNonce)}
<body>
<main class="shell">
${brandHeader()}
<section class="hero">
  <p class="eyebrow">Private league</p>
  <h1>Enter PIN</h1>
  <p class="muted">Use the 6-digit PIN shared by your game manager to view the latest standings and matchdays.</p>
</section>
<section class="panel ${error ? "error" : ""}">
  ${error ? `<p class="error">${escapeHtml(error)}</p>` : ""}
  <form class="form" method="POST">
    <label>PIN
      <input type="password" inputmode="numeric" name="pin" placeholder="000000" autocomplete="one-time-code" autofocus required>
    </label>
    <button class="btn" type="submit">View league</button>
  </form>
</section>
<p class="legal">Not affiliated with, licensed by or endorsed by any football club, league or federation.</p>
</main>
</body>
</html>`;
}

function fixtureRow(f) {
  const hasScore = f.homeScore != null && f.awayScore != null;
  return `<div class="fixture-row">
    <span class="rank">v</span>
    <span class="name">${escapeHtml(f.homeTeamName)} v ${escapeHtml(f.awayTeamName)}</span>
    <span class="score">${hasScore ? `${escapeHtml(f.homeScore)}-${escapeHtml(f.awayScore)}` : formatDate(f.kickoff)}</span>
  </div>`;
}

function pointsRow(res) {
  return `<div class="points-row">
    <span class="rank">+</span>
    <span class="name">${escapeHtml(res.playerName)}</span>
    <span class="pts">${escapeHtml(res.points)} pts</span>
  </div>`;
}

function standingsSection(snapshot) {
  const rows = (snapshot.standings ?? []).map((s) => `
    <div class="standing-row">
      <span class="rank ${Number(s.position) <= 3 ? "top" : ""}">${escapeHtml(s.position)}</span>
      <span class="name">${escapeHtml(s.playerName)}</span>
      <span class="pts">${escapeHtml(s.points)} pts</span>
    </div>`).join("");
  return `<section class="panel">
    <div class="section-head">
      <h2>Standings</h2>
      <p class="muted">${escapeHtml((snapshot.standings ?? []).length)} players</p>
    </div>
    <div class="row-list">${rows || `<p class="muted">No standings yet.</p>`}</div>
  </section>`;
}

function recentRoundsSection(snapshot) {
  const rounds = (snapshot.recentRounds ?? []).map((r) => `
    <article class="panel round-card">
      <div class="section-head">
        <h3>Matchday ${escapeHtml(r.roundNumber)}</h3>
        <p class="muted">Recent results</p>
      </div>
      <div class="row-list">${(r.fixtures ?? []).map(fixtureRow).join("") || `<p class="muted">No fixtures.</p>`}</div>
      <div class="row-list">${(r.results ?? []).map(pointsRow).join("") || `<p class="muted">No player points.</p>`}</div>
    </article>`).join("");
  return `<section class="grid">${rounds || `<section class="panel"><h2>Recent matchdays</h2><p class="muted">No recent results yet.</p></section>`}</section>`;
}

function nextFixturesSection(snapshot) {
  const fixtures = snapshot.nextFixtures ?? [];
  if (!fixtures.length) return "";
  return `<section class="panel wide">
    <div class="section-head">
      <h2>Next Matchday</h2>
      <p class="muted">${escapeHtml(fixtures.length)} fixtures</p>
    </div>
    <div class="row-list">${fixtures.map(fixtureRow).join("")}</div>
  </section>`;
}

function resultsPage(snapshot, scriptNonce) {
  return `<!doctype html>
<html lang="en">
${sharedHead(snapshot.gameName || "Predictor League", scriptNonce)}
<body>
<main class="shell">
${brandHeader()}
<section class="hero">
  <p class="eyebrow">League table</p>
  <h1>${escapeHtml(snapshot.gameName)}</h1>
  <p class="muted">Updated ${formatDate(snapshot.generatedAt)}. Recent matchdays and the next fixtures are shown below.</p>
</section>
<div class="results-grid">
  ${standingsSection(snapshot)}
  ${recentRoundsSection(snapshot)}
  ${nextFixturesSection(snapshot)}
</div>
<p class="legal">Not affiliated with, licensed by or endorsed by any football club, league or federation.</p>
</main>
</body>
</html>`;
}

function html(body, scriptNonce, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": `default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; script-src 'nonce-${scriptNonce}'; form-action 'self'; base-uri 'none'`,
    },
  });
}

const VALID_REGION = /^[a-z]{2,8}$/;

export async function onRequestGet({ params }) {
  if (!VALID_REGION.test(params.region)) {
    return new Response("Not found", { status: 404 });
  }
  const n = nonce();
  return html(pinFormPage({}, n), n);
}

export async function onRequestPost({ request, params }) {
  if (!VALID_REGION.test(params.region)) {
    return new Response("Not found", { status: 404 });
  }
  const n = nonce();
  const form = await request.formData();
  const pin = form.get("pin");
  if (!pin) return html(pinFormPage({ error: "PIN is required" }, n), n, 400);

  const authorityBase = `https://api.${params.region}.sportsmanager.site`;
  const resp = await fetch(`${authorityBase}/publish/${params.id}/unlock`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pin }),
  });

  if (resp.status === 401) return html(pinFormPage({ error: "Incorrect PIN" }, n), n, 401);
  if (resp.status === 404) return html(pinFormPage({ error: "This link no longer exists" }, n), n, 404);
  if (resp.status === 429) return html(pinFormPage({ error: "Too many attempts — try again later" }, n), n, 429);
  if (!resp.ok) return html(pinFormPage({ error: "Something went wrong — please try again" }, n), n, 502);

  const snapshot = await resp.json();
  return html(resultsPage(snapshot, n), n);
}
