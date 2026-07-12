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

// HH:MM:SS, extending to "Dd HH:MM:SS" past 24h. `ms` should already be
// clamped to >= 0 by the caller — this doesn't guard against negative input.
export function formatCountdown(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const clock = `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
  return days > 0 ? `${days}d ${clock}` : clock;
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
