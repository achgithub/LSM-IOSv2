import { useEffect, useMemo, useState } from 'react';
import type { Game } from '../types';
import { needsPlayerAction } from '../gameStatus';

export interface DeadlineCountdown {
  game: Game;
  remainingMs: number;
}

// The single most urgent deadline across all games the player still needs to
// act on, ticking every second. Considered across all modes, not just the
// currently-filtered tab — the point is surfacing the one thing that matters
// most regardless of which mode the player happens to be looking at.
// Recomputes automatically as `games` changes (e.g. after a submit +
// refresh), which is what makes "advances to the next one" work for free —
// a submitted game drops out of `needsPlayerAction` and the next-nearest
// deadline becomes the candidate on the next render.
export function useDeadlineCountdown(games: Game[]): DeadlineCountdown | null {
  const [now, setNow] = useState(() => Date.now());

  const candidate = useMemo(() => {
    let nearest: { game: Game; deadlineMs: number } | null = null;
    for (const game of games) {
      if (!needsPlayerAction(game) || !game.deadline) continue;
      const deadlineMs = new Date(game.deadline).getTime();
      if (Number.isNaN(deadlineMs) || deadlineMs <= now) continue;
      if (!nearest || deadlineMs < nearest.deadlineMs) {
        nearest = { game, deadlineMs };
      }
    }
    return nearest;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [games]);

  useEffect(() => {
    if (!candidate) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [candidate]);

  if (!candidate) return null;
  const remainingMs = candidate.deadlineMs - now;
  if (remainingMs <= 0) return null;
  return { game: candidate.game, remainingMs };
}
