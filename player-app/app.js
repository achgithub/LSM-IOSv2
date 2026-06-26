// LSM Player App — anonymous submission PWA (Phase 4).
//
// The token in the URL (/s/<uuid>) is the only credential. On load we fetch
// GET /s/:token to get all active games for this player, render them, and
// POST to /s/:token/games/:gameToken to submit. Nothing here writes a real
// pick/prediction — the manager approves in the LSM app.
// See worker/src/routes/submissions.ts.
//
// No build step. Plain HTML/JS. textContent only — no innerHTML — so team
// names and player input from the API can never inject markup.

const API_BASE = "https://lsm-uk-worker.sportsmanager.workers.dev";

// ── Token ────────────────────────────────────────────────────────────────────

/** Pull the token out of /s/<uuid> (or ?token=<uuid> in dev). */
function getToken() {
  const m = location.pathname.match(/\/s\/([0-9a-f-]{16,})/i);
  if (m) return m[1];
  return new URLSearchParams(location.search).get("token");
}

// ── API ───────────────────────────────────────────────────────────────────────

async function fetchPlayer(token) {
  const res = await fetch(`${API_BASE}/s/${token}`);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Server error ${res.status}`);
  }
  return res.json();
}

async function postSubmission(token, gameToken, payload) {
  const res = await fetch(`${API_BASE}/s/${token}/games/${gameToken}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Submit failed ${res.status}`);
  }
  return res.json();
}

// ── DOM helpers ───────────────────────────────────────────────────────────────

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;  // textContent, never innerHTML
  return e;
}

function setContent(root, ...children) {
  root.replaceChildren(...children);
}

// ── Render ────────────────────────────────────────────────────────────────────

/**
 * Top-level render. State shape:
 *   { loading: true }
 *   { error: "..." }
 *   { playerName, games: [...] }
 */
function render(state, token) {
  const root = document.getElementById("content");

  if (state.loading) {
    setContent(root, el("p", "muted", "Loading your link…"));
    return;
  }

  if (state.error) {
    setContent(root, el("p", "error", state.error));
    return;
  }

  const frag = document.createDocumentFragment();

  const header = el("h2", null, `Hi ${state.playerName}`);
  header.style.margin = "0 0 1rem";
  frag.appendChild(header);

  if (!state.games || state.games.length === 0) {
    frag.appendChild(el("p", "muted", "No active rounds right now. Check back when your manager opens the next round."));
    setContent(root, frag);
    return;
  }

  for (const game of state.games) {
    frag.appendChild(renderGame(game, token));
  }

  setContent(root, frag);
}

/**
 * Render one game card. Each game tracks its own submitted state independently.
 * game shape: { gameToken, mode, roundNumber, deadline, fixtures,
 *               jokerEnabled?, managerSuffix?, eligibleTeams?,
 *               priorSubmission?, _submitted?, _submitError?, _jokerFixtureId? }
 */
function renderGame(game, token) {
  const card = el("div", "card");
  card.style.marginBottom = "1.5rem";

  const title = el("p", null, `Round ${game.roundNumber}`);
  title.style.fontWeight = "600";
  title.style.margin = "0 0 0.25rem";
  card.appendChild(title);

  if (game.managerSuffix) {
    card.appendChild(el("p", "small muted", `Manager: ${game.managerSuffix}`));
  }

  if (game.deadline) {
    const d = new Date(game.deadline);
    card.appendChild(el("p", "small muted", `Deadline: ${d.toLocaleString()}`));
  }

  // Prior submission banner
  if (game.priorSubmission && !game._submitted) {
    const prior = game.priorSubmission;
    const banner = el("div", null);
    banner.style.marginBottom = "0.75rem";
    const statusText = prior.status === "pending"
      ? "Your pick is pending manager approval."
      : prior.status === "approved"
      ? "Your pick has been approved ✓"
      : "Your pick was rejected.";
    const statusEl = el("p", "muted small", statusText);
    if (prior.status === "approved") statusEl.style.color = "#4caf50";
    banner.appendChild(statusEl);
    if (prior.status === "approved") {
      card.appendChild(banner);
      return card;  // approved — no re-submission
    }
    banner.appendChild(el("p", "small", "You can submit again to update it."));
    card.appendChild(banner);
  }

  if (game._submitted) {
    const ok = el("p", null, "✓ Submitted! Your pick is pending manager approval.");
    ok.style.fontWeight = "600";
    card.appendChild(ok);
    return card;
  }

  if (game._submitError) {
    card.appendChild(el("p", "error", game._submitError));
  }

  // Mode-specific input
  if (game.mode === "lms") {
    renderLMS(card, game, token);
  } else if (game.mode === "predictor") {
    renderPredictor(card, game, token);
  } else {
    card.appendChild(el("p", "error", `Unknown game mode: ${game.mode}`));
  }

  return card;
}

// ── LMS renderer ─────────────────────────────────────────────────────────────

function renderLMS(container, game, token) {
  const eligibleTeams = game.eligibleTeams ?? [];

  container.appendChild(el("p", null, "Pick a team for this round:"));

  if (eligibleTeams.length === 0) {
    container.appendChild(el("p", "muted", "No eligible teams found. Contact your manager."));
    return;
  }

  const teamList = el("div", null);
  teamList.style.marginBottom = "0.5rem";
  for (const team of eligibleTeams) {
    const btn = el("button", "pick-btn", team.name);
    btn.addEventListener("click", () => submitLMS(token, game, team.id, team.name));
    teamList.appendChild(btn);
  }
  container.appendChild(teamList);
  container.appendChild(el("p", "small muted", "Pick the team you think will win (or survive) this round."));
}

async function submitLMS(token, game, teamId, teamName) {
  try {
    await postSubmission(token, game.gameToken, { teamId, teamName });
    updateGameState(game, { _submitted: true });
  } catch (e) {
    updateGameState(game, { _submitError: e.message });
  }
}

// ── Predictor renderer ────────────────────────────────────────────────────────

function renderPredictor(container, game, token) {
  if (game.jokerEnabled) {
    const hint = el("p", "small muted", "★ Tap a fixture to mark it as your Joker (doubles points for that match).");
    hint.style.marginBottom = "0.75rem";
    container.appendChild(hint);
  }

  container.appendChild(el("p", null, "Enter your score predictions:"));

  const inputs = [];

  for (const f of game.fixtures) {
    const fixtureCard = el("div", null);
    fixtureCard.style.marginBottom = "0.75rem";

    // Fixture label row (with joker toggle if enabled)
    const labelRow = el("div", null);
    labelRow.style.display = "flex";
    labelRow.style.alignItems = "center";
    labelRow.style.gap = "0.5rem";
    labelRow.style.marginBottom = "0.5rem";

    const label = el("span", null, `${f.home} vs ${f.away}`);
    label.style.fontWeight = "500";
    labelRow.appendChild(label);

    if (game.jokerEnabled) {
      const jokerBtn = el("button", "joker-btn", "★ Joker");
      jokerBtn.dataset.fixtureId = f.fixtureId;
      const isActive = game._jokerFixtureId === f.fixtureId;
      jokerBtn.className = isActive ? "joker-btn joker-btn--active" : "joker-btn";
      jokerBtn.addEventListener("click", () => {
        const next = game._jokerFixtureId === f.fixtureId ? null : f.fixtureId;
        updateGameState(game, { _jokerFixtureId: next });
      });
      labelRow.appendChild(jokerBtn);
    }

    fixtureCard.appendChild(labelRow);

    if (f.kickoff) {
      const ko = el("p", "small muted", `KO: ${new Date(f.kickoff).toLocaleString()}`);
      ko.style.margin = "0 0 0.5rem";
      fixtureCard.appendChild(ko);
    }

    const row = el("div", null);
    row.style.display = "flex";
    row.style.alignItems = "center";
    row.style.gap = "0.5rem";

    const homeInput = el("input");
    homeInput.type = "number";
    homeInput.min = "0";
    homeInput.max = "99";
    homeInput.placeholder = "0";
    homeInput.style.width = "3.5rem";
    homeInput.style.textAlign = "center";

    const sep = el("span", null, "–");

    const awayInput = el("input");
    awayInput.type = "number";
    awayInput.min = "0";
    awayInput.max = "99";
    awayInput.placeholder = "0";
    awayInput.style.width = "3.5rem";
    awayInput.style.textAlign = "center";

    row.appendChild(el("span", "small", f.home));
    row.appendChild(homeInput);
    row.appendChild(sep);
    row.appendChild(awayInput);
    row.appendChild(el("span", "small", f.away));

    fixtureCard.appendChild(row);
    container.appendChild(fixtureCard);
    inputs.push({ fixtureId: f.fixtureId, homeInput, awayInput });
  }

  const submitBtn = el("button", "submit-btn", "Submit Predictions");
  submitBtn.addEventListener("click", () => submitPredictor(token, game, inputs));
  container.appendChild(submitBtn);
}

async function submitPredictor(token, game, inputs) {
  const scores = inputs.map(({ fixtureId, homeInput, awayInput }) => ({
    fixtureId,
    home: parseInt(homeInput.value, 10) || 0,
    away: parseInt(awayInput.value, 10) || 0,
    isJoker: game.jokerEnabled && game._jokerFixtureId === fixtureId,
  }));

  try {
    await postSubmission(token, game.gameToken, { scores });
    updateGameState(game, { _submitted: true });
  } catch (e) {
    updateGameState(game, { _submitError: e.message });
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

let _state = null;
let _token = null;

function updateGameState(game, patch) {
  Object.assign(game, patch);
  render(_state, _token);
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function main() {
  const token = getToken();
  if (!token) {
    render({ error: "This link is missing its token. Check the URL and try again." }, null);
    return;
  }

  _token = token;
  _state = { loading: true };
  render(_state, token);

  try {
    _state = await fetchPlayer(token);
    render(_state, token);
  } catch (e) {
    _state = { error: e.message || "Couldn't load your link. It may have expired or been revoked." };
    render(_state, token);
  }
}

main();
