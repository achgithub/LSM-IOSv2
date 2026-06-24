---
name: run-lsm
description: Build, launch, and drive the LSM iOS app (Last Stand Manager) on the iOS Simulator or on Andrew's iPhone. Use when asked to run, start, build, launch, test, or screenshot the LSM app, or to confirm a change works in the real app. macOS-only.
---

# Run the LSM iOS app

LSM (`com.sportsmanager.LSM`) is a SwiftUI iOS app. It is **driven via
XCUITest** — `simctl`/`devicectl` can launch the app but cannot tap, so UI
navigation goes through the `LSMUITests` target, wrapped by `drive.sh`. The app
reads live league data from the v2 Cloudflare Workers
(`lsm-uk-worker` / `lsm-eu-worker`), so a successful run also confirms that path.

**macOS only.** The iOS Simulator and on-device install require it; there is no
Linux path. All paths below are relative to the app unit `ios/LSM/`.

## ALWAYS ASK FIRST: Simulator or Andrew's iPhone?

When the user says "run the app" (or similar), **ask which target** before
doing anything — use `AskUserQuestion`:

- **Simulator** (`drive.sh sim`) — headless-friendly, screenshots auto-export. Default.
- **Andrew's iPhone** (`drive.sh device`) — real device "Andy H" (iPhone 16).
  Requires the phone connected, paired, and **unlocked** (launch fails on a
  locked phone — see Gotchas).

Only skip the question if the user already named the target.

## Prerequisites

Xcode + command-line tools (already present on this machine). No `apt-get` /
brew packages needed — `xcodebuild`, `xcrun simctl`, and `xcrun devicectl` ship
with Xcode. Signing is automatic (team `UD928WR9RR`); device builds pass
`-allowProvisioningUpdates` (handled by the driver).

## Run (agent path — use this)

From `ios/LSM/`:

```bash
# Simulator: boot → build → install → launch → drive (UI test) → screenshots
./.claude/skills/run-lsm/drive.sh sim

# Andrew's iPhone (UNLOCK IT FIRST): build → install → launch via devicectl
./.claude/skills/run-lsm/drive.sh device

# Skip the UI-test drive (just launch the app):
./.claude/skills/run-lsm/drive.sh sim --no-test
```

The driver writes build products + screenshots under `$LSM_OUT` (default
`$TMPDIR/lsm-run`); override it to keep output in a scratch dir:

```bash
LSM_OUT=/path/to/scratch/lsm-run ./.claude/skills/run-lsm/drive.sh sim
```

Screenshots land in `$LSM_OUT/shots/*.png` (Standings + Matches). **Open them
and look** — a load-error screen means the Workers/network path is broken, not
that the app launched fine.

Knobs (env vars): `LSM_SIM_NAME` (default `iPhone 17`), `LSM_DEVICE_ID`
(default is Andy H's id — refresh with `xcrun devicectl list devices`).

### How the drive works (the harness)

`simctl`/`devicectl` can't tap, so the actual interaction lives in an XCUITest:
`LSMUITests/LMSSmokeUITests.swift` →
`testLeaguesLoadFromV2Workers`. It launches with `-uitests` (skips ad/consent
dialogs, keeps the network live), handles first-run onboarding, taps the
**Standings** and **Matches** tabs, asserts real rows loaded from the v2
Workers, and attaches a screenshot per screen. `drive.sh` runs that test and
exports the attachments. To navigate somewhere new, add a test method there and
point `-only-testing` at it.

To confirm the app really hit the Workers (independent of the UI), check the
simulator log:

```bash
xcrun simctl spawn "iPhone 17" log show --last 2m \
  --predicate 'eventMessage CONTAINS "workers.dev"' --style compact 2>/dev/null \
  | grep -oE 'https://lsm-[a-z]+-worker\.sportsmanager\.workers\.dev[^ ,]*' | sort -u
```

## Run (human path)

Open `LSM.xcodeproj` in Xcode, pick the `LSM` scheme + a simulator or Andy H,
press ⌘R. Useless headless — use the driver instead.

## Test

```bash
# Full UI smoke (network-free launch/onboarding check) + the live-data test:
xcodebuild test -project LSM.xcodeproj -scheme LSM -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:LSMUITests
```

## Gotchas

- **Device launch fails while the phone is locked.** `devicectl ... process
  launch` returns `FBSOpenApplicationErrorDomain error 7 (Locked)` — the app
  *installs* fine, but won't launch until the phone is unlocked. Always unlock
  Andy H before `drive.sh device`.
- **`simctl` cannot tap.** Launching only proves the entrypoint resolves. Real
  navigation must go through XCUITest (that's why the driver runs a UI test, not
  just `simctl launch`).
- **Don't use AppleScript to click the Simulator** — it needs Accessibility
  permission that isn't granted here, and it's the wrong tool anyway. XCUITest is
  the supported driver.
- **`-uitests` keeps the network live.** It only suppresses ad/consent bootstrap
  (ATT/UMP) so dialogs don't make the run flaky. The live-data test relies on the
  Worker fetch still happening.
- **Standings show P/W/D/L = 0.** Correct as of 2026-06 — the shards hold a frozen
  preseason 2025/26 copy. Team names + fixture dates rendering is the real signal,
  not the numbers.
- **SwiftLint runs every build** (a "will be run during every build" note) — cosmetic.
- **Background SourceKit may flag `No such module 'XCTest'`** in
  `LSMUITests/*.swift`. False positive from the indexer; it compiles fine under
  `xcodebuild test`.

## Troubleshooting

- **`Unable to find a device matching ... iPhone 17`** — `xcrun simctl list
  devices available | grep iPhone` and set `LSM_SIM_NAME` to one that exists.
- **Device not found / "unavailable"** — `xcrun devicectl list devices`; the
  iPhone must show `available (paired)`. Re-pair via Xcode if not, then update
  `LSM_DEVICE_ID`.
- **Screenshots not exported** — the result bundle path differs across Xcode
  versions; the driver tries both `$RESULTS` and `$RESULTS.xcresult`. Inspect
  with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`.
