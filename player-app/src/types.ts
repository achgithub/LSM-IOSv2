export type GameMode = 'lms' | 'predictor';

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
