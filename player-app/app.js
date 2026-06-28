// LSM Player App - anonymous submission PWA.
//
// The token in the URL (/s/<uuid>) is the only credential. On load we fetch
// GET /s/:token to get all active games for this player, render them, and
// POST to /s/:token/games/:gameToken to submit. Nothing here writes a real
// pick/prediction - the manager approves in the LSM app.

const API_BASE = "https://lsm-uk-worker.sportsmanager.workers.dev";
const TOKEN_STORAGE_KEY = "lsm.playerSubmissionToken";
const LARGE_TEXT_STORAGE_KEY = "lsm.largeText";
const TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let _deferredInstallPrompt = null;
let _saveStatus = null;
let _state = null;
let _token = null;

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  _deferredInstallPrompt = event;
  updateSaveLinkAction(_token);
  if (_state && _token) render(_state, _token);
});

// -- Preferences --------------------------------------------------------------

function getLargeTextPreference() {
  try {
    return localStorage.getItem(LARGE_TEXT_STORAGE_KEY) === "true";
  } catch {
    return false;
  }
}

function setLargeTextPreference(on) {
  try {
    localStorage.setItem(LARGE_TEXT_STORAGE_KEY, String(on));
  } catch {
    // The visual preference still applies for this page view.
  }
  applyLargeTextPreference(on);
}

function applyLargeTextPreference(on = getLargeTextPreference()) {
  document.documentElement.classList.toggle("large-text", on);
  const btn = document.getElementById("text-size-toggle");
  if (!btn) return;
  btn.setAttribute("aria-pressed", String(on));
  btn.textContent = on ? "Text L" : "Text +";
}

function setupTextSizeToggle() {
  const btn = document.getElementById("text-size-toggle");
  if (!btn) return;
  btn.addEventListener("click", () => {
    setLargeTextPreference(!document.documentElement.classList.contains("large-text"));
  });
  applyLargeTextPreference();
}

function setupSaveLinkAction() {
  const btn = document.getElementById("save-link-action");
  if (!btn) return;
  btn.addEventListener("click", savePrivateLink);
  updateSaveLinkAction(_token);
}

function updateSaveLinkAction(token) {
  const btn = document.getElementById("save-link-action");
  if (!btn) return;
  const show = Boolean(token) && !isStandalone();
  btn.hidden = !show;
  if (!show) return;
  btn.textContent = _saveStatus === "Use the browser menu to add it." ? "Use menu" : "Save link";
  const help = _deferredInstallPrompt
    ? "Install this app with your private player link."
    : "Use the browser menu to add this private link to your Home Screen.";
  btn.title = _saveStatus ?? help;
  btn.setAttribute("aria-label", help);
}

// -- Token --------------------------------------------------------------------

function getToken() {
  const m = location.pathname.match(/\/s\/([0-9a-f-]{36})(?:\/|$)/i);
  const token = m?.[1] ?? new URLSearchParams(location.search).get("token");
  if (!token || !TOKEN_RE.test(token)) return null;
  return token.toLowerCase();
}

function rememberToken(token) {
  try {
    localStorage.setItem(TOKEN_STORAGE_KEY, token);
  } catch {
    // Storage can be unavailable in private browsing; the URL token still works.
  }
}

function getRememberedToken() {
  try {
    const token = localStorage.getItem(TOKEN_STORAGE_KEY);
    return token && TOKEN_RE.test(token) ? token.toLowerCase() : null;
  } catch {
    return null;
  }
}

// -- API ----------------------------------------------------------------------

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

// -- DOM helpers --------------------------------------------------------------

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

function setContent(root, ...children) {
  root.replaceChildren(...children);
}

function chip(text, cls = "") {
  return el("span", `chip ${cls}`.trim(), text);
}

function formatDate(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString([], {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).replace(/,/g, "");
}

function fixtureKickoff(value) {
  const node = el("span", "fixture-kickoff");
  if (!value) return node;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    node.textContent = value;
    return node;
  }
  node.append(
    el("span", null, date.toLocaleDateString([], { day: "numeric", month: "short" })),
    el("span", null, date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }))
  );
  return node;
}

// -- Render -------------------------------------------------------------------

function render(state, token) {
  const root = document.getElementById("content");
  updateSaveLinkAction(token);

  if (state.loading) {
    setContent(root, renderNotice("Loading your link", "Checking what your manager has opened for you."));
    return;
  }

  if (state.error) {
    setContent(root, renderNotice("We couldn't open this link", state.error, "error"));
    return;
  }

  const pendingCount = pendingGameCount(state.games ?? []);

  const frag = document.createDocumentFragment();
  frag.appendChild(renderHero(state, pendingCount));

  if (!state.games || state.games.length === 0) {
    frag.appendChild(renderNotice(
      "No active rounds right now",
      "Check back when your manager opens the next round."
    ));
    setContent(root, frag);
    return;
  }

  const list = el("div", "game-list");
  for (const game of state.games) {
    list.appendChild(renderGame(game, token));
  }
  frag.appendChild(list);
  setContent(root, frag);
}

function needsPlayerAction(game) {
  if (game._submitted) return false;
  const status = game.priorSubmission?.status;
  return status !== "approved" && status !== "pending";
}

function pendingGameCount(games, mode = null) {
  return games.filter((game) => (!mode || game.mode === mode) && needsPlayerAction(game)).length;
}

function renderHero(state, pendingCount) {
  const games = state.games ?? [];
  const hero = el("section", "hero-panel");
  const titleRow = el("div", "hero-title-row");
  const title = el("h1", null, `Hi ${state.playerName}`);
  const badge = el("div", pendingCount === 0 ? "pending-badge clear" : "pending-badge",
    String(pendingCount));
  badge.setAttribute("role", "status");
  badge.setAttribute("aria-label", pendingCount === 0
    ? "No pending submissions"
    : `${pendingCount} pending submission${pendingCount === 1 ? "" : "s"}`);
  titleRow.append(title, badge);

  const counts = el("div", "mode-count-row");
  counts.appendChild(modeCountPill("LMS", pendingGameCount(games, "lms"), "lms"));
  counts.appendChild(modeCountPill("PRED", pendingGameCount(games, "predictor"), "predictor"));

  hero.append(titleRow, counts);
  return hero;
}

function modeCountPill(label, count, mode) {
  const pill = el("div", `mode-count-pill ${mode}`);
  pill.append(el("span", null, label), el("strong", null, String(count)));
  pill.setAttribute("aria-label", `${label}: ${count} pending`);
  return pill;
}

function renderNotice(title, message, type = "") {
  const card = el("section", `notice-card ${type}`.trim());
  card.appendChild(el("h2", null, title));
  card.appendChild(el("p", "muted", message));
  return card;
}

function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
}

async function savePrivateLink() {
  _saveStatus = null;

  if (_deferredInstallPrompt) {
    const promptEvent = _deferredInstallPrompt;
    _deferredInstallPrompt = null;
    promptEvent.prompt();
    const choice = await promptEvent.userChoice.catch(() => null);
    _saveStatus = choice?.outcome === "accepted" ? "Saved." : "Use the browser menu to add it.";
    updateSaveLinkAction(_token);
    render(_state, _token);
    return;
  }

  _saveStatus = "Use the browser menu to add it.";
  updateSaveLinkAction(_token);
  render(_state, _token);
}

function renderGame(game, token) {
  const modeClass = game.mode === "predictor" ? "mode-predictor" : "mode-lms";
  const card = el("article", `game-card ${modeClass}`);

  const head = el("header", "game-head");
  const headCopy = el("div", null);
  const modeName = game.mode === "predictor" ? "PRED" : "LMS";
  const topLine = el("div", "card-topline");
  topLine.appendChild(el("p", "eyebrow", modeName));
  const status = gameStatus(game);
  topLine.appendChild(el("span", `card-status ${status.kind}`, status.label));
  headCopy.appendChild(topLine);
  const roundLabel = `${game.mode === "predictor" ? "Matchday" : "Round"} ${game.roundNumber}`;
  headCopy.appendChild(el("h2", null, game.deadline ? `${roundLabel} · ${formatDate(game.deadline)}` : roundLabel));
  head.appendChild(headCopy);
  card.appendChild(head);

  const priorStatus = renderPriorStatus(game);
  if (priorStatus) card.appendChild(priorStatus);

  if (game._submitted) {
    card.appendChild(renderStatusBanner("pending", "Submitted", "Awaiting approval."));
    return card;
  }

  if (game._submitError) {
    card.appendChild(renderStatusBanner("error", "Couldn't submit", game._submitError));
  }

  if (game.priorSubmission?.status === "approved") return card;

  if (game.mode === "lms") {
    renderLMS(card, game, token);
  } else if (game.mode === "predictor") {
    renderPredictor(card, game, token);
  } else {
    card.appendChild(renderStatusBanner("error", "Unknown game mode", String(game.mode)));
  }

  return card;
}

function gameStatus(game) {
  if (game._submitted || game.priorSubmission?.status === "pending") {
    return { kind: "status-submitted", label: "Submitted" };
  }
  if (game.priorSubmission?.status === "approved") {
    return { kind: "status-approved", label: "Approved" };
  }
  return { kind: "status-action", label: "Needs action" };
}

function renderPriorStatus(game) {
  const prior = game.priorSubmission;
  if (!prior || game._submitted) return null;

  if (prior.status === "approved") {
    return renderStatusBanner("approved", "Approved", "No action needed.");
  }
  if (prior.status === "pending") {
    return renderStatusBanner("pending", "Submitted", "You can change it if needed.");
  }
  return renderStatusBanner("rejected", "Rejected", "Submit again.");
}

function renderStatusBanner(type, title, message) {
  const banner = el("div", `status-banner ${type}`);
  banner.appendChild(el("strong", null, title));
  banner.appendChild(el("span", null, message));
  return banner;
}

// -- LMS ----------------------------------------------------------------------

function renderLMS(container, game, token) {
  const eligibleTeams = game.eligibleTeams ?? [];
  const section = el("section", "submission-section");

  if (eligibleTeams.length === 0) {
    section.appendChild(renderNotice("No eligible teams found", "Contact your manager.", "compact"));
    container.appendChild(section);
    return;
  }

  const picker = el("label", "team-picker");
  picker.appendChild(el("span", "section-title", "Team"));
  const select = el("select", "team-select");
  select.setAttribute("aria-label", "Choose team");
  select.appendChild(el("option", null, "Choose team"));
  select.options[0].value = "";
  select.options[0].disabled = true;
  select.options[0].selected = game._selectedTeamId == null;
  for (const team of eligibleTeams) {
    const option = el("option", null, team.name);
    option.value = String(team.id);
    option.selected = game._selectedTeamId === team.id;
    select.appendChild(option);
  }
  select.addEventListener("change", () => {
    const team = eligibleTeams.find((item) => String(item.id) === select.value);
    updateGameState(game, {
      _selectedTeamId: team?.id ?? null,
      _selectedTeamName: team?.name ?? null,
      _submitError: null,
    });
  });
  picker.appendChild(select);

  const submit = el("button", "btn btn-primary lms-submit", "Submit pick");
  submit.type = "button";
  submit.disabled = game._selectedTeamId == null;
  submit.addEventListener("click", () => submitLMS(token, game));

  section.appendChild(picker);
  section.appendChild(submit);
  container.appendChild(section);
}

async function submitLMS(token, game) {
  if (game._selectedTeamId == null) return;
  try {
    await postSubmission(token, game.gameToken, {
      teamId: game._selectedTeamId,
      teamName: game._selectedTeamName,
    });
    updateGameState(game, { _submitted: true, _submitError: null });
  } catch (e) {
    updateGameState(game, { _submitError: e.message });
  }
}

// -- Predictor ----------------------------------------------------------------

function renderPredictor(container, game, token) {
  const section = el("section", "submission-section");

  const inputs = [];
  const fixtures = el("div", "fixture-list predictor-scroll");
  for (const f of game.fixtures ?? []) {
    const row = renderFixturePrediction(game, f, inputs);
    fixtures.appendChild(row);
  }

  const submit = el("button", "btn btn-primary predictor-submit", "Submit predictions");
  submit.type = "button";
  submit.addEventListener("click", () => submitPredictor(token, game, inputs));

  section.appendChild(fixtures);
  section.appendChild(submit);
  container.appendChild(section);
}

function renderFixturePrediction(game, fixture, inputs) {
  const fixtureId = fixture.fixtureId;
  game._scoreValues ??= {};
  game._scoreValues[fixtureId] ??= { home: "", away: "" };

  const card = el("div", "fixture-row");
  const score = el("div", game.jokerEnabled ? "compact-score-row" : "compact-score-row no-joker");
  const homeInput = scoreInput(`${fixture.home} score`, game._scoreValues[fixtureId].home);
  homeInput.addEventListener("input", () => { game._scoreValues[fixtureId].home = homeInput.value; });
  const awayInput = scoreInput(`${fixture.away} score`, game._scoreValues[fixtureId].away);
  awayInput.addEventListener("input", () => { game._scoreValues[fixtureId].away = awayInput.value; });

  score.append(
    fixtureKickoff(fixture.kickoff),
    el("span", "fixture-team home", fixture.home),
    homeInput,
    el("span", "score-separator", "-"),
    awayInput,
    el("span", "fixture-team away", fixture.away)
  );

  if (game.jokerEnabled) {
    const joker = el("button", game._jokerFixtureId === fixtureId ? "joker-btn selected" : "joker-btn", "J");
    joker.type = "button";
    joker.title = `Joker: ${fixture.home} v ${fixture.away}`;
    joker.setAttribute("aria-label", `Joker for ${fixture.home} v ${fixture.away}`);
    joker.setAttribute("aria-pressed", String(game._jokerFixtureId === fixtureId));
    joker.addEventListener("click", () => {
      const next = game._jokerFixtureId === fixtureId ? null : fixtureId;
      updateGameState(game, { _jokerFixtureId: next });
    });
    score.appendChild(joker);
  }

  card.appendChild(score);
  inputs.push({ fixtureId, homeInput, awayInput });
  return card;
}

function scoreInput(label, value) {
  const input = el("input");
  input.type = "number";
  input.inputMode = "numeric";
  input.min = "0";
  input.max = "999";
  input.placeholder = "0";
  input.className = "score-input";
  input.value = value ?? "";
  input.setAttribute("aria-label", label);
  return input;
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
    updateGameState(game, { _submitted: true, _submitError: null });
  } catch (e) {
    updateGameState(game, { _submitError: e.message });
  }
}

// -- State --------------------------------------------------------------------

function updateGameState(game, patch) {
  Object.assign(game, patch);
  render(_state, _token);
}

async function main() {
  applyLargeTextPreference();
  setupTextSizeToggle();
  setupSaveLinkAction();

  const token = getToken() ?? getRememberedToken();
  if (!token) {
    render({ error: "This link is missing its token. Check the URL and try again." }, null);
    return;
  }

  rememberToken(token);
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
