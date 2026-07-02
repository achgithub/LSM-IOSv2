import type { LMSSelection, PlayerData, PredictorScore } from './types';

// In dev, requests go through the Vite proxy at /api (see vite.config.ts) so
// the browser sees a same-origin call — worker-api's CORS only allows the
// production origin, so a direct cross-origin fetch from localhost is blocked.
const API_BASE = import.meta.env.DEV ? '/api' : 'https://api.uk.sportsmanager.site';

async function parseErrorBody(res: Response): Promise<string> {
  const body = await res.json().catch(() => ({}) as { error?: string });
  return body.error || `Server error ${res.status}`;
}

export async function fetchPlayer(token: string): Promise<PlayerData> {
  const res = await fetch(`${API_BASE}/s/${token}`);
  if (!res.ok) throw new Error(await parseErrorBody(res));
  return res.json();
}

export async function submitLMS(token: string, gameToken: string, selection: LMSSelection): Promise<void> {
  const res = await fetch(`${API_BASE}/s/${token}/games/${gameToken}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(selection),
  });
  if (!res.ok) throw new Error(await parseErrorBody(res));
}

export async function submitPredictor(token: string, gameToken: string, scores: PredictorScore[]): Promise<void> {
  const res = await fetch(`${API_BASE}/s/${token}/games/${gameToken}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ scores }),
  });
  if (!res.ok) throw new Error(await parseErrorBody(res));
}

export { API_BASE };
