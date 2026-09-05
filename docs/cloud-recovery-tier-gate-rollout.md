# Cloud Recovery Tier Gate — Rollout

Status: **code complete, nothing deployed or shipped.** Agreed 2026-09-05.

Recovery-email registration is now a cloud-tier feature (`leagues_3` and above).
Free / No Ads back up with **Export for Transfer** instead. All code is committed
and pushed on `redesign-v2-full` (through `346ec04`).

---

## Why the order matters

The server gate returns **403** to any client that still offers the registration
form. Live **1.2 offers it to everyone**, including at first-launch onboarding.

Deploy `worker-api` before the force-upgrade and every new free user sees:

> Couldn't verify this device with the server (403). Try again, and if this keeps
> happening, send a report from Settings → Report a Bug.

Wrong, alarming, and it explicitly invites bug reports. The version gate has to
land first so those clients can't reach the endpoint at all.

The server can't distinguish old clients from new ones on its own — the version
gate is client-side (the app fetches `minVersion` and blocks *itself*), and no
app version is sent on any request. Only `Authorization`, `X-Manager-Token` and
`X-Shard-Id` reach the worker.

---

## Sequence

### 1. Ship the app

Build + upload **1.3 / build 103** from **`redesign-v2-full`**.

> ⚠️ Not `main` — it is ~68 commits behind and contains none of this work.
> `MARKETING_VERSION = 1.3` and `CURRENT_PROJECT_VERSION = 103` are already set.

### 2. 🚦 Hard gate — confirm 1.3 is downloadable

**Actually installable from the App Store, not merely "approved".** Every step
below is safe only because an update exists to force people onto. Raising
`minVersion` before this locks out every user with no escape but reverting.

### 3. Force the upgrade

Set `minVersion: "1.3"` in `worker/src/manifest.ts` (currently `"1.0"`, a no-op),
then deploy `worker` to **both regions**:

```bash
cd worker
pnpm deploy:uk
pnpm deploy:eu
```

Compares `CFBundleShortVersionString`, so **the build number is irrelevant** —
the value must be exactly `"1.3"`.

Hardcoded rather than KV-backed by choice: a redeploy takes seconds, so rollback
is cheap enough not to warrant the extra machinery.

### 4. Verify the block

- A 1.2 device shows the hard **"Update Required"** screen (no dismiss)
- A 1.3 device is unaffected
- `leagues.json` is served with no cache headers, so the change propagates
  immediately

**Rollback:** set `minVersion` back to `"1.0"` and redeploy.

### 5. Wait a few days

This buys **change isolation**, not straggler protection. A blocked client can't
reach the API at all — `VersionGateView` replaces the root before `V2RootView`
or `RootTabView` mounts, so the onboarding sheet never appears and
`/account/register` is unreachable.

No urgency either way: 1.3's client-side gate already hides the registration form
from free users. The worker gate only catches requests made outside the app.

### 6. Deploy the server gate

```bash
cd worker-api
pnpm deploy:uk
pnpm deploy:eu
```

### 7. Verify

- Free tier registering → 403 `cloud_tier_required`
- 3L+ tier → code arrives, registration completes
- **Link-device recovery still works on every tier** (must never be gated)

---

## Design notes

**The server gate is soft, deliberately.** `manager_lifecycle.max_pwa_links` is
reported by the client on every launch — tier is a StoreKit concept the server
can't verify, so a hand-crafted request could claim anything. This closes the
casual path, not a determined one.

**It fails open on every uncertain case:**

| Server's record | Meaning | Result |
| --- | --- | --- |
| A number (60/100/140) | 3L / 5L / 7L | Allow |
| Row exists, value `NULL` | Free or No Ads | **Refuse** |
| No row at all | Never reported yet | Allow |
| Lookup failed | Server-side problem | Allow |

Only a record that positively says "no cloud tier" is refused. A paying manager
mid-first-launch, offline, or with a dropped entitlement report simply has no
record, so they pass. That asymmetry is what made this safe to add at all.

**Link-device and reauthorize are ungated by design.** They are recovery, they
run on devices with no resolved tier by definition, and they gate themselves —
you can only link to an account that already exists, and accounts are only
created by an entitled manager.

**Forcing an upgrade is normally too blunt for this.** `minVersion`'s own comment
says *"bump only for a genuinely breaking change"*, and this isn't one — nothing
about an old client is incompatible with the API; it just offers a feature it
shouldn't. Accepted deliberately because the user base is small enough right now
that it's cheap. That gets more expensive with every user added.

**Fallback if this goes wrong:** add an `X-App-Version` header and exempt old
clients instead of blocking them. Nothing here forecloses that.

---

## Related

- `ios/LSM/LSM/Shared/Onboarding/ManagerOnboardingView.swift` — first-launch tier branch
- `ios/LSM/LSM/Shared/Onboarding/RecoveryEmailPrompt.swift` — the 30-day nudge
- `ios/LSM/LSM/Shared/Settings/ProfileSettingsView.swift` — gate rationale in the header
- `worker-api/src/routes/account.ts` — `hasCloudEntitlement`
- `worker/src/manifest.ts` — `minVersion`
- `ios/LSM/LSM/Cloud/VersionGate.swift` — client-side block
