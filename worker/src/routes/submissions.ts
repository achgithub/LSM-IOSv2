import { Hono } from "hono";

// ── Submissions (the anonymous PWA approval queue) ───────────────────────────
// NEW in v2. Two distinct audiences share this file:
//
//   • PLAYER (PWA, anonymous, no account) — reaches these via their unguessable
//     UUID link. They can only see what's actionable for their token and POST a
//     submission. A submission lands as 'pending'; it does NOT write into
//     picks/predictions. No email, no login — deliberately outside GDPR scope.
//
//   • MANAGER (LSM app) — reviews the queue and approves/rejects. APPROVAL is
//     what creates the real pick/prediction row; rejection discards. This is the
//     misuse gate: anyone with the link can submit, nothing is live until the
//     manager confirms. Manager-typed entries skip this queue entirely (see
//     ./games.ts).
//
// SKELETON: handlers stubbed (501). See docs/lsm-v2-architecture.md §3 and
// worker/schema.sql (submission_tokens, submissions).
export const submissions = new Hono<{ Bindings: Env }>();

const notImplemented = (what: string) => (c: any) =>
  c.json({ error: "not implemented", todo: what }, 501);

// Player-facing (token-authenticated by the unguessable UUID, not an account) --
// GET  /s/:token            what's actionable now for this player (round teams / week fixtures)
// POST /s/:token            submit a pick/prediction → inserts a 'pending' submission row
submissions.get("/s/:token", notImplemented("player: actionable view for token"));
submissions.post("/s/:token", notImplemented("player: enqueue pending submission"));

// Manager-facing (LSM app) ----------------------------------------------------
// GET  /games/:id/submissions          the pending queue for a game
// POST /submissions/:sid/approve       create the real pick/prediction, mark approved
// POST /submissions/:sid/reject        discard, mark rejected
submissions.get("/games/:id/submissions", notImplemented("manager: list queue"));
submissions.post("/submissions/:sid/approve", notImplemented("manager: approve → create row"));
submissions.post("/submissions/:sid/reject", notImplemented("manager: reject"));
