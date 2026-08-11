// ── KV value shapes ───────────────────────────────────────────────────────────
// Mirrors Clubroom2's worker/src/types.ts style: plain interfaces for
// everything that lives in SUBMISSIONS_KV, no ORM. See the plan's "KV key
// catalog" for the authoritative shape-per-key table this file implements.
//
// `attest_devices` is NOT here — it stays on D1 (attest-store.ts), a small
// database of its own, separate from worker-api's.

// One eligible team a player can pick for an LMS round — fixtureId/opponentName
// disambiguate a team playing twice in the round (rearranged fixtures).
export interface EligibleTeam {
  id: number;
  name: string;
  fixtureId?: number;
  opponentName?: string;
}

// One game a player-link is enrolled in. Lives inside PlayerLinkRecord.games —
// this is what replaces the old `game_enrollments` join table.
export interface GameMembership {
  gameToken: string;
  localPlayerId: string;
  eligibleTeams: EligibleTeam[] | null;
  managerSuffix: string | null;
}

// `player_link:{token}` — replaces player_tokens + game_enrollments join.
export interface PlayerLinkRecord {
  token: string;
  playerName: string;
  managerToken: string | null;
  managerName: string | null;
  createdAt: string;
  revokedAt: string | null;
  lastUsedAt: string | null;
  games: GameMembership[];
}

// `mgr_link:{managerToken}:{token}` metadata — marker value is "".
export interface MgrLinkMetadata {
  playerName: string;
  lastUsedAt: string | null;
  revoked: boolean;
}

// `round_push:{gameToken}` — replaces round_pushes row.
export interface RoundPushRecord {
  gameToken: string;
  mode: string;
  roundNumber: number;
  deadline: string | null;
  gameName: string | null;
  fixtures: unknown[];
  jokerEnabled: boolean;
  managerToken: string | null;
  updatedAt: string;
  extra: string | null;
}

// `mgr_game:{managerToken}:{gameToken}` metadata — marker value is "".
export interface MgrGameMetadata {
  updatedAt: string;
}

// `submission:{managerToken}:{gameToken}:{r%04d}:{token}` — replaces
// submissions row + its 3-way join (game_enrollments/player_tokens/round_pushes).
export type SubmissionStatus = "pending" | "approved" | "rejected";

export interface SubmissionRecord {
  id: string;
  token: string;
  gameToken: string;
  roundNumber: number;
  payload: unknown;
  status: SubmissionStatus;
  submittedAt: string;
  decidedAt: string | null;
}

// Captured at submit time (the player route already loads round_push to
// validate, so this is free) — lets list-heavy routes (per-game submission
// list, the manager-wide pending aggregate, approve/reject id lookup) filter
// and render without a get() per candidate key. `id` is carried here too so
// approve/reject can resolve the opaque submission id to its KV key with a
// single list() (matching on metadata.id) instead of needing the key's
// round/token components encoded into the id itself.
export interface SubmissionMetadata {
  id: string;
  status: SubmissionStatus;
  submittedAt: string;
  roundNumber: number;
  playerName: string | null;
  localPlayerId: string | null;
  managerSuffix: string | null;
  gameName: string | null;
  mode: string;
}

// `result:{gameToken}:{r%04d}` — replaces round_results row.
export interface ResultRecord {
  gameToken: string;
  roundNumber: number;
  mode: string;
  results: unknown;
  createdAt: string;
}

// `mgr_lifecycle:{managerToken}` — replaces manager_lifecycle row.
export interface ManagerLifecycleRecord {
  managerToken: string;
  createdAt: string;
  unsubscribedAt: string | null;
  scheduledDeleteAt: string | null;
  maxPWALinks: number | null;
  linkCapWarnedAt: string | null;
}
