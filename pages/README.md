# LSM Cloud Publish viewer (Cloudflare Pages)

The PIN-gated page a published Predictor league's `/l/<id>` link opens (§0).
Renders standings, recent matchdays' results, and the next matchday's
fixtures from a snapshot the manager's app published to the Worker.

## How it works

Deliberately has **no D1/R2 bindings of its own**. The Worker
(`worker/src/routes/publish.ts`, `POST /publish/:id/unlock`) is the only
thing that ever validates the PIN and touches the blob — this Pages project
is just a static PIN form (`functions/l/[id].js`, `onRequestGet`) that POSTs
the entered PIN to that one Worker endpoint and renders whatever comes back
(`onRequestPost`). That keeps provisioning to "static site + one env var",
no secrets stored here.

## Status

**Code only — not yet deployed.** Provisioning this as an actual Cloudflare
Pages project (and setting its `WORKER_BASE_URL` env var to a deployed
shard's URL, e.g. `https://lsm-uk-worker.<account>.workers.dev`) is a
deploy-affecting action to confirm with Andrew first, same as the R2
bucket/D1 migration this depends on (see `worker/wrangler.jsonc`,
`worker/schema.sql`'s `publish_links` table).

## Local preview

```
npx wrangler pages dev pages/public --compatibility-date=2026-06-14 \
  --binding WORKER_BASE_URL=http://localhost:8799
```
(with `worker`'s `wrangler dev --env uk --local` running on 8799 — see
`worker/README.md` / `.dev.vars` for the `ATTEST_DEV_BYPASS` local-only flag.
Cloud Publish's `/unlock` route itself isn't attest-gated, so that flag isn't
actually needed just to preview this page — only `POST /publish` requires it.)
