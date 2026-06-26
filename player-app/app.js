// LSM Player App — anonymous submission PWA (Phase 3).
//
// The token in the URL (/s/<uuid>) is the only credential. On load we fetch
// GET /s/:token to find out what's actionable right now (the open round for
// the player's game), render it, and POST the player's choice back as a
// PENDING submission. Nothing here writes a real pick/prediction — the manager
// approves in the LSM app. See worker/src/routes/submissions.ts.
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

async function fetchActionable(token) {
  const res = await fetch(`${API_BASE}/s/${token}`);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Server error ${res.status}`);
  }
  return res.json();
}

async function postSubmission(token, payload) {
  const res = await fetch(`${API_BASE}/s/${token}`, {
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
 * state shape:
 *   { loading: true }
 *   { error: "..." }
 *   { mode, playerName, roundNumber, deadline, fixtures, eligibleTeamIds?,
 *     priorSubmission?, submitted: true, submitError: "..." }
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

  // Header
  const header = el("h2", null, `Hi ${state.playerName}`);
  header.style.margin = "0 0 0.5rem";
  frag.appendChild(header);

  const sub = el("p", "muted", `Round ${state.roundNumber}`);
  sub.style.margin = "0 0 1rem";
  frag.appendChild(sub);

  if (state.deadline) {
    const d = new Date(state.deadline);
    const deadline = el("p", "small muted", `Deadline: ${d.toLocaleString()}`);
    frag.appendChild(deadline);
  }

  // Prior submission banner
  if (state.priorSubmission && !state.submitted) {
    const prior = state.priorSubmission;
    const banner = el("div", "card");
    banner.style.marginBottom = "1rem";
    const statusText = prior.status === "pending"
      ? "Your pick is pending manager approval."
      : prior.status === "approved"
      ? "Your pick has been approved ✓"
      : "Your pick was rejected.";
    banner.appendChild(el("p", "muted small", statusText));
    if (prior.status !== "approved") {
      banner.appendChild(el("p", "small", "You can submit again to update it."));
    }
    frag.appendChild(banner);
  }

  if (state.submitted) {
    const ok = el("p", null, "✓ Submitted! Your pick is pending manager approval.");
    ok.style.fontWeight = "600";
    frag.appendChild(ok);
    if (state.submitError) frag.appendChild(el("p", "error", state.submitError));
    setContent(root, frag);
    return;
  }

  // Mode-specific input
  if (state.mode === "lms") {
    renderLMS(frag, state, token);
  } else if (state.mode === "predictor") {
    renderPredictor(frag, state, token);
  } else {
    frag.appendChild(el("p", "error", `Unknown game mode: ${state.mode}`));
  }

  setContent(root, frag);
}

// ── LMS renderer ─────────────────────────────────────────────────────────────

function renderLMS(frag, state, token) {
  // eligibleTeams is [{id, name}], ordered by priority (the server computed this).
  // If absent (shouldn't happen for LMS), fall back to all fixture teams.
  const eligibleTeams = state.eligibleTeams ?? [];

  frag.appendChild(el("p", null, "Pick a team for this round:"));

  if (eligibleTeams.length === 0) {
    frag.appendChild(el("p", "muted", "No eligible teams found. Contact your manager."));
    return;
  }

  const card = el("div", "card");
  for (const team of eligibleTeams) {
    const btn = el("button", "pick-btn", team.name);
    btn.addEventListener("click", () => submitLMS(token, team.id, team.name, state));
    card.appendChild(btn);
  }
  frag.appendChild(card);

  frag.appendChild(el("p", "small muted", "Pick the team you think will win (or survive) this round."));
}

async function submitLMS(token, teamId, teamName, state) {
  try {
    await postSubmission(token, { teamId });
    updateSubmitState({ ...state, submitted: true }, token);
  } catch (e) {
    updateSubmitState({ ...state, submitError: e.message }, token);
  }
}

// ── Predictor renderer ────────────────────────────────────────────────────────

function renderPredictor(frag, state, token) {
  frag.appendChild(el("p", null, "Enter your score predictions:"));

  const inputs = [];

  for (const f of state.fixtures) {
    const card = el("div", "card");
    card.style.marginBottom = "0.75rem";

    const label = el("p", null, `${f.home} vs ${f.away}`);
    label.style.fontWeight = "500";
    label.style.margin = "0 0 0.5rem";
    card.appendChild(label);

    if (f.kickoff) {
      const ko = el("p", "small muted", `KO: ${new Date(f.kickoff).toLocaleString()}`);
      ko.style.margin = "0 0 0.75rem";
      card.appendChild(ko);
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

    card.appendChild(row);
    frag.appendChild(card);
    inputs.push({ fixtureId: f.fixtureId, homeInput, awayInput });
  }

  const submitBtn = el("button", "submit-btn", "Submit Predictions");
  submitBtn.addEventListener("click", () => submitPredictor(token, inputs, state));
  frag.appendChild(submitBtn);
}

async function submitPredictor(token, inputs, state) {
  const scores = inputs.map(({ fixtureId, homeInput, awayInput }) => ({
    fixtureId,
    home: parseInt(homeInput.value, 10) || 0,
    away: parseInt(awayInput.value, 10) || 0,
  }));

  try {
    await postSubmission(token, { scores });
    updateSubmitState({ ...state, submitted: true }, token);
  } catch (e) {
    updateSubmitState({ ...state, submitError: e.message }, token);
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

let _currentState = null;
let _currentToken = null;

function updateSubmitState(state, token) {
  _currentState = state;
  _currentToken = token;
  render(state, token);
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function main() {
  const token = getToken();
  if (!token) {
    render({ error: "This link is missing its token. Check the URL and try again." }, null);
    return;
  }

  render({ loading: true }, token);

  try {
    const data = await fetchActionable(token);
    render(data, token);
  } catch (e) {
    render({ error: e.message || "Couldn't load your link. It may have expired or been revoked." }, token);
  }
}

main();
