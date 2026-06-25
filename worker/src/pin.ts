// PIN hashing for Cloud Publish links (§0: "PIN is validated server-side...
// stored hashed"). SHA-256 over a per-link random salt + the PIN — a publish
// PIN is short (the manager picks it, e.g. 4-6 digits) so the salt matters:
// without it, every link sharing a common PIN ("1234") would hash identically.

const hex = (bytes: ArrayBuffer): string =>
  Array.from(new Uint8Array(bytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

export function makeSalt(): string {
  return hex(crypto.getRandomValues(new Uint8Array(16)).buffer);
}

export async function hashPin(pin: string, salt: string): Promise<string> {
  const data = new TextEncoder().encode(`${salt}:${pin}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return hex(digest);
}

// Constant-time comparison — a PIN's keyspace is tiny (4-6 digits), so even a
// short-circuiting `===` leaking string-prefix-match timing is worth closing.
function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifyPin(pin: string, salt: string, expectedHash: string): Promise<boolean> {
  return timingSafeEqualHex(await hashPin(pin, salt), expectedHash);
}
