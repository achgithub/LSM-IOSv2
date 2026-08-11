#!/bin/bash
# Manual smoke test against `wrangler dev --env uk` (local KV only — no D1,
# no --remote, no production data involved). Modeled on Clubroom2's
# worker/test/smoke.sh (curl/pass/fail structure).
#
# worker-api-v2 doesn't mint JWTs itself — worker-api is the identity
# authority (App Attest device registry + JWT signing); this Worker only
# verifies. So this script mints its own throwaway test JWT locally in Node,
# signed with a private key that ONLY ever exists here and in .dev.vars'
# matching JWT_PUBLIC_KEYS override — never a real secret, never used against
# a real deploy. This means the smoke test runs fully offline: no live
# worker-api instance needs to be running.
#
# (If you'd rather test against a *real* worker-api-issued JWT instead, run
# worker-api's own POST /attest/assert dev-bypass flow separately and pass
# the resulting token in via JWT="<token>" test/smoke.sh — but note that only
# verifies if wrangler.jsonc's JWT_PUBLIC_KEYS — worker-api's real public
# key — is what's actually loaded, i.e. you're not running under the
# .dev.vars override below.)
#
# Exercises the full lifecycle: mint a link → push a round → player GET →
# player submit → manager list (per-game + aggregate) → approve → re-GET →
# delete-game → revoke. Also touches revoke-by-name and unsubscribe/
# resubscribe/entitlements since those are new KV-only logic worth covering
# directly.
set -euo pipefail

BASE="${1:-http://127.0.0.1:8788}"

# Throwaway ES256 keypair, local-test-only — matches .dev.vars'
# JWT_PUBLIC_KEYS override for kid "uk-2026-01". Never used for a real
# deploy; regenerate freely if needed (see jwt.ts's header comment for the
# one-off Web Crypto snippet), just keep .dev.vars' public half in sync.
TEST_JWT_PRIVATE_KEY_PKCS8_B64="MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgWzL+sx1HTuDh++5c1dviViNLotw+Pl+Agfgsc2rXd16hRANCAATaJ0p4Cpide5RNLfYqivRAMlwggLtyTeVH6+KzQwWPSWbgd5a+0LYXT4FgONaOpTmEqu/xcXlRQt/fJJ0WUN4i"
# Randomized per run (not just GAME_TOKEN) — local KV/D1 state persists on
# disk across repeated `wrangler dev` sessions, so a fixed manager/player
# name would let one run's leftover (still-active, short-TTL-but-not-yet-
# expired) records leak into the next run's revoke-by-name matching.
RUN_ID=$(date +%s)-$$
MANAGER_TOKEN="manager-$RUN_ID"
GAME_TOKEN="game-$RUN_ID"
PLAYER_NAME="Smoke Test Player $RUN_ID"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

echo "== mint a test JWT locally (no live worker-api needed) =="
if [ -n "${JWT:-}" ]; then
  pass "using caller-supplied JWT"
else
  JWT=$(node -e "
    const { subtle } = require('crypto').webcrypto;
    const kid = 'uk-2026-01';
    const b64uFromBytes = (bytes) => Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const b64uFromObj = (obj) => b64uFromBytes(Buffer.from(JSON.stringify(obj)));
    (async () => {
      const der = Buffer.from('$TEST_JWT_PRIVATE_KEY_PKCS8_B64', 'base64');
      const key = await subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
      const now = Math.floor(Date.now() / 1000);
      const header = b64uFromObj({ alg: 'ES256', typ: 'JWT', kid });
      const payload = b64uFromObj({ iss: 'https://api.uk.sportsmanager.site', iat: now, exp: now + 900 });
      const toSign = Buffer.from(header + '.' + payload);
      const sig = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, toSign);
      console.log(header + '.' + payload + '.' + b64uFromBytes(Buffer.from(sig)));
    })();
  ")
  [ -n "$JWT" ] && pass "minted test JWT" || fail "JWT minting failed"
fi
AUTH=(-H "Authorization: Bearer $JWT")

echo "== mint a player link =="
MINT=$(curl -sf -X POST "$BASE/links" "${AUTH[@]}" -H 'content-type: application/json' -d '{
  "playerName": "'"$PLAYER_NAME"'", "managerToken": "'"$MANAGER_TOKEN"'", "managerName": "Smoke Manager"
}')
TOKEN=$(echo "$MINT" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).token))")
[ -n "$TOKEN" ] && pass "minted player link: $TOKEN" || fail "mint failed: $MINT"

echo "== mint is unconditional — a second link for the same name doesn't 409 =="
# Uses a distinct name so it doesn't collide with $TOKEN in the later
# revoke-by-name test (revoke-by-name matches by playerName, and playerName
# is deliberately non-unique now — plan decision #2).
MINT2=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/links" "${AUTH[@]}" -H 'content-type: application/json' -d '{
  "playerName": "'"$PLAYER_NAME"' (duplicate)", "managerToken": "'"$MANAGER_TOKEN"'"
}')
[ "$MINT2" = "200" ] && pass "second mint for same name succeeded (200, not 409)" || fail "expected 200, got $MINT2"

echo "== push a round =="
PUSH=$(curl -sf -X POST "$BASE/games/$GAME_TOKEN/push" "${AUTH[@]}" -H 'content-type: application/json' -d '{
  "mode": "lms", "roundNumber": 1, "gameName": "Smoke League",
  "fixtures": [{"fixtureId": 101, "homeTeamId": 1, "awayTeamId": 2}],
  "managerToken": "'"$MANAGER_TOKEN"'", "managerSuffix": "sm",
  "players": [{"token": "'"$TOKEN"'", "localPlayerId": "p1", "playerName": "'"$PLAYER_NAME"'",
               "eligibleTeams": [{"id": 1, "name": "Team One"}, {"id": 2, "name": "Team Two"}]}]
}')
echo "$PUSH" | grep -q '"ok":true' && pass "pushed round 1" || fail "push failed: $PUSH"

echo "== push from a different manager token is rejected (403) =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/games/$GAME_TOKEN/push" "${AUTH[@]}" -H 'content-type: application/json' -d '{
  "mode": "lms", "roundNumber": 2, "fixtures": [], "managerToken": "some-other-manager", "players": []
}')
[ "$STATUS" = "403" ] && pass "cross-manager push rejected (403)" || fail "expected 403, got $STATUS"

echo "== player GET shows the pushed fixture =="
VIEW=$(curl -sf "$BASE/s/$TOKEN")
echo "$VIEW" | grep -q "$GAME_TOKEN" && pass "player view includes game" || fail "player view missing game: $VIEW"
echo "$VIEW" | grep -q '"fixtureId":101' && pass "player view includes fixture" || fail "player view missing fixture: $VIEW"

echo "== player submits a pick =="
SUB=$(curl -sf -X POST "$BASE/s/$TOKEN/games/$GAME_TOKEN" -H 'content-type: application/json' -d '{
  "teamId": 1, "fixtureId": 101, "roundNumber": 1
}')
echo "$SUB" | grep -q '"ok":true' && pass "submission accepted" || fail "submission failed: $SUB"

echo "== stale round number is rejected (409) =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/s/$TOKEN/games/$GAME_TOKEN" -H 'content-type: application/json' -d '{
  "teamId": 1, "fixtureId": 101, "roundNumber": 99
}')
[ "$STATUS" = "409" ] && pass "stale roundNumber rejected (409)" || fail "expected 409, got $STATUS"

echo "== a fixtureId not in the current round is rejected (400) =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/s/$TOKEN/games/$GAME_TOKEN" -H 'content-type: application/json' -d '{
  "teamId": 1, "fixtureId": 999
}')
[ "$STATUS" = "400" ] && pass "unknown fixtureId rejected (400)" || fail "expected 400, got $STATUS"

echo "== manager lists submissions for this game =="
LIST=$(curl -sf "$BASE/games/$GAME_TOKEN/submissions" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$LIST" | grep -q '"status":"pending"' && pass "per-game list shows pending submission" || fail "per-game list missing pending: $LIST"
SUB_ID=$(echo "$LIST" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).submissions[0].id))")
[ -n "$SUB_ID" ] && pass "got submission id: $SUB_ID" || fail "no submission id"

echo "== manager-wide pending aggregate shows the same submission =="
PENDING=$(curl -sf "$BASE/manager/submissions/pending" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$PENDING" | grep -q "\"id\":\"$SUB_ID\"" && pass "aggregate pending list includes it" || fail "aggregate list missing it: $PENDING"
echo "$PENDING" | grep -q '"gameName":"Smoke League"' && pass "aggregate list carries gameName from metadata" || fail "aggregate list missing gameName: $PENDING"

echo "== approve the submission =="
APPROVE=$(curl -sf -X POST "$BASE/games/$GAME_TOKEN/submissions/$SUB_ID/approve" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$APPROVE" | grep -q '"payload"' && pass "approve returned the payload" || fail "approve response missing payload: $APPROVE"

echo "== approving again 404s (already decided) =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/games/$GAME_TOKEN/submissions/$SUB_ID/approve" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
[ "$STATUS" = "404" ] && pass "re-approve rejected (404)" || fail "expected 404, got $STATUS"

echo "== re-GET the per-game list shows approved status =="
# Documenting the accepted ≤60s KV staleness window here, not working around
# it — against a fresh local `wrangler dev` KV there's no real propagation
# delay, so this assertion is expected to pass immediately in this
# environment; production callers should not assume the same latency.
LIST2=$(curl -sf "$BASE/games/$GAME_TOKEN/submissions" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$LIST2" | grep -q '"status":"approved"' && pass "re-GET shows approved" || fail "re-GET didn't show approved: $LIST2"

echo "== manager status is active (has a recent push, not warned/unsubscribed) =="
STATUS_JSON=$(curl -sf "$BASE/manager/status" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$STATUS_JSON" | grep -q '"state":"active"' && pass "manager status active" || fail "expected active: $STATUS_JSON"

echo "== unsubscribe sets scheduledDeleteAt =="
UNSUB=$(curl -sf -X POST "$BASE/manager/unsubscribe" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$UNSUB" | grep -q '"scheduledDeleteAt"' && pass "unsubscribe scheduled a delete" || fail "unsubscribe response missing scheduledDeleteAt: $UNSUB"

STATUS_JSON=$(curl -sf "$BASE/manager/status" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$STATUS_JSON" | grep -q '"state":"pending_delete"' && pass "manager status now pending_delete" || fail "expected pending_delete: $STATUS_JSON"

echo "== resubscribe clears it =="
RESUB=$(curl -sf -X POST "$BASE/manager/resubscribe" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$RESUB" | grep -q '"ok":true' && pass "resubscribed" || fail "resubscribe failed: $RESUB"
STATUS_JSON=$(curl -sf "$BASE/manager/status" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$STATUS_JSON" | grep -q '"state":"active"' && pass "manager status active again after resubscribe" || fail "expected active: $STATUS_JSON"

echo "== entitlements accepts a cap report =="
ENT=$(curl -sf -X POST "$BASE/manager/entitlements" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN" -H 'content-type: application/json' -d '{"maxPWALinks": 140}')
echo "$ENT" | grep -q '"ok":true' && pass "entitlements accepted" || fail "entitlements failed: $ENT"

echo "== delete the game =="
DEL=$(curl -sf -X DELETE "$BASE/games/$GAME_TOKEN" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
echo "$DEL" | grep -q '"ok":true' && pass "game deleted" || fail "delete failed: $DEL"

echo "== player view no longer includes the deleted game =="
VIEW2=$(curl -sf "$BASE/s/$TOKEN")
echo "$VIEW2" | grep -q "$GAME_TOKEN" && fail "deleted game still present: $VIEW2" || pass "deleted game no longer in player view"

echo "== deleting again 404s (game already gone) =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/games/$GAME_TOKEN" "${AUTH[@]}" -H "X-Manager-Token: $MANAGER_TOKEN")
[ "$STATUS" = "404" ] && pass "re-delete rejected (404)" || fail "expected 404, got $STATUS"

echo "== revoke-by-name =="
REVOKE_NAME=$(curl -sf -X POST "$BASE/links/revoke-by-name" "${AUTH[@]}" -H 'content-type: application/json' -d '{
  "playerName": "'"$PLAYER_NAME"'", "managerToken": "'"$MANAGER_TOKEN"'"
}')
echo "$REVOKE_NAME" | grep -q '"ok":true' && pass "revoke-by-name succeeded" || fail "revoke-by-name failed: $REVOKE_NAME"

echo "== revoked link 404s on player GET =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/s/$TOKEN")
[ "$STATUS" = "404" ] && pass "revoked link 404s" || fail "expected 404, got $STATUS"

echo "== revoke-by-name again is idempotent-safe: no *active* link left, so 404 =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/links/revoke-by-name" "${AUTH[@]}" -H 'content-type: application/json' -d '{
  "playerName": "'"$PLAYER_NAME"'", "managerToken": "'"$MANAGER_TOKEN"'"
}')
[ "$STATUS" = "404" ] && pass "second revoke-by-name 404s as expected (no active link)" || fail "expected 404, got $STATUS"

echo "== direct token revoke on an already-revoked token 404s =="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/links/$TOKEN/revoke" "${AUTH[@]}")
[ "$STATUS" = "404" ] && pass "revoke of already-revoked token 404s" || fail "expected 404, got $STATUS"

echo
echo "All smoke tests passed."
