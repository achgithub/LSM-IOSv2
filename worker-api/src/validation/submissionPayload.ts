// Server-side validation for the anonymous player-submission body
// (POST /s/:token/games/:gameToken). This endpoint is unauthenticated by
// design (no login for players) — anyone who guesses or leaks a submission
// token can POST arbitrary JSON here, so unlike the JWT-gated manager-side
// push endpoint, this is the one payload shape worth policing before it's
// persisted and later trusted by the manager's approve flow.
//
// Whitelists fields and drops anything unexpected rather than merely
// type-checking — defense in depth against a client sending extra fields
// that some future code path might accidentally trust.

const MAX_ARRAY_LENGTH = 100; // generous — no round realistically has more fixtures than this
const MAX_STRING_LENGTH = 200;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string };

function isPositiveInt(v: unknown, max = 2 ** 31 - 1): v is number {
  return typeof v === "number" && Number.isInteger(v) && v > 0 && v <= max;
}

function isBoundedString(v: unknown, max = MAX_STRING_LENGTH): v is string {
  return typeof v === "string" && v.length > 0 && v.length <= max;
}

// Scorelines are goals scored, not an open-ended number — 99 is already an
// absurd scoreline and comfortably bounds any real match.
function isScore(v: unknown): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 99;
}

interface LMSPayload {
  teamId: number;
  teamName?: string;
  fixtureId?: number;
  opponentName?: string;
}

function validateLMS(body: Record<string, unknown>): ValidationResult<LMSPayload> {
  if (!isPositiveInt(body.teamId)) return { ok: false, error: "teamId must be a positive integer" };
  const value: LMSPayload = { teamId: body.teamId as number };
  if (body.fixtureId !== undefined) {
    if (!isPositiveInt(body.fixtureId)) return { ok: false, error: "fixtureId must be a positive integer" };
    value.fixtureId = body.fixtureId as number;
  }
  if (body.teamName !== undefined) {
    if (!isBoundedString(body.teamName)) return { ok: false, error: "teamName is invalid" };
    value.teamName = body.teamName as string;
  }
  if (body.opponentName !== undefined) {
    if (!isBoundedString(body.opponentName)) return { ok: false, error: "opponentName is invalid" };
    value.opponentName = body.opponentName as string;
  }
  return { ok: true, value };
}

interface PredictorScore {
  fixtureId: number;
  home: number;
  away: number;
  isJoker?: boolean;
}

function validatePredictor(body: Record<string, unknown>): ValidationResult<{ scores: PredictorScore[] }> {
  if (!Array.isArray(body.scores)) return { ok: false, error: "scores must be an array" };
  if (body.scores.length === 0 || body.scores.length > MAX_ARRAY_LENGTH) {
    return { ok: false, error: "scores has an invalid length" };
  }
  const scores: PredictorScore[] = [];
  for (const raw of body.scores) {
    if (typeof raw !== "object" || raw === null) return { ok: false, error: "each score must be an object" };
    const s = raw as Record<string, unknown>;
    if (!isPositiveInt(s.fixtureId)) return { ok: false, error: "score.fixtureId must be a positive integer" };
    if (!isScore(s.home) || !isScore(s.away)) return { ok: false, error: "score.home/away must be 0-99" };
    const entry: PredictorScore = { fixtureId: s.fixtureId as number, home: s.home as number, away: s.away as number };
    if (s.isJoker !== undefined) {
      if (typeof s.isJoker !== "boolean") return { ok: false, error: "score.isJoker must be a boolean" };
      entry.isJoker = s.isJoker;
    }
    scores.push(entry);
  }
  return { ok: true, value: { scores } };
}

const KILLER_OUTCOMES = new Set(["homeWin", "draw", "awayWin"]);

interface KillerOutcomeEntry {
  fixtureId: number;
  outcome: string;
  hitTargetId?: string;
}

function validateKiller(body: Record<string, unknown>): ValidationResult<{ outcomes: KillerOutcomeEntry[] }> {
  if (!Array.isArray(body.outcomes)) return { ok: false, error: "outcomes must be an array" };
  if (body.outcomes.length === 0 || body.outcomes.length > MAX_ARRAY_LENGTH) {
    return { ok: false, error: "outcomes has an invalid length" };
  }
  const outcomes: KillerOutcomeEntry[] = [];
  for (const raw of body.outcomes) {
    if (typeof raw !== "object" || raw === null) return { ok: false, error: "each outcome must be an object" };
    const o = raw as Record<string, unknown>;
    if (!isPositiveInt(o.fixtureId)) return { ok: false, error: "outcome.fixtureId must be a positive integer" };
    if (typeof o.outcome !== "string" || !KILLER_OUTCOMES.has(o.outcome)) {
      return { ok: false, error: "outcome.outcome must be homeWin, draw, or awayWin" };
    }
    const entry: KillerOutcomeEntry = { fixtureId: o.fixtureId as number, outcome: o.outcome };
    if (o.hitTargetId !== undefined) {
      if (typeof o.hitTargetId !== "string" || !UUID_RE.test(o.hitTargetId)) {
        return { ok: false, error: "outcome.hitTargetId must be a UUID" };
      }
      entry.hitTargetId = o.hitTargetId.toLowerCase();
    }
    outcomes.push(entry);
  }
  return { ok: true, value: { outcomes } };
}

// `mode` comes from the already-trusted `round_pushes` row for this game
// (set by the JWT-gated manager push, not from the anonymous submit body),
// so it's safe to switch on directly.
export function validateSubmissionPayload(mode: string, body: unknown): ValidationResult<object> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: "Body must be a JSON object" };
  }
  const record = body as Record<string, unknown>;
  switch (mode) {
    case "lms":
      return validateLMS(record);
    case "predictor":
      return validatePredictor(record);
    case "killer":
      return validateKiller(record);
    default:
      return { ok: false, error: `Unknown mode: ${mode}` };
  }
}
