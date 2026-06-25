// Cloud Publish viewer — Cloudflare Pages Function at /l/:id (§0).
//
// Deliberately has NO D1/R2 bindings of its own: the Worker already validates
// the PIN server-side and is the only thing that ever touches the blob (see
// worker/src/routes/publish.ts `/publish/:id/unlock`). This Function is just
// a PIN form + renderer that calls that one endpoint — keeping this Pages
// project's setup to "static site + one env var", no secrets, no bindings.
//
// Required Pages env var: WORKER_BASE_URL (e.g. https://lsm-uk-worker.<acct>.workers.dev)
// — either regional shard works, publish data isn't league-scoped.

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}

function pinFormPage({ error } = {}) {
  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>LSM Predictor League</title>
<style>body{font-family:-apple-system,sans-serif;max-width:420px;margin:48px auto;padding:0 16px}
input{font-size:1.1em;padding:8px;width:100%;box-sizing:border-box}
button{font-size:1.1em;padding:10px;width:100%;margin-top:12px}
.error{color:#c00}</style></head>
<body>
<h2>Enter PIN</h2>
${error ? `<p class="error">${escapeHtml(error)}</p>` : ""}
<form method="POST">
<input type="password" inputmode="numeric" name="pin" placeholder="PIN" autofocus required>
<button type="submit">View</button>
</form>
</body></html>`;
}

function resultsPage(snapshot) {
  // The blob came from R2 as untyped JSON (the Worker stores whatever the
  // attested app posted to /publish without validating shape) — escape EVERY
  // interpolated field, not just the ones expected to be strings. A "number"
  // field is just as attacker-controllable as a name field.
  const fixtureRow = (f) =>
    `<tr><td>${escapeHtml(f.homeTeamName)} v ${escapeHtml(f.awayTeamName)}</td><td>${
      f.homeScore != null ? `${escapeHtml(f.homeScore)}-${escapeHtml(f.awayScore)}` : "—"
    }</td></tr>`;

  const roundSection = (r) => `
    <h3>Matchday ${escapeHtml(r.roundNumber)}</h3>
    <table><tbody>${r.fixtures.map(fixtureRow).join("")}</tbody></table>
    <table><tbody>${r.results
      .map((res) => `<tr><td>${escapeHtml(res.playerName)}</td><td>${escapeHtml(res.points)} pts</td></tr>`)
      .join("")}</tbody></table>`;

  const standingsRows = snapshot.standings
    .map((s) => `<tr><td>${escapeHtml(s.position)}</td><td>${escapeHtml(s.playerName)}</td><td>${escapeHtml(s.points)}</td></tr>`)
    .join("");

  const nextFixtures = snapshot.nextFixtures.map(fixtureRow).join("");

  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(snapshot.gameName)}</title>
<style>body{font-family:-apple-system,sans-serif;max-width:560px;margin:24px auto;padding:0 16px}
table{width:100%;border-collapse:collapse;margin-bottom:16px}
td{padding:4px 8px;border-bottom:1px solid #eee}
h1,h2,h3{margin-top:28px}</style></head>
<body>
<h1>${escapeHtml(snapshot.gameName)}</h1>

<h2>Standings</h2>
<table><tbody>${standingsRows}</tbody></table>

${snapshot.recentRounds.map(roundSection).join("")}

${snapshot.nextFixtures.length ? `<h2>Next Matchday</h2><table><tbody>${nextFixtures}</tbody></table>` : ""}

<p style="color:#888;font-size:0.85em">Not affiliated with, licensed by or endorsed by any football club, league or federation.</p>
</body></html>`;
}

function html(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // Belt-and-suspenders alongside escapeHtml above: no inline/external
      // scripts can run even if a field escapes unescaped.
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
    },
  });
}

export async function onRequestGet() {
  return html(pinFormPage());
}

export async function onRequestPost({ request, params, env }) {
  const form = await request.formData();
  const pin = form.get("pin");
  if (!pin) return html(pinFormPage({ error: "PIN is required" }), 400);

  const workerBase = env.WORKER_BASE_URL;
  const resp = await fetch(`${workerBase}/publish/${params.id}/unlock`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pin }),
  });

  if (resp.status === 401) return html(pinFormPage({ error: "Incorrect PIN" }), 401);
  if (resp.status === 404) return html(pinFormPage({ error: "This link no longer exists" }), 404);
  if (!resp.ok) return html(pinFormPage({ error: "Something went wrong — please try again" }), 502);

  const snapshot = await resp.json();
  return html(resultsPage(snapshot));
}
