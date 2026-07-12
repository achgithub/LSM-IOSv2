export type GameMode = 'lms' | 'predictor' | 'killer';

export interface EligibleTeam {
  id: number;
  name: string;
  fixtureId?: number;
  opponentName?: string;
}

export interface Fixture {
  fixtureId: number;
  home: string;
  away: string;
  kickoff: string | null;
}

export interface PriorSubmission {
  status: 'pending' | 'approved' | 'rejected';
  payload?: {
    teamName?: string;
    scores?: { fixtureId: number; home: number; away: number; isJoker?: boolean }[];
  };
}

// What actually happened that round — survived/eliminated (LMS), points
// (Predictor), or lives/hits (Killer). Only the fields for the game's own
// mode will ever be populated; the component reading this already knows
// `game.mode`, so no discriminated union is needed.
export interface SubmissionHistoryResult {
  // LMS
  teamPicked?: string;
  survived?: boolean;
  // Predictor
  pointsThisRound?: number;
  cumulativePoints?: number;
  position?: number;
  // Killer
  lives?: number;
  eliminated?: boolean;
  hitsLandedThisRound?: number;
  correctPredictionsThisRound?: number;
}

// A player's own submission for a round that's since closed, plus (once the
// manager's app has pushed it) what actually happened that round. `status`/
// `payload` are absent for a round where a result exists but the player
// never submitted anything (e.g. the manager entered their pick manually).
export interface SubmissionHistoryItem {
  roundNumber: number;
  status?: 'pending' | 'approved' | 'rejected';
  payload?: PriorSubmission['payload'];
  result?: SubmissionHistoryResult;
}

// Opponent roster entry for Killer's Kill Phase hit-target picker — `id` is
// the local Player UUID string, verbatim from the iOS side, that must
// round-trip unchanged through a submission back to `applyLocally`.
export interface KillerOtherPlayer {
  id: string;
  name: string;
}

// Parsed shape of a Killer game's opaque `extra` field (see `Game.extra`).
export interface KillerExtra {
  phase: 'build' | 'kill';
  otherPlayers?: KillerOtherPlayer[];
}

export interface KillerOutcome {
  fixtureId: number;
  /** Matches iOS `FixtureOutcome.rawValue` exactly — no translation layer. */
  outcome: 'homeWin' | 'draw' | 'awayWin';
  /** Kill Phase only. Local Player UUID string of the chosen hit target. */
  hitTargetId?: string;
}

export interface Game {
  mode: GameMode;
  gameToken: string;
  gameName?: string;
  roundNumber: number;
  deadline?: string | null;
  eligibleTeams?: EligibleTeam[];
  fixtures?: Fixture[];
  jokerEnabled?: boolean;
  priorSubmission?: PriorSubmission;
  /** Last up-to-2 closed rounds' submissions, most recent first. */
  history?: SubmissionHistoryItem[];
  /** Opaque, mode-specific round data — raw JSON string, parse client-side. */
  extra?: string;
  /** This player's own local Player UUID string — lets mode-specific UI (e.g.
   * Killer's opponent roster) identify and exclude "me" without a lookup. */
  localPlayerId?: string;
}

export interface PlayerData {
  playerName?: string;
  managerName?: string;
  games?: Game[];
}

export interface PlayerState extends Partial<PlayerData> {
  loading?: boolean;
  error?: string;
  maintenance?: boolean;
}

export interface LMSSelection {
  teamId: number;
  teamName: string;
  fixtureId: number | null;
  opponentName: string | null;
}

export interface PredictorScore {
  fixtureId: number;
  home: number;
  away: number;
  isJoker: boolean;
}
