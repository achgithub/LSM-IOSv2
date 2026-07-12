import type { LMSSelection, PlayerData, PredictorScore } from './types';

// In dev, requests go through the Vite proxy at /api (see vite.config.ts) so
// the browser sees a same-origin call — worker-api's CORS only allows the
// production origin, so a direct cross-origin fetch from localhost is blocked.
const API_BASE = import.meta.env.DEV ? '/api' : 'https://api.uk.sportsmanager.site';

// Thrown when the backend's global outage flag is on (see worker-api's
// src/outage.ts). Distinguishable from a generic Error so callers can render
// a dedicated "under maintenance" state instead of the generic error banner.
export class MaintenanceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MaintenanceError';
  }
}

// Thrown when the round the player loaded against has moved on (the manager
// closed it and opened a new one) before the submission landed — the server
// rejects the stale-round write rather than silently overwriting the current
// round's data. Callers should prompt the player to refresh.
export class RoundMovedOnError extends Error {
  currentRound: number;
  constructor(currentRound: number) {
    super('This round has moved on — refresh to see the latest.');
    this.name = 'RoundMovedOnError';
    this.currentRound = currentRound;
  }
}

async function throwIfError(res: Response): Promise<void> {
  if (res.ok) return;
  const body = await res.json().catch(() => ({}) as { error?: string; message?: string; currentRound?: number });
  if (res.status === 503 && body.error === 'maintenance') {
    throw new MaintenanceError(body.message || "We're doing scheduled maintenance — back shortly.");
  }
  if (res.status === 409 && body.error === 'round_moved_on') {
    throw new RoundMovedOnError(body.currentRound ?? 0);
  }
  throw new Error(body.error || `Server error ${res.status}`);
}

export async function fetchPlayer(token: string): Promise<PlayerData> {
  const res = await fetch(`${API_BASE}/s/${token}`);
  await throwIfError(res);
  return res.json();
}

export async function submitLMS(
  token: string,
  gameToken: string,
  roundNumber: number,
  selection: LMSSelection
): Promise<void> {
  const res = await fetch(`${API_BASE}/s/${token}/games/${gameToken}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ roundNumber, ...selection }),
  });
  await throwIfError(res);
}

export async function submitPredictor(
  token: string,
  gameToken: string,
  roundNumber: number,
  scores: PredictorScore[]
): Promise<void> {
  const res = await fetch(`${API_BASE}/s/${token}/games/${gameToken}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ roundNumber, scores }),
  });
  await throwIfError(res);
}

export { API_BASE };
