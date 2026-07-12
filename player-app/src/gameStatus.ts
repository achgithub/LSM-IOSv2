import type { Game } from './types';

export function needsPlayerAction(game: Game): boolean {
  const status = game.priorSubmission?.status;
  return status !== 'approved' && status !== 'pending';
}
