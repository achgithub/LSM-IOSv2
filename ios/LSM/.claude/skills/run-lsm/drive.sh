#!/usr/bin/env bash
# Build, launch, and drive the LSM iOS app — on the Simulator or on Andrew's
# iPhone. macOS-only (the iOS Simulator and on-device install require it).
#
# Usage:
#   drive.sh sim     [--no-test]   # boot sim, build, install, launch
#                                  # then run the live-data UI test + export screenshots
#   drive.sh device  [--no-test]   # build for device, install + launch via devicectl
#
# All paths below are relative to the app unit: ios/LSM/ . Run from there:
#   ./.claude/skills/run-lsm/drive.sh sim
#
# Output (build products + screenshots) lands under OUT (a scratch dir), never
# in the repo.
set -euo pipefail

TARGET="${1:-sim}"
RUN_TEST=1
[[ "${2:-}" == "--no-test" ]] && RUN_TEST=0

# --- knobs -------------------------------------------------------------------
SIM_NAME="${LSM_SIM_NAME:-iPhone 17}"
# Andrew's iPhone ("Andy H", iPhone 16). `xcrun devicectl list devices` to refresh.
DEVICE_ID="${LSM_DEVICE_ID:-E2185E12-6C9D-5CB4-9B82-DB42ED82C68E}"
BUNDLE_ID="com.sportsmanager.LMS"
OUT="${LSM_OUT:-${TMPDIR:-/tmp}/lsm-run}"
mkdir -p "$OUT/shots"

PROJ="LSM.xcodeproj"
SCHEME="LSM"

case "$TARGET" in
  sim)
    DEST="platform=iOS Simulator,name=$SIM_NAME"
    DD="$OUT/DerivedData-Sim"
    ;;
  device)
    DEST="id=$DEVICE_ID"
    DD="$OUT/DerivedData-Device"
    ;;
  *) echo "usage: drive.sh [sim|device] [--no-test]" >&2; exit 2 ;;
esac

echo "==> target=$TARGET  dest='$DEST'"

if [[ "$TARGET" == "sim" ]]; then
  # Boot is idempotent — swallow the 'already booted' error.
  xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
  open -a Simulator || true
fi

echo "==> building"
xcodebuild build \
  -project "$PROJ" -scheme "$SCHEME" -configuration Debug \
  -destination "$DEST" -derivedDataPath "$DD" \
  ${TARGET:+$([[ "$TARGET" == device ]] && echo -allowProvisioningUpdates)} \
  | tail -3

if [[ "$TARGET" == "sim" ]]; then
  APP="$DD/Build/Products/Debug-iphonesimulator/$SCHEME.app"
  echo "==> install + launch (simulator)"
  xcrun simctl install "$SIM_NAME" "$APP"
  xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID"
else
  APP="$DD/Build/Products/Debug-iphoneos/$SCHEME.app"
  echo "==> install + launch (device — UNLOCK THE PHONE FIRST)"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP" | tail -3
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" | tail -3
fi

if [[ "$RUN_TEST" == "1" ]]; then
  echo "==> driving the app: live-data UI test (Standings + Matches from the v2 Workers)"
  RESULTS="$OUT/TestResults"
  rm -rf "$RESULTS"
  xcodebuild test \
    -project "$PROJ" -scheme "$SCHEME" -configuration Debug \
    -destination "$DEST" -derivedDataPath "$DD" \
    ${TARGET:+$([[ "$TARGET" == device ]] && echo -allowProvisioningUpdates)} \
    -only-testing:LSMUITests/LMSSmokeUITests/testLeaguesLoadFromV2Workers \
    -resultBundlePath "$RESULTS" | tail -5

  echo "==> exporting screenshots to $OUT/shots"
  rm -rf "$OUT/shots"; mkdir -p "$OUT/shots"
  xcrun xcresulttool export attachments --path "$RESULTS" --output-path "$OUT/shots" >/dev/null 2>&1 || \
    xcrun xcresulttool export attachments --path "$RESULTS.xcresult" --output-path "$OUT/shots" >/dev/null 2>&1
  ls "$OUT/shots"/*.png 2>/dev/null && echo "screenshots above (Standings / Matches)"
fi

echo "==> done"
