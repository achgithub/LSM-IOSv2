// ── Key shapes ─────────────────────────────────────────────────────────────────
// Small, pure key builders — same style as Clubroom2's worker/src/keys.ts.
// Centralised here so the prefix a route's list() call uses can never drift
// from the prefix individual writes use. See the plan's "KV key catalog".
//
// Round numbers are zero-padded to 4 digits inside keys so list()'s
// lexicographic ordering doesn't corrupt on "10" < "2".

// A game with no confirmed owner yet (round_push.managerToken was null —
// "grandfathered" in the old D1 tri-state) has no real managerToken to prefix
// submission/mgr_game keys with. This sentinel keeps the managerToken-first
// prefix scheme well-defined even in that edge case. In practice unreachable
// with a fresh KV store + the current iOS client (which always sends a
// managerToken on push) — kept only so the tri-state ownership branches stay
// structurally correct, per the plan's explicit requirement.
export const UNCLAIMED_MANAGER = "_unclaimed";

export function padRound(roundNumber: number): string {
  return String(roundNumber).padStart(4, "0");
}

export function unpadRound(padded: string): number {
  return parseInt(padded, 10);
}

export function playerLinkKey(token: string): string {
  return `player_link:${token}`;
}

export function mgrLinkKey(managerToken: string, token: string): string {
  return `mgr_link:${managerToken}:${token}`;
}

export function mgrLinkPrefix(managerToken: string): string {
  return `mgr_link:${managerToken}:`;
}

/** Parses the token back out of a mgr_link key. */
export function tokenFromMgrLinkKey(key: string): string | null {
  const parts = key.split(":");
  if (parts.length !== 3 || parts[0] !== "mgr_link") return null;
  return parts[2] ?? null;
}

export function roundPushKey(gameToken: string): string {
  return `round_push:${gameToken}`;
}

export function mgrGameKey(managerToken: string, gameToken: string): string {
  return `mgr_game:${managerToken}:${gameToken}`;
}

export function mgrGamePrefix(managerToken: string): string {
  return `mgr_game:${managerToken}:`;
}

/** Parses the gameToken back out of a mgr_game key. */
export function gameTokenFromMgrGameKey(key: string): string | null {
  const parts = key.split(":");
  if (parts.length !== 3 || parts[0] !== "mgr_game") return null;
  return parts[2] ?? null;
}

export function gamePlayerKey(gameToken: string, token: string): string {
  return `game_player:${gameToken}:${token}`;
}

export function gamePlayerPrefix(gameToken: string): string {
  return `game_player:${gameToken}:`;
}

/** Parses the token back out of a game_player key. */
export function tokenFromGamePlayerKey(key: string): string | null {
  const parts = key.split(":");
  if (parts.length !== 3 || parts[0] !== "game_player") return null;
  return parts[2] ?? null;
}

export function submissionKey(managerToken: string, gameToken: string, roundNumber: number, token: string): string {
  return `submission:${managerToken}:${gameToken}:${padRound(roundNumber)}:${token}`;
}

// Manager-wide — the whole point of the managerToken-first prefix (plan
// decision #4): GET /manager/submissions/pending stays one list() call
// across every game this manager owns.
export function submissionPrefixForManager(managerToken: string): string {
  return `submission:${managerToken}:`;
}

export function submissionPrefixForGame(managerToken: string, gameToken: string): string {
  return `submission:${managerToken}:${gameToken}:`;
}

export function submissionPrefixForGameRound(managerToken: string, gameToken: string, roundNumber: number): string {
  return `submission:${managerToken}:${gameToken}:${padRound(roundNumber)}:`;
}

/** Parses {managerToken, gameToken, roundNumber, token} back out of a submission key. */
export function parseSubmissionKey(key: string): { managerToken: string; gameToken: string; roundNumber: number; token: string } | null {
  const parts = key.split(":");
  if (parts.length !== 5 || parts[0] !== "submission") return null;
  return {
    managerToken: parts[1] ?? "",
    gameToken: parts[2] ?? "",
    roundNumber: unpadRound(parts[3] ?? "0"),
    token: parts[4] ?? "",
  };
}

export function resultKey(gameToken: string, roundNumber: number): string {
  return `result:${gameToken}:${padRound(roundNumber)}`;
}

export function resultPrefix(gameToken: string): string {
  return `result:${gameToken}:`;
}

/** Parses the round number back out of a result key. */
export function roundFromResultKey(key: string): number | null {
  const parts = key.split(":");
  if (parts.length !== 3 || parts[0] !== "result") return null;
  return unpadRound(parts[2] ?? "0");
}

export function mgrLifecycleKey(managerToken: string): string {
  return `mgr_lifecycle:${managerToken}`;
}
