// Region-prefixed secret resolution + admin auth for the authority Worker.
// Same pattern as worker/src/auth.ts; kept separate so each codebase evolves
// independently.

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.byteLength !== bb.byteLength) return false;
  return crypto.subtle.timingSafeEqual(ab, bb);
}

type SecretName = "ATTEST_CHALLENGE_KEY" | "JWT_PRIVATE_KEY" | "ADMIN_TOKEN";

export function regionSecret(env: Env, name: SecretName): string {
  const prefix = env.REGION.toUpperCase();
  switch (prefix) {
    case "UK":
      switch (name) {
        case "ATTEST_CHALLENGE_KEY": return env.UK_ATTEST_CHALLENGE_KEY ?? "";
        case "JWT_PRIVATE_KEY":      return env.UK_JWT_PRIVATE_KEY ?? "";
        case "ADMIN_TOKEN":          return env.UK_ADMIN_TOKEN ?? "";
      }
      break;
    case "EU":
      switch (name) {
        case "ATTEST_CHALLENGE_KEY": return env.EU_ATTEST_CHALLENGE_KEY ?? "";
        case "JWT_PRIVATE_KEY":      return env.EU_JWT_PRIVATE_KEY ?? "";
        case "ADMIN_TOKEN":          return env.EU_ADMIN_TOKEN ?? "";
      }
      break;
  }
  return "";
}

export function requireAdmin(env: Env, authorization: string | undefined): boolean {
  const token = regionSecret(env, "ADMIN_TOKEN");
  const provided = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token || !provided) return false;
  return timingSafeEqual(provided, token);
}
