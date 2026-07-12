export function formatDate(value?: string | null): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date
    .toLocaleString([], {
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    })
    .replace(/,/g, '');
}

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

export interface CountdownParts {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
}

// Shared breakdown used by both the plain-text countdown and the digit-clock
// display — keeps the two in sync instead of each re-deriving units. `ms`
// should already be clamped to >= 0 by the caller.
export function countdownParts(ms: number): CountdownParts {
  const totalSeconds = Math.floor(ms / 1000);
  return {
    days: Math.floor(totalSeconds / 86400),
    hours: Math.floor((totalSeconds % 86400) / 3600),
    minutes: Math.floor((totalSeconds % 3600) / 60),
    seconds: totalSeconds % 60,
  };
}

// HH:MM:SS, extending to "Dd HH:MM:SS" past 24h.
export function formatCountdown(ms: number): string {
  const { days, hours, minutes, seconds } = countdownParts(ms);
  const clock = `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
  return days > 0 ? `${days}d ${clock}` : clock;
}

// "Fri 14 Aug, 19:00" — used by the closes-soonest banner, distinct from
// formatDate's "Thu 13 Aug 20:00" (no comma) used in per-game cutoff lines.
export function formatDeadlineShort(value?: string | null): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  const weekday = date.toLocaleDateString([], { weekday: 'short' });
  const day = date.toLocaleDateString([], { day: 'numeric', month: 'short' });
  const time = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  return `${weekday} ${day}, ${time}`;
}

export function kickoffParts(value?: string | null): [string, string] | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return [value, ''];
  return [
    date.toLocaleDateString([], { day: 'numeric', month: 'short' }),
    date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
  ];
}
