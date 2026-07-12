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

// A player's own submission for a round that's since closed. "What did I
// submit," not "did I win" — results/points aren't carried here, only the
// picks themselves (roundNumber + status + payload, same shape as PriorSubmission).
export interface SubmissionHistoryItem {
  roundNumber: number;
  status: 'pending' | 'approved' | 'rejected';
  payload?: PriorSubmission['payload'];
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
