#!/bin/bash
# ci_post_clone.sh — Xcode Cloud clone hook: rebrand + shim patch + xcconfig
# token injection, mirroring the GHA ci-build.yml prep so an Xcode Cloud
# archive produces the same Blount Phone artifact.
# Env: PBX_SHIM_TOKEN (secret env var on the workflow — unset => token
# registration + beacons disabled for this build). Repo root is located via
# this script's own path — Xcode Cloud cd's into ci_scripts/ and CI_WORKSPACE
# is not the repository root on the current image (/Volumes/workspace).
set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

bash "$REPO_ROOT/phone-app/rebrand.sh" "$REPO_ROOT"
git apply --verbose "$REPO_ROOT/phone-app/corecontext-shim.patch"

# usernotifications.filtering is a restricted entitlement — Xcode managed
# signing cannot enable it on the App ID (DVTPortalAppIDErrorDomain 5) and
# aborts the whole signing pass. The shipped GHA profile never embedded it,
# so dropping it here produces a functionally identical artifact.
/usr/libexec/PlistBuddy -c \
  "Delete :com.apple.developer.usernotifications.filtering" \
  "$REPO_ROOT/msgNotificationService/msgNotificationService.entitlements" || true

# PBX_SHIM_* are xcconfig build settings — rebrand.sh appended the keys to
# Shared.xcconfig (URL baked via the :/$()/ idiom, token deliberately blank).
# Inject the token the same way GHA does — a build setting, never a
# committed literal.
if [ -n "${PBX_SHIM_TOKEN:-}" ]; then
  /usr/bin/sed -i '' "s|^PBX_SHIM_TOKEN =.*|PBX_SHIM_TOKEN = $PBX_SHIM_TOKEN|" "$REPO_ROOT/Shared.xcconfig"
fi
echo "ci_post_clone: rebrand+patch applied, token=${PBX_SHIM_TOKEN:+set}"
