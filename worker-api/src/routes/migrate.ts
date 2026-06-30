import { Hono } from "hono";

// ── Region migration stubs ────────────────────────────────────────────────────
// Used when a user's home authority changes — e.g. a French user who registered
// before api.eu went live was assigned to api.uk. Once api.eu is live they can
// move: iOS calls GET /manager/export on the old authority, then
// POST /manager/import on the new one, then updates its persisted authority URL.
//
// Both endpoints are JWT-gated (requireJWT applied in index.ts).
// The export bundle is signed by the manager's attest key id so only the real
// device can trigger the move (verified by comparing X-Manager-Token).
//
// Stubs return 501 until the iOS migration flow is built. The endpoints are
// registered now so the URL contract is stable.

export const migrate = new Hono<{ Bindings: Env }>();

// GET /manager/export
// Returns lifecycle state + player tokens for this manager as a signed bundle.
// The receiving authority passes this to POST /manager/import.
migrate.get("/export", (c) => {
  return c.json({ error: "not implemented" }, 501);
});

// POST /manager/import
// Accepts a bundle from GET /manager/export on another authority.
// Idempotent — safe to retry if the move is interrupted mid-flight.
migrate.post("/import", (c) => {
  return c.json({ error: "not implemented" }, 501);
});
