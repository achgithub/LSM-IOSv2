// Domain types for the LMS read-only sports-data API.
// All times are ISO8601 UTC strings. The app converts to local time for display.

export type FixtureStatus =
  | "SCHEDULED"
  | "TIMED"
  | "IN_PLAY"
  | "PAUSED"
  | "FINISHED"
  | "POSTPONED"
  | "SUSPENDED"
  | "CANCELLED";

export type MatchWinner = "HOME_TEAM" | "AWAY_TEAM" | "DRAW" | null;

export interface Team {
  id: string;
  externalId: number;
  name: string;
  shortName: string | null;
  tla: string | null;
  leagueId: string;
}

export interface Fixture {
  id: number;
  matchday: number | null;
  kickoff: string;
  status: FixtureStatus;
  homeTeamId: number;
  awayTeamId: number;
  homeScore: number | null;
  awayScore: number | null;
  winner: MatchWinner;
  updatedAt: string;
}

export interface Standing {
  teamId: number;
  position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifference: number;
  points: number;
  updatedAt: string;
}

// The compact score payload cached in KV and served on GET /scores.
export interface ScoreEntry {
  id: number;
  status: FixtureStatus;
  minute: number | null;
  homeTeamId: number;
  awayTeamId: number;
  homeScore: number | null;
  awayScore: number | null;
  winner: MatchWinner;
}

