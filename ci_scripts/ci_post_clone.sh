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

# PBX_SHIM_* are xcconfig build settings — rebrand.sh appended the keys to
# Shared.xcconfig (URL baked via the :/$()/ idiom, token deliberately blank).
# Inject the token the same way GHA does — a build setting, never a
# committed literal.
if [ -n "${PBX_SHIM_TOKEN:-}" ]; then
  /usr/bin/sed -i '' "s|^PBX_SHIM_TOKEN =.*|PBX_SHIM_TOKEN = $PBX_SHIM_TOKEN|" "$REPO_ROOT/Shared.xcconfig"
fi
echo "ci_post_clone: rebrand+patch applied, token=${PBX_SHIM_TOKEN:+set}"
