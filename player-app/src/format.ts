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

export function kickoffParts(value?: string | null): [string, string] | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return [value, ''];
  return [
    date.toLocaleDateString([], { day: 'numeric', month: 'short' }),
    date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
  ];
}
