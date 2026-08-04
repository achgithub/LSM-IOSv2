#!/bin/bash
# Archives LSM (Release) and uploads it to App Store Connect/TestFlight.
# Adapted from Clubroom2's scripts/testflight-deploy.sh.
#
# Bumps CURRENT_PROJECT_VERSION (Debug + Release, LSM app target only —
# LSMTests/LSMUITests keep their own separate build number) unless --no-bump
# is passed. The bump is scoped to the buildSettings block that also contains
# `PRODUCT_BUNDLE_IDENTIFIER = com.sportsmanager.LMS;` (exact match — the
# Tests/UITests targets use suffixed bundle ids), so it can't drift onto the
# wrong target even if the .pbxproj is reordered later.
#
# Auth: App Store Connect API key (Apple's recommended non-interactive
# method — no Apple ID/app-specific-password prompts). One-time setup:
#   1. App Store Connect > Users and Access > Integrations > App Store
#      Connect API > generate a key with the "App Manager" role.
#   2. Download the .p8 once (Apple only lets you download it once) to
#      ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   3. export APP_STORE_CONNECT_API_KEY_ID=<the Key ID>
#      export APP_STORE_CONNECT_API_ISSUER_ID=<the Issuer ID, same for all keys>
#      (put these in your shell profile so every future run just works)
#   Defaults below fall back to this project's known key/issuer if the env
#   vars aren't set, so a bare run still works on this machine.
#
# Usage:
#   scripts/testflight-deploy.sh                     # bump build, archive, upload
#   scripts/testflight-deploy.sh --no-bump            # reuse current build number
#   scripts/testflight-deploy.sh --build-number 70     # set an explicit number
#   scripts/testflight-deploy.sh --no-upload           # archive + export only, skip upload
#   scripts/testflight-deploy.sh --no-push             # bump locally, don't commit/push
#
# Run from anywhere — the script cd's to ios/LSM itself.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJ="LSM.xcodeproj"
PBXPROJ="$PROJ/project.pbxproj"
SCHEME="LSM"
EXPORT_OPTIONS="ExportOptions.plist"
BUILD_DIR=".build/testflight"
ARCHIVE_PATH="$BUILD_DIR/LSM.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_BUNDLE_ID="com.sportsmanager.LMS"

BUMP=true
EXPLICIT_BUILD_NUMBER=""
DO_UPLOAD=true
DO_PUSH=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-bump) BUMP=false; shift ;;
    --build-number) EXPLICIT_BUILD_NUMBER="${2:?--build-number requires a value}"; shift 2 ;;
    --build-number=*) EXPLICIT_BUILD_NUMBER="${1#*=}"; shift ;;
    --no-upload) DO_UPLOAD=false; shift ;;
    --no-push) DO_PUSH=false; shift ;;
    *) echo "error: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

API_KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-K47UYBTP48}"
API_ISSUER_ID="${APP_STORE_CONNECT_API_ISSUER_ID:-69a6de75-5358-47e3-e053-5b8c7c11a4d1}"

if [[ "$DO_UPLOAD" == true ]]; then
  KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"
  if [[ ! -f "$KEY_FILE" ]]; then
    echo "error: API key file not found at $KEY_FILE" >&2
    echo "       Re-run with --no-upload to just archive+export without uploading." >&2
    exit 1
  fi
fi

echo "==> Checking working tree"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has uncommitted changes — commit or stash first." >&2
  git status --short
  exit 1
fi

# Read the current build number straight from the app target (not just the
# first CURRENT_PROJECT_VERSION line in the file — LSMTests/LSMUITests have
# their own, unrelated counter that happens to sort earlier in the file).
CURRENT_VERSION="$(xcodebuild -showBuildSettings -project "$PROJ" -scheme "$SCHEME" -configuration Release 2>/dev/null \
  | grep -m1 'CURRENT_PROJECT_VERSION =' | awk '{print $3}')"
if [[ -z "$CURRENT_VERSION" ]]; then
  echo "error: couldn't read the current CURRENT_PROJECT_VERSION for scheme $SCHEME." >&2
  exit 1
fi

if [[ -n "$EXPLICIT_BUILD_NUMBER" ]]; then
  NEW_VERSION="$EXPLICIT_BUILD_NUMBER"
elif [[ "$BUMP" == true ]]; then
  NEW_VERSION=$((CURRENT_VERSION + 1))
else
  NEW_VERSION="$CURRENT_VERSION"
fi

if [[ "$NEW_VERSION" != "$CURRENT_VERSION" ]]; then
  echo "==> Bumping CURRENT_PROJECT_VERSION $CURRENT_VERSION -> $NEW_VERSION (LSM app target only)"
  awk -v new="$NEW_VERSION" -v bundle="$APP_BUNDLE_ID" '
    /buildSettings = \{/ { inBlock=1; buf="" }
    inBlock { buf = buf $0 "\n" }
    inBlock && /\};[ \t]*$/ {
      inBlock=0
      if (buf ~ ("PRODUCT_BUNDLE_IDENTIFIER = " bundle ";")) {
        gsub(/CURRENT_PROJECT_VERSION = [0-9]+;/, "CURRENT_PROJECT_VERSION = " new ";", buf)
      }
      printf "%s", buf
      next
    }
    !inBlock { print }
  ' "$PBXPROJ" > "$PBXPROJ.tmp"
  mv "$PBXPROJ.tmp" "$PBXPROJ"

  BUMPED_COUNT="$(grep -c "CURRENT_PROJECT_VERSION = $NEW_VERSION;" "$PBXPROJ" || true)"
  if [[ "$BUMPED_COUNT" -lt 2 ]]; then
    echo "error: expected 2 build configs (Debug+Release) at CURRENT_PROJECT_VERSION = $NEW_VERSION, found $BUMPED_COUNT — check $PBXPROJ before retrying." >&2
    exit 1
  fi

  git add "$PBXPROJ"
  git commit -m "Bump build number for TestFlight upload

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
  if [[ "$DO_PUSH" == true ]]; then
    echo "==> Pushing build bump"
    git push origin "$(git branch --show-current)"
  fi
else
  echo "==> Using existing build number $CURRENT_VERSION"
fi

echo "==> Archiving (Release, build $NEW_VERSION)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
if command -v xcbeautify >/dev/null 2>&1; then
  set -o pipefail
  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    | xcbeautify
else
  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates
fi

if [[ "$DO_UPLOAD" == true ]]; then
  echo "==> Exporting + uploading to App Store Connect"
  # Reuses ExportOptions.plist (method: app-store-connect) but overrides
  # destination to "upload" so exportArchive uploads directly instead of
  # just producing an .ipa — the API key auth flags below are what let this
  # run non-interactively (no Xcode sign-in / 2FA prompt).
  UPLOAD_OPTIONS="$BUILD_DIR/ExportOptionsUpload.plist"
  /usr/libexec/PlistBuddy -c "Print" "$EXPORT_OPTIONS" > /dev/null # sanity-check it parses
  cp "$EXPORT_OPTIONS" "$UPLOAD_OPTIONS"
  /usr/libexec/PlistBuddy -c "Set :destination upload" "$UPLOAD_OPTIONS"

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$UPLOAD_OPTIONS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_FILE" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER_ID"

  echo "==> Uploaded build $NEW_VERSION to App Store Connect. It'll appear in TestFlight once Apple finishes processing."
else
  echo "==> Exporting (no upload)"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates
  echo "==> Exported to $EXPORT_PATH — upload it yourself via Xcode Organizer or Transporter."
fi
