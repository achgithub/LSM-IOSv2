import { Hono } from "hono";
import { validateSubmissionPayload, referencedFixtureIds } from "../validation/submissionPayload";
import {
  gamePlayerKey, gamePlayerPrefix, parseSubmissionKey, resultKey, resultPrefix,
  roundFromResultKey, roundPushKey, submissionKey, submissionPrefixForGame,
  submissionPrefixForGameRound, submissionPrefixForManager, tokenFromGamePlayerKey,
  UNCLAIMED_MANAGER,
} from "../kv/keys";
import { deleteMgrGame, ensureManagerLifecycle, putMgrGame } from "../kv/managerIndex";
import { getPlayerLink, mintPlayerLink, putPlayerLink, revokePlayerLink, revokePlayerLinkByName, touchPlayerLink } from "../kv/playerLinks";
import { CONTENT_TTL_SECONDS, SUBMISSION_TTL_SECONDS, nowIso } from "../kv/retention";
import type { GameMembership, ResultRecord, RoundPushRecord, SubmissionMetadata, SubmissionRecord } from "../kv/types";

// ── Submissions (the anonymous PWA approval queue) — KV design ───────────────
//
// This is worker-api-v2's rebuild of worker-api's routes/submissions.ts:
// same wire format, same route surface, storage moved from D1 (player_tokens
// / game_enrollments / round_pushes / submissions / round_results) to KV
// (SUBMISSIONS_KV) with self-expiring TTLs instead of a cron. See kv/ for the
// storage layer and the plan for the full design.
//
// Two audiences:
//
//   PLAYER (PWA, anonymous) — /s/:token. GET returns all active games with
//   jokerEnabled and managerSuffix per game. POST /s/:token/games/:gameToken
//   submits for one specific game (LMS: {teamId}, Predictor: {scores, jokerFixtureId?}).
//
//   MANAGER (LSM app) — mints tokens per roster member, pushes rounds,
//   reviews queues, approves/rejects. Revoke kills the token everywhere.

export const submissions = new Hono<{ Bindings: Env }>();

// CORS for player-facing PWA routes is registered in index.ts, ahead of any
// gating middleware, so a gate's short-circuit still ships CORS headers.

// ─── helpers ─────────────────────────────────────────────────────────────────

function now(): string {
  return nowIso();
}

// The owning managerToken for a game, read from its round_push record.
// `undefined` = no such game; `null` = game exists but predates ownership
// binding (grandfathered — allowed through until the next push claims it).
async function loadGameOwner(kv: KVNamespace, gameToken: string): Promise<string | null | undefined> {
  const raw = await kv.get(roundPushKey(gameToken));
  if (!raw) return undefined;
  const push = JSON.parse(raw) as RoundPushRecord;
  return push.managerToken;
}

async function loadRoundPush(kv: KVNamespace, gameToken: string): Promise<RoundPushRecord | null> {
  const raw = await kv.get(roundPushKey(gameToken));
  return raw ? (JSON.parse(raw) as RoundPushRecord) : null;
}

// managerToken component used for submission/mgr_game keys — a null owner
// (grandfathered game with no claimed manager) falls back to a sentinel so
// the managerToken-first prefix scheme stays well-defined. See kv/keys.ts.
function mgrPrefixFor(owner: string | null): string {
  return owner ?? UNCLAIMED_MANAGER;
}

function managerTokenHeader(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header("X-Manager-Token")?.toLowerCase() ?? null;
}

async function putSubmission(
  kv: KVNamespace, mgrPrefix: string, record: SubmissionRecord, metadata: SubmissionMetadata,
): Promise<void> {
  await kv.put(
    submissionKey(mgrPrefix, record.gameToken, record.roundNumber, record.token),
    JSON.stringify(record),
    { metadata, expirationTtl: SUBMISSION_TTL_SECONDS },
  );
}

// ─── Manager-facing ──────────────────────────────────────────────────────────

// POST /links
// Mint a global player token. Unconditional — no player_name uniqueness
// check (plan decision #2); revoke-by-name is the self-heal path for a
// manager who's lost its local record of a token.
submissions.post("/links", async (c) => {
  const body = await c.req.json<{ playerName: string; managerToken?: string; managerName?: string }>();
  const playerName = body?.playerName?.trim();
  if (!playerName) return c.json({ error: "playerName is required" }, 400);

  const managerToken = body?.managerToken?.toLowerCase() ?? null;
  const managerName = body?.managerName?.trim() ?? null;

  const record = await mintPlayerLink(c.env.SUBMISSIONS_KV, { playerName, managerToken, managerName });

  return c.json({ token: record.token });
});

// POST /links/:token/revoke
submissions.post("/links/:token/revoke", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const ok = await revokePlayerLink(c.env.SUBMISSIONS_KV, token);
  if (!ok) return c.json({ error: "token not found or already revoked" }, 404);
  return c.json({ ok: true });
});

// POST /links/revoke-by-name
// Self-heal path for a manager who has lost their local record of a token
// (e.g. app reinstall wipes the on-device roster, but the Keychain-backed
// managerToken survives). Scoped to the caller's own managerToken — a
// manager can only revoke a link that was minted with that same
// managerToken, never an arbitrary player's link.
submissions.post("/links/revoke-by-name", async (c) => {
  const body = await c.req.json<{ playerName: string; managerToken?: string }>();
  const playerName = body?.playerName?.trim();
  const managerToken = body?.managerToken?.toLowerCase().trim();
  if (!playerName) return c.json({ error: "playerName is required" }, 400);
  if (!managerToken) return c.json({ error: "managerToken is required" }, 400);

  const ok = await revokePlayerLinkByName(c.env.SUBMISSIONS_KV, managerToken, playerName);
  if (!ok) return c.json({ error: "No active link for this player under this manager" }, 404);
  return c.json({ ok: true });
});

// POST /games/:gameToken/push
// Upsert the open round and (re)enroll every player who has a token.
// Body: { mode, roundNumber, deadline?, gameName?, fixtures, jokerEnabled?, extra?,
//         previousResultsRoundNumber?, previousResults?, managerSuffix?, players }
// `extra` is an opaque, mode-specific JSON string (e.g. Killer's
// {"phase":"build"}) — stored and returned unread/unvalidated, exactly like
// fixtures/payload elsewhere in this file. Null/omitted for LMS/Predictor.
// `previousResults` (a pre-serialized JSON array string, same convention as
// `extra`) is the most-recently-closed round's outcome (survived/eliminated,
// points, lives/hits — opaque per mode) for `previousResultsRoundNumber`,
// piggybacked on whichever push happens next: a new round opening, a
// game-complete event with no new round, or a manual "resend" retry. Not a
// separate endpoint — always rides along with the same round_push upsert
// this route already does.
submissions.post("/games/:gameToken/push", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const kv = c.env.SUBMISSIONS_KV;
  // fixtureId/opponentName are set when a team plays twice in the round
  // (rearranged fixtures) — disambiguates which fixture occurrence this is.
  interface EligibleTeam { id: number; name: string; fixtureId?: number; opponentName?: string }
  interface PushPlayer {
    token: string;
    localPlayerId: string;
    // Roster member's current name — carried on every push so an in-app
    // rename refreshes the player link's playerName without a dedicated call.
    playerName?: string | null;
    eligibleTeams?: EligibleTeam[] | null;
  }
  const body = await c.req.json<{
    mode: string;
    roundNumber: number;
    deadline?: string | null;
    gameName?: string | null;
    fixtures: unknown[];
    jokerEnabled?: boolean;
    extra?: string | null;
    previousResultsRoundNumber?: number | null;
    previousResults?: string | null;
    managerSuffix?: string | null;
    managerName?: string | null;
    managerToken?: string | null;
    players: PushPlayer[];
  }>();
  const {
    mode, roundNumber, deadline, gameName, fixtures, jokerEnabled, extra,
    previousResultsRoundNumber, previousResults, managerSuffix, managerName, managerToken, players,
  } = body ?? {};
  if (!mode || roundNumber == null || !Array.isArray(fixtures)) {
    return c.json({ error: "mode, roundNumber, and fixtures are required" }, 400);
  }

  const ts = now();
  const mgrToken = managerToken?.toLowerCase() ?? null;

  // gameToken alone isn't proof of ownership — it's disclosed to every player
  // enrolled in the game via GET /s/:token, so anything mutating here must
  // also check the (non-disclosed) managerToken that claimed the game on its
  // first push. Games pushed before this check existed have managerToken
  // null and are grandfathered through — this push will claim them.
  const existing = await loadRoundPush(kv, gameToken);
  const owner = existing ? existing.managerToken : undefined;
  if (owner && owner !== mgrToken) {
    return c.json({ error: "forbidden" }, 403);
  }

  // COALESCE-equivalent: once a game is claimed by a managerToken, it stays
  // claimed — a later push with a different (or absent) token can't steal it
  // (already rejected by the owner check above) or un-claim it.
  const finalManagerToken = existing?.managerToken ?? mgrToken;

  const pushRecord: RoundPushRecord = {
    gameToken, mode, roundNumber,
    deadline: deadline ?? null,
    gameName: gameName ?? null,
    fixtures,
    jokerEnabled: !!jokerEnabled,
    managerToken: finalManagerToken,
    updatedAt: ts,
    extra: extra ?? null,
  };
  await kv.put(roundPushKey(gameToken), JSON.stringify(pushRecord), { expirationTtl: CONTENT_TTL_SECONDS });

  if (finalManagerToken) {
    await putMgrGame(kv, finalManagerToken, gameToken, { updatedAt: ts }, CONTENT_TTL_SECONDS);
    await ensureManagerLifecycle(kv, finalManagerToken);
  }

  const mgrPrefix = mgrPrefixFor(finalManagerToken);

  if (previousResultsRoundNumber != null && previousResults) {
    // `previousResults` arrives already JSON.stringify'd by the client (same
    // convention as `extra`) — parsed once here so the KV value is plain JSON,
    // not a doubly-encoded string.
    let parsedResults: unknown;
    try { parsedResults = JSON.parse(previousResults); } catch { parsedResults = []; }
    const resultRecord: ResultRecord = {
      gameToken, roundNumber: previousResultsRoundNumber, mode, results: parsedResults, createdAt: ts,
    };
    await kv.put(resultKey(gameToken, previousResultsRoundNumber), JSON.stringify(resultRecord), {
      expirationTtl: CONTENT_TTL_SECONDS,
    });

    // Keep the last 2 results rows per game (matches submissions' retention).
    if (previousResultsRoundNumber > 1) {
      const cutoff = previousResultsRoundNumber - 1;
      const page = await kv.list({ prefix: resultPrefix(gameToken) });
      for (const k of page.keys) {
        const rn = roundFromResultKey(k.name);
        if (rn !== null && rn < cutoff) await kv.delete(k.name);
      }
    }
  }

  // Prune submissions older than 2 rounds (aligned with Predictor publish retention).
  if (roundNumber > 2) {
    const cutoff = roundNumber - 2;
    const page = await kv.list({ prefix: submissionPrefixForGame(mgrPrefix, gameToken) });
    for (const k of page.keys) {
      const parsed = parseSubmissionKey(k.name);
      if (parsed && parsed.roundNumber < cutoff) await kv.delete(k.name);
    }
  }

  const suffix = managerSuffix?.toLowerCase() ?? null;
  const mgrName = managerName?.trim() ?? null;

  if (Array.isArray(players)) {
    for (const p of players) {
      const tk = p.token.toLowerCase();
      const pid = p.localPlayerId.toLowerCase();
      const link = await getPlayerLink(kv, tk);
      if (!link || link.revokedAt) continue;

      const membership: GameMembership = {
        gameToken,
        localPlayerId: pid,
        eligibleTeams: p.eligibleTeams ?? null,
        managerSuffix: suffix,
      };
      link.games = [...link.games.filter((g) => g.gameToken !== gameToken), membership];

      const newName = p.playerName?.trim() || null;
      if (mgrName && newName) {
        link.managerName = mgrName;
        link.playerName = newName;
      } else if (mgrName) {
        link.managerName = mgrName;
      } else if (newName) {
        link.playerName = newName;
      }

      await putPlayerLink(kv, link, CONTENT_TTL_SECONDS);
      await kv.put(gamePlayerKey(gameToken, tk), "", { expirationTtl: CONTENT_TTL_SECONDS });
    }
  }

  return c.json({ ok: true });
});

// GET /games/:gameToken/submissions?round=N
submissions.get("/games/:gameToken/submissions", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const round = c.req.query("round");
  const kv = c.env.SUBMISSIONS_KV;

  const owner = await loadGameOwner(kv, gameToken);
  if (owner === undefined) return c.json({ error: "game not found" }, 404);
  if (owner && owner !== managerTokenHeader(c)) return c.json({ error: "forbidden" }, 403);

  const mgrPrefix = mgrPrefixFor(owner);
  const prefix = round
    ? submissionPrefixForGameRound(mgrPrefix, gameToken, parseInt(round, 10))
    : submissionPrefixForGame(mgrPrefix, gameToken);

  const page = await kv.list<SubmissionMetadata>({ prefix });
  const results: Array<{
    id: string; token: string; playerName: string | null; localPlayerId: string | null;
    managerSuffix: string | null; roundNumber: number; payload: unknown; status: string;
    submittedAt: string; decidedAt: string | null;
  }> = [];
  for (const k of page.keys) {
    const parsed = parseSubmissionKey(k.name);
    if (!parsed) continue;
    const raw = await kv.get(k.name);
    if (!raw) continue;
    const rec = JSON.parse(raw) as SubmissionRecord;
    results.push({
      id: rec.id,
      token: rec.token,
      playerName: k.metadata?.playerName ?? null,
      localPlayerId: k.metadata?.localPlayerId ?? null,
      managerSuffix: k.metadata?.managerSuffix ?? null,
      roundNumber: rec.roundNumber,
      payload: rec.payload,
      status: rec.status,
      submittedAt: rec.submittedAt,
      decidedAt: rec.decidedAt,
    });
  }
  results.sort((a, b) => a.submittedAt.localeCompare(b.submittedAt));

  return c.json({ submissions: results });
});

// GET /manager/submissions/pending
// Aggregates pending submissions across every game owned by this manager, in
// one list() call (no per-game fan-out) — the whole point of the
// managerToken-first submission prefix (plan decision #4).
submissions.get("/manager/submissions/pending", async (c) => {
  const managerToken = managerTokenHeader(c);
  if (!managerToken) return c.json({ error: "X-Manager-Token header is required" }, 400);
  const kv = c.env.SUBMISSIONS_KV;

  const page = await kv.list<SubmissionMetadata>({ prefix: submissionPrefixForManager(managerToken) });
  const results: Array<{
    id: string; token: string; playerName: string | null; localPlayerId: string | null;
    managerSuffix: string | null; roundNumber: number; payload: unknown; status: string;
    submittedAt: string; decidedAt: string | null; gameToken: string; gameName: string | null; mode: string | null;
  }> = [];
  for (const k of page.keys) {
    if (k.metadata?.status !== "pending") continue;
    const parsed = parseSubmissionKey(k.name);
    if (!parsed) continue;
    const raw = await kv.get(k.name);
    if (!raw) continue;
    const rec = JSON.parse(raw) as SubmissionRecord;
    results.push({
      id: rec.id,
      token: rec.token,
      playerName: k.metadata?.playerName ?? null,
      localPlayerId: k.metadata?.localPlayerId ?? null,
      managerSuffix: k.metadata?.managerSuffix ?? null,
      roundNumber: rec.roundNumber,
      payload: rec.payload,
      status: rec.status,
      submittedAt: rec.submittedAt,
      decidedAt: rec.decidedAt,
      gameToken: parsed.gameToken,
      gameName: k.metadata?.gameName ?? null,
      mode: k.metadata?.mode ?? null,
    });
  }
  results.sort((a, b) => a.submittedAt.localeCompare(b.submittedAt));

  return c.json({ submissions: results });
});

// Finds the full submission key for a given opaque `id` within one game —
// `id` is a random UUID stored in both the value and the metadata
// (metadata.id), so this costs one list() (metadata only) plus one get() for
// the match, never a get() per candidate.
async function findSubmissionById(
  kv: KVNamespace, mgrPrefix: string, gameToken: string, id: string,
): Promise<{ key: string; metadata: SubmissionMetadata } | null> {
  const page = await kv.list<SubmissionMetadata>({ prefix: submissionPrefixForGame(mgrPrefix, gameToken) });
  for (const k of page.keys) {
    if (k.metadata?.id === id) return { key: k.name, metadata: k.metadata };
  }
  return null;
}

// POST /games/:gameToken/submissions/:id/approve
submissions.post("/games/:gameToken/submissions/:id/approve", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const id = c.req.param("id").toLowerCase();
  const kv = c.env.SUBMISSIONS_KV;

  const owner = await loadGameOwner(kv, gameToken);
  if (owner === undefined) return c.json({ error: "game not found" }, 404);
  if (owner && owner !== managerTokenHeader(c)) return c.json({ error: "forbidden" }, 403);

  const mgrPrefix = mgrPrefixFor(owner);
  const found = await findSubmissionById(kv, mgrPrefix, gameToken, id);
  if (!found || found.metadata.status !== "pending") {
    return c.json({ error: "submission not found or already decided" }, 404);
  }

  const raw = await kv.get(found.key);
  if (!raw) return c.json({ error: "submission not found or already decided" }, 404);
  const rec = JSON.parse(raw) as SubmissionRecord;
  rec.status = "approved";
  rec.decidedAt = now();

  const metadata: SubmissionMetadata = { ...found.metadata, status: "approved" };
  await kv.put(found.key, JSON.stringify(rec), { metadata, expirationTtl: SUBMISSION_TTL_SECONDS });

  return c.json({
    id: rec.id,
    localPlayerId: found.metadata.localPlayerId,
    managerSuffix: found.metadata.managerSuffix,
    roundNumber: rec.roundNumber,
    payload: rec.payload,
  });
});

// POST /games/:gameToken/submissions/:id/reject
submissions.post("/games/:gameToken/submissions/:id/reject", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const id = c.req.param("id").toLowerCase();
  const kv = c.env.SUBMISSIONS_KV;

  const owner = await loadGameOwner(kv, gameToken);
  if (owner === undefined) return c.json({ error: "game not found" }, 404);
  if (owner && owner !== managerTokenHeader(c)) return c.json({ error: "forbidden" }, 403);

  const mgrPrefix = mgrPrefixFor(owner);
  const found = await findSubmissionById(kv, mgrPrefix, gameToken, id);
  if (!found || found.metadata.status !== "pending") {
    return c.json({ error: "submission not found or already decided" }, 404);
  }

  const raw = await kv.get(found.key);
  if (!raw) return c.json({ error: "submission not found or already decided" }, 404);
  const rec = JSON.parse(raw) as SubmissionRecord;
  rec.status = "rejected";
  rec.decidedAt = now();

  const metadata: SubmissionMetadata = { ...found.metadata, status: "rejected" };
  await kv.put(found.key, JSON.stringify(rec), { metadata, expirationTtl: SUBMISSION_TTL_SECONDS });

  return c.json({ ok: true });
});

// DELETE /games/:gameToken
// Called when the manager deletes the game on-device. Removes this game's
// round/enrollment/submission/result keys. Does NOT touch player_link
// records themselves — those are one global link per player, shared across
// all of a player's games; only this game's entry is spliced out of each.
submissions.delete("/games/:gameToken", async (c) => {
  const gameToken = c.req.param("gameToken").toLowerCase();
  const kv = c.env.SUBMISSIONS_KV;

  const owner = await loadGameOwner(kv, gameToken);
  if (owner === undefined) return c.json({ error: "game not found" }, 404);
  if (owner && owner !== managerTokenHeader(c)) return c.json({ error: "forbidden" }, 403);

  const mgrPrefix = mgrPrefixFor(owner);

  // Splice this game out of every enrolled player-link's games[] — game_player:
  // is exactly the index that exists to make this lookup possible without a
  // manager-token-scoped scan (games can be grandfathered/unclaimed too).
  const gamePlayers = await kv.list({ prefix: gamePlayerPrefix(gameToken) });
  for (const k of gamePlayers.keys) {
    const token = tokenFromGamePlayerKey(k.name);
    if (!token) continue;
    const link = await getPlayerLink(kv, token);
    if (link) {
      link.games = link.games.filter((g) => g.gameToken !== gameToken);
      await putPlayerLink(kv, link, CONTENT_TTL_SECONDS);
    }
    await kv.delete(k.name);
  }

  await kv.delete(roundPushKey(gameToken));
  if (owner) await deleteMgrGame(kv, owner, gameToken);

  const subs = await kv.list({ prefix: submissionPrefixForGame(mgrPrefix, gameToken) });
  for (const k of subs.keys) await kv.delete(k.name);

  const results = await kv.list({ prefix: resultPrefix(gameToken) });
  for (const k of results.keys) await kv.delete(k.name);

  return c.json({ ok: true });
});

// ─── Player-facing (PWA) ─────────────────────────────────────────────────────

// GET /s/:token
// Returns all active games for this player. Each game includes jokerEnabled and
// managerSuffix so the PWA can display identity and render the joker control.
submissions.get("/s/:token", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const kv = c.env.SUBMISSIONS_KV;

  const link = await touchPlayerLink(kv, token);
  if (!link) return c.json({ error: "Link not found." }, 404);
  if (link.revokedAt) return c.json({ error: "This link has been revoked." }, 404);

  const games = await Promise.all(link.games.map(async (membership) => {
    const push = await loadRoundPush(kv, membership.gameToken);
    if (!push) return null; // game deleted — original JOIN would simply omit it

    const mgrPrefix = mgrPrefixFor(push.managerToken);
    const currentKey = submissionKey(mgrPrefix, membership.gameToken, push.roundNumber, token);
    const priorRaw = await kv.get(currentKey);
    const prior = priorRaw ? (JSON.parse(priorRaw) as SubmissionRecord) : null;

    // Last-2-rounds submission history + "what actually happened" — fetched
    // by direct key (round numbers are known, no list() needed) for the
    // window [max(1, current-2), current-1].
    const historyByRound = new Map<number, Record<string, unknown>>();
    const lo = Math.max(1, push.roundNumber - 2);
    for (let r = lo; r < push.roundNumber; r++) {
      const subRaw = await kv.get(submissionKey(mgrPrefix, membership.gameToken, r, token));
      if (subRaw) {
        const sub = JSON.parse(subRaw) as SubmissionRecord;
        historyByRound.set(r, {
          roundNumber: r, status: sub.status, submittedAt: sub.submittedAt, payload: sub.payload,
        });
      }
      const resultRaw = await kv.get(resultKey(membership.gameToken, r));
      if (resultRaw) {
        const result = JSON.parse(resultRaw) as ResultRecord;
        const entries = (Array.isArray(result.results) ? result.results : []) as { playerId?: string }[];
        const mine = entries.find((e) => e.playerId?.toLowerCase() === (membership.localPlayerId ?? "").toLowerCase());
        if (mine) {
          const existing = historyByRound.get(r);
          if (existing) existing.result = mine;
          else historyByRound.set(r, { roundNumber: r, result: mine });
        }
      }
    }

    const game: Record<string, unknown> = {
      gameToken: membership.gameToken,
      mode: push.mode,
      roundNumber: push.roundNumber,
      deadline: push.deadline,
      gameName: push.gameName ?? null,
      fixtures: push.fixtures,
      jokerEnabled: push.jokerEnabled,
      managerSuffix: membership.managerSuffix ?? null,
      // Lets the PWA identify "me" in a mode-agnostic per-player roster (e.g.
      // Killer's opponent list) without a separate lookup.
      localPlayerId: membership.localPlayerId ?? null,
    };
    if (membership.eligibleTeams != null) game.eligibleTeams = membership.eligibleTeams;
    if (push.extra) game.extra = push.extra;
    if (prior) {
      game.priorSubmission = {
        roundNumber: prior.roundNumber, status: prior.status, submittedAt: prior.submittedAt, payload: prior.payload,
      };
    }
    if (historyByRound.size > 0) {
      game.history = Array.from(historyByRound.values()).sort(
        (a, b) => (b.roundNumber as number) - (a.roundNumber as number),
      );
    }
    return game;
  }));

  return c.json({
    playerName: link.playerName,
    managerName: link.managerName ?? null,
    games: games.filter((g): g is Record<string, unknown> => g !== null),
  });
});

// POST /s/:token/games/:gameToken
// Submit (or resubmit) for one specific game.
// LMS body: { teamId, teamName?, fixtureId? } — fixtureId disambiguates a team
// playing twice in the round.
// Predictor body: { scores: [{fixtureId, home, away, isJoker?}] }
// All modes may optionally include `roundNumber` (the round the client loaded
// against) — if present and stale, the submission is rejected with 409 rather
// than silently landing against whatever round is now live.
submissions.post("/s/:token/games/:gameToken", async (c) => {
  const token = c.req.param("token").toLowerCase();
  const gameToken = c.req.param("gameToken").toLowerCase();
  const body = await c.req.json<Record<string, unknown>>();
  const kv = c.env.SUBMISSIONS_KV;

  const link = await getPlayerLink(kv, token);
  const membership = link?.games.find((g) => g.gameToken === gameToken);
  if (!link || link.revokedAt || !membership) {
    return c.json({ error: "Link not found, revoked, or not enrolled in this game." }, 404);
  }

  const push = await loadRoundPush(kv, gameToken);
  if (!push) return c.json({ error: "No active round for this game." }, 404);

  // If the client tells us which round it loaded against, reject a submission
  // that's fallen behind — otherwise a stale tab (round N still open in the
  // browser after the manager has moved on to round N+1) silently overwrites
  // whatever was already submitted for the new round via the upsert below.
  // Optional/backwards-compatible: an old cached PWA build that doesn't send
  // roundNumber still gets today's behavior.
  const submittedRoundNumber = typeof body.roundNumber === "number" ? body.roundNumber : null;
  if (submittedRoundNumber !== null && submittedRoundNumber !== push.roundNumber) {
    return c.json({ error: "round_moved_on", currentRound: push.roundNumber }, 409);
  }

  // `deadline` was previously display-only — a submission arriving after it
  // (e.g. a tab left open past cutoff) was silently accepted. Reject it
  // server-side instead of relying on the PWA's own clock, which the client
  // controls.
  if (push.deadline && Date.now() > new Date(push.deadline).getTime()) {
    return c.json({ error: "deadline_passed", deadline: push.deadline }, 403);
  }

  // This endpoint is unauthenticated by design (anonymous player token, no
  // login) — anyone who guesses or leaks a token can POST arbitrary JSON
  // here, so unlike the JWT-gated manager push above, the shape/range of
  // this body is worth policing before it's persisted and later trusted by
  // the manager's approve flow. Validates against `push.mode`, which comes
  // from the trusted round_push record, not from this body. Stores the
  // whitelisted, sanitized value — not the raw body — as a second layer of
  // defense against unexpected extra fields.
  const validation = validateSubmissionPayload(push.mode, body);
  if (!validation.ok) return c.json({ error: validation.error }, 400);

  // A round number can match while the fixtures underneath it have already
  // moved on in some edge case (or a client is simply sending fabricated
  // ids) — cross-check every fixtureId the payload references is actually
  // part of the round currently pushed for this game.
  const pushedFixtureIds = new Set((push.fixtures as Array<{ fixtureId: number }>).map((f) => f.fixtureId));
  const badFixtureId = referencedFixtureIds(push.mode, validation.value).find((id) => !pushedFixtureIds.has(id));
  if (badFixtureId !== undefined) {
    return c.json({ error: `fixtureId ${badFixtureId} is not part of the current round` }, 400);
  }

  const ts = now();
  const mgrPrefix = mgrPrefixFor(push.managerToken);
  const rec: SubmissionRecord = {
    id: crypto.randomUUID().toLowerCase(),
    token, gameToken, roundNumber: push.roundNumber,
    payload: validation.value, status: "pending", submittedAt: ts, decidedAt: null,
  };
  const metadata: SubmissionMetadata = {
    id: rec.id, status: "pending", submittedAt: ts, roundNumber: push.roundNumber,
    playerName: link.playerName, localPlayerId: membership.localPlayerId,
    managerSuffix: membership.managerSuffix, gameName: push.gameName, mode: push.mode,
  };
  await putSubmission(kv, mgrPrefix, rec, metadata);

  return c.json({ ok: true });
});
