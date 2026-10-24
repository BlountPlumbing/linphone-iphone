#!/usr/bin/env bash
# rebrand.sh — Blount Phone rebrand of a linphone-iphone release/6.2 checkout.
#
# Usage:  ./rebrand.sh /path/to/linphone-iphone        (idempotent — safe to re-run)
#
# Env knobs:
#   TEAM_ID          default S77XPPF572
#   APS_ENVIRONMENT  default production  (use "development" for dev-signed builds;
#                    must match webhookd use_sandbox for pushes to arrive)
#   PBX_SHIM_URL     default http://192.168.200.158:8777 (pbx-wazo-01 over tailnet
#                    subnet route; plain HTTP — NSAllowsLocalNetworking is added
#                    by corecontext-shim.patch)
#
# What it does (details + evidence in PREP-NOTES.md):
#   * bundle IDs      org.linphone.phone[.*]      -> net.blount.phone[.*]
#                     org.linphone.LinphoneApp*   -> net.blount.LinphoneApp*
#   * app groups      group.org.linphone.phone.*, group.belledonne-communications.linphone
#                     -> group.net.blount.phone (single shared group)
#   * keychain group  $(AppIdentifierPrefix)org.linphone.phone -> $(AppIdentifierPrefix)net.blount.phone
#   * display name    Linphone -> "Blount Phone" (main target only)
#   * DEVELOPMENT_TEAM Z2V957B3D6 -> $TEAM_ID
#   * aps-environment development -> $APS_ENVIRONMENT
#   * strips -DUSE_CRASHLYTICS (keeps Belledonne's Firebase out of our binary)
#   * SPM: gitlab.linphone.org -> github.com mirror, pin exactVersion 5.5.36
#   * misc org.linphone leftovers (SSO redirect, intent activityType,
#     CFBundleURLName, GoogleService BUNDLE_IDs, run-mdm-tests.sh)
#   * appends PBX_SHIM_URL / PBX_SHIM_TOKEN build settings to Shared.xcconfig
#     (token stays EMPTY in source — CI injects via `xcodebuild PBX_SHIM_TOKEN=...`)
#   * ends with a loud grep verify pass on leftover identifier patterns

set -euo pipefail

ROOT="${1:?usage: rebrand.sh <linphone-iphone checkout path>}"
TEAM_ID="${TEAM_ID:-S77XPPF572}"
APS_ENV="${APS_ENVIRONMENT:-production}"
SHIM_URL="${PBX_SHIM_URL:-http://192.168.200.158:8777}"
SDK_REV_VERSION="5.5.36"   # matches checked-in Package.resolved pin (rev 06a666b8)

PBXPROJ="$ROOT/LinphoneApp.xcodeproj/project.pbxproj"
XCCONFIG="$ROOT/Shared.xcconfig"

[ -f "$PBXPROJ" ] || { echo "FATAL: $PBXPROJ not found — is $ROOT a linphone-iphone checkout?"; exit 1; }
[ -f "$XCCONFIG" ] || { echo "FATAL: $XCCONFIG not found"; exit 1; }

echo "== rebrand.sh: root=$ROOT team=$TEAM_ID aps=$APS_ENV =="

# perl -pi is BSD/GNU-safe; -0777 used where a multiline collapse is needed.
ed() { perl -pi -e "$2" "$1"; }

# --- 1. project.pbxproj -------------------------------------------------------
ed "$PBXPROJ" 's/\borg\.linphone\.phone\b/net.blount.phone/g'          # app + 3 ext IDs
ed "$PBXPROJ" 's/\borg\.linphone\.LinphoneApp/net.blount.LinphoneApp/g' # test targets (Tests/UITests)
ed "$PBXPROJ" 's/\bZ2V957B3D6\b/'"$TEAM_ID"'/g'                          # DEVELOPMENT_TEAM
ed "$PBXPROJ" 's/INFOPLIST_KEY_CFBundleDisplayName = Linphone;/INFOPLIST_KEY_CFBundleDisplayName = "Blount Phone";/g'

# strip Firebase/crashlytics compile flags (all Firebase code is #if USE_CRASHLYTICS)
ed "$PBXPROJ" 's/^[ \t]*"USE_CRASHLYTICS=1",\n//mg'
ed "$PBXPROJ" 's/ -DUSE_CRASHLYTICS//g'

# Force Apple Distribution signing on Release configs of the app targets ONLY.
# Needed because (a) the team may have zero registered devices -> development
# profile resolution fails, and (b) export to TestFlight wants distribution
# anyway. Scoped to `name = Release` blocks inside this file's
# XCBuildConfiguration entries — SPM package targets live in generated
# projects and are untouched. Idempotent.
perl -0777 -pi -e '
	# normalize any existing CODE_SIGN_IDENTITY inside Release blocks
	s/(buildSettings = \{[^}]*?CODE_SIGN_IDENTITY = ")[^"]*("[^}]*?\n\t+\};\n\t+name = Release;)/${1}Apple Distribution${2}/g;
	# inject into Release blocks that have no CODE_SIGN_IDENTITY at all
	s/(buildSettings = \{(?:(?!CODE_SIGN_IDENTITY)[^}])*?)(\n\t+\};\n\t+name = Release;)/$1\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";$2/g;
' "$PBXPROJ"

# SPM: repoint gitlab -> github mirror; pin BOTH linphone-sdk refs to exactVersion
ed "$PBXPROJ" 's|https://gitlab\.linphone\.org/BC/public/linphone-sdk-swift-ios\.git|https://github.com/BelledonneCommunications/linphone-sdk-swift-ios.git|g'
# collapse the two linphone-sdk requirement styles onto one exact pin
perl -0777 -pi -e '
	s/(XCRemoteSwiftPackageReference "linphone-sdk-swift-ios" \*\/ = \{\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "https:\/\/github\.com\/BelledonneCommunications\/linphone-sdk-swift-ios\.git";\n\t\t\trequirement = \{\n)\t\t\t\t(?:branch = stable;\n\t\t\t\tkind = branch;|kind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = [0-9.]+;)/$1\t\t\t\tkind = exactVersion;\n\t\t\t\tversion = '"$SDK_REV_VERSION"';/g
' "$PBXPROJ"

# --- 2. Shared.xcconfig -------------------------------------------------------
ed "$XCCONFIG" 's/^APP_GROUP_NAME = .*$/APP_GROUP_NAME = group.net.blount.phone/'
# PBX_SHIM_URL uses the http:/$()/ idiom because // starts an xcconfig comment.
if ! grep -q '^PBX_SHIM_URL' "$XCCONFIG"; then
	printf '\n// Blount Phone — pbx-push-shim endpoint (task A5). Token is injected by\n// CI via `xcodebuild PBX_SHIM_TOKEN=...`; never commit a real token here.\nPBX_SHIM_URL = %s\nPBX_SHIM_TOKEN = \n' \
		"$(echo "$SHIM_URL" | sed 's|://|:/$()/|')" >> "$XCCONFIG"
fi

# --- 3. entitlements ----------------------------------------------------------
for ENT in "$ROOT/Linphone/Linphone.entitlements" \
           "$ROOT/msgNotificationService/msgNotificationService.entitlements" \
           "$ROOT/linphoneExtension/linphoneExtension.entitlements"; do
	[ -f "$ENT" ] || continue
	ed "$ENT" 's/group\.(org\.linphone\.phone\.[A-Za-z]+|belledonne-communications\.linphone)/group.net.blount.phone/g'
	ed "$ENT" 's/\$\(AppIdentifierPrefix\)org\.linphone\.phone/\$\(AppIdentifierPrefix\)net.blount.phone/g'
	ed "$ENT" 's|<key>aps-environment</key>\s*\n\s*<string>[^<]*</string>|<key>aps-environment</key>\n\t<string>'"$APS_ENV"'</string>|g' 2>/dev/null || true
done
# collapse the now-duplicated app-group array in the main app entitlements
perl -0777 -pi -e 's|<key>com\.apple\.security\.application-groups</key>\s*\n\t*<array>\s*\n(\t*<string>group\.net\.blount\.phone</string>\s*\n)+(\t*</array>)|<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>group.net.blount.phone</string>\n\t</array>|g' \
	"$ROOT/Linphone/Linphone.entitlements"
# aps-environment: both keys (aps-environment + com.apple.developer.aps-environment)
perl -0777 -pi -e 's|(<key>(?:com\.apple\.developer\.)?aps-environment</key>\s*\n\s*<string>)[^<]*(</string>)|$1'"$APS_ENV"'$2|g' \
	"$ROOT/Linphone/Linphone.entitlements"

# --- 4. plists ----------------------------------------------------------------
ed "$ROOT/Linphone/Info.plist" 's|\borg\.linphone\.phone\b|net.blount.phone|g'   # CFBundleURLName x12
ed "$ROOT/Linphone/Info.plist" 's|<string>org\.linphone</string>|<string>net.blount</string>|g' # org.linphone:// URL scheme
for GS in "$ROOT/GoogleService-Info.plist" "$ROOT/msgNotificationService/GoogleService-Info.plist"; do
	[ -f "$GS" ] && ed "$GS" 's|\borg\.linphone\.phone\b|net.blount.phone|g'
done
# AppIntentVocabulary examples (all lproj variants)
find "$ROOT" -name AppIntentVocabulary.plist -exec perl -pi -e 's/\bLinphone\b/Blount Phone/g' {} +

# --- 5. swift sources ---------------------------------------------------------
[ -f "$ROOT/linphoneExtension/ShareViewController.swift" ] && \
	ed "$ROOT/linphoneExtension/ShareViewController.swift" \
	   's/group\.org\.linphone\.phone\.linphoneExtension/group.net.blount.phone/g'
[ -f "$ROOT/intentsExtension/IntentHandler.swift" ] && \
	ed "$ROOT/intentsExtension/IntentHandler.swift" \
	   's/\borg\.linphone\.startCall\b/net.blount.phone.startCall/g'
[ -f "$ROOT/Linphone/Utils/SingleSignOn/SingleSignOnManager.swift" ] && \
	ed "$ROOT/Linphone/Utils/SingleSignOn/SingleSignOnManager.swift" \
	   's|\borg\.linphone:/openidcallback\b|net.blount.phone:/openidcallback|g'

# --- 6. misc scripts ----------------------------------------------------------
[ -f "$ROOT/scripts/run-mdm-tests.sh" ] && \
	ed "$ROOT/scripts/run-mdm-tests.sh" \
	   's/\borg\.linphone\.phone\b/net.blount.phone/g; s/group\.org\.linphone\.phone\.[A-Za-z]+/group.net.blount.phone/g'

# --- 6b. app icon (Closes the PREP-NOTES "manual leftover") ------------------
# If phone-app/AppIcon-1024.png rides next to this script, drop it in as the
# app icon (upstream slot is a single 1024x1024.png — see Contents.json).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_DST="$ROOT/Linphone/Assets.xcassets/AppIcon.appiconset/1024x1024.png"
if [ -f "$SCRIPT_DIR/AppIcon-1024.png" ] && [ -d "$(dirname "$ICON_DST")" ]; then
	cp "$SCRIPT_DIR/AppIcon-1024.png" "$ICON_DST"
	echo "== app icon replaced from phone-app/AppIcon-1024.png =="
fi

# --- 7. verify pass — fail loudly on leftovers --------------------------------
echo "== verify pass =="
FAIL=0
# org.linphone bundle-id pattern anywhere outside .git (sip.linphone.org / doc
# URLs / the gitlab path we just rewrote are not org.linphone and won't match).
# phone-app/ excluded — it legitimately documents the OLD identifiers.
if grep -rn 'org\.linphone' "$ROOT" --exclude-dir=.git --exclude-dir=phone-app ; then
	echo "FAIL: leftover org.linphone identifiers above"; FAIL=1
fi
if grep -rn 'belledonne-communications\.linphone\|Z2V957B3D6' "$ROOT" --exclude-dir=.git --exclude-dir=phone-app --exclude-dir=Documentation ; then
	echo "FAIL: leftover belledonne group / team id above"; FAIL=1
fi
if grep -rn 'gitlab\.linphone\.org' "$PBXPROJ" ; then
	echo "FAIL: gitlab SDK endpoint still in pbxproj"; FAIL=1
fi
if grep -rn 'USE_CRASHLYTICS' "$PBXPROJ" ; then
	echo "FAIL: USE_CRASHLYTICS still in pbxproj"; FAIL=1
fi
if grep -rn 'linphone\.android\|com\.linphone\.|org\.linphone\.' "$ROOT" --exclude-dir=.git --include='*.entitlements' --include='*.plist' --include='*.pbxproj' ; then
	echo "FAIL: foreign-style bundle identifiers above"; FAIL=1
fi
# positive assertions — the renames must actually be present
for EXPECT in \
	'PRODUCT_BUNDLE_IDENTIFIER = net.blount.phone;' \
	'PRODUCT_BUNDLE_IDENTIFIER = net.blount.phone.msgNotificationService;' \
	'PRODUCT_BUNDLE_IDENTIFIER = net.blount.phone.linphoneExtension;' \
	'PRODUCT_BUNDLE_IDENTIFIER = net.blount.phone.intentsExtension;' \
	'"Blount Phone"'; do
	grep -qF "$EXPECT" "$PBXPROJ" || { echo "FAIL: expected '$EXPECT' missing from project.pbxproj"; FAIL=1; }
done
grep -q '^APP_GROUP_NAME = group.net.blount.phone' "$XCCONFIG" || { echo "FAIL: APP_GROUP_NAME not rebranded"; FAIL=1; }
grep -q 'group.net.blount.phone' "$ROOT/Linphone/Linphone.entitlements" || { echo "FAIL: app entitlements group missing"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "== rebrand.sh: ALL CHECKS PASSED ==" || { echo "== rebrand.sh: FAILED — see above =="; exit 1; }
