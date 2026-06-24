// LSM Player App — anonymous submission PWA (SKELETON).
//
// The token in the URL (/s/<uuid>) is the only credential. We read it, ask the
// Worker what's actionable, render it, and POST the player's choice back as a
// PENDING submission. Nothing here writes a real pick/prediction — the manager
// approves in the LSM app. See worker/src/routes/submissions.ts.

// TODO: point at the real v2 shard host once provisioned (see worker/wrangler.jsonc).
const API_BASE = "https://uk.sportsmanager.site";

/** Pull the token out of /s/<uuid> (or ?token=<uuid> in dev). */
function getToken() {
  const m = location.pathname.match(/\/s\/([0-9a-f-]{16,})/i);
  if (m) return m[1];
  return new URLSearchParams(location.search).get("token");
}

async function loadActionable(token) {
  // GET /s/:token → { mode, game, items } describing what to show right now.
  const res = await fetch(`${API_BASE}/s/${token}`);
  if (!res.ok) throw new Error(`load failed: ${res.status}`);
  return res.json();
}

async function submit(token, payload) {
  // POST /s/:token → enqueues a 'pending' submission (NOT a live pick/prediction).
  const res = await fetch(`${API_BASE}/s/${token}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`submit failed: ${res.status}`);
  return res.json();
}

function render(state) {
  const el = document.getElementById("content");
  el.replaceChildren(); // clear without innerHTML
  const p = document.createElement("p");
  if (state.error) {
    p.className = "error";
    p.textContent = state.error; // textContent, never innerHTML — values may be server/player-sourced
    el.append(p);
    return;
  }
  // TODO: render mode-specific UI by building DOM nodes + textContent (NOT
  // innerHTML) so team names / player input from the API can't inject markup:
  //   LMS       → list the round's still-available teams, pick one.
  //   Predictor → list this week's fixtures, enter a home/away score per fixture.
  p.className = "muted";
  p.textContent = "Skeleton — actionable view renders here.";
  el.append(p);
}

async function main() {
  const token = getToken();
  if (!token) {
    render({ error: "This link is missing its token." });
    return;
  }
  try {
    const state = await loadActionable(token); // stubbed endpoint → 501 for now
    render(state);
  } catch (e) {
    render({ error: "Couldn't load your link. It may have expired." });
    console.error(e);
  }
}

// Exported for the eventual submit-button wiring.
export { submit };
main();
