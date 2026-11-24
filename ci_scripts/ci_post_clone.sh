#!/bin/bash
# ci_post_clone.sh — Xcode Cloud clone hook: rebrand + shim patch + Info.plist
# injection, mirroring the GHA ci-build.yml prep so an Xcode Cloud archive
# produces the same Blount Phone artifact.
# Env: PBX_SHIM_URL (default LAN shim), PBX_SHIM_TOKEN (set as a secret env
# var on the workflow in ASC/Xcode — unset => token registration + beacons
# disabled for this build).
set -e
cd "$CI_WORKSPACE"

bash phone-app/rebrand.sh "$CI_WORKSPACE"
git apply --verbose phone-app/corecontext-shim.patch

SHIM_URL="${PBX_SHIM_URL:-http://192.168.200.158:8777}"
/usr/libexec/PlistBuddy -c "Set :PBX_SHIM_URL $SHIM_URL" Linphone/Info.plist
if [ -n "${PBX_SHIM_TOKEN:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :PBX_SHIM_TOKEN $PBX_SHIM_TOKEN" Linphone/Info.plist
fi
echo "ci_post_clone: rebrand+patch applied, PBX_SHIM_URL=$SHIM_URL token=${PBX_SHIM_TOKEN:+set}"
