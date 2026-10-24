# Blount Phone — A5 Prep Notes (verified against real checkout 2026-10-24)

Checkout verified: `git clone --depth 1 --branch release/6.2 https://github.com/BelledonneCommunications/linphone-iphone.git /tmp/linphone-iphone-6.2`
- `release/6.2` **exists** — used directly, no fallback needed.
- HEAD = `694f17def8d137f376bdfefd0560a785ea7989dd` — "Updated CHANGELOG & bumped version code to 6.2.4" (Thu Oct 22 16:13:25 2026 +0200).
- `MARKETING_VERSION = 6.2.4`, `CURRENT_PROJECT_VERSION = 1`, `IPHONEOS_DEPLOYMENT_TARGET = 15.0`, scheme `LastUpgradeVersion = "1500"` (Xcode 15).

## A1 claim verification — CONFIRMED / CORRECTED

| # | A1 claim | Verdict | Evidence |
|---|----------|---------|----------|
| 1 | Base branch `release/6.2` (not 6.0) | **CONFIRMED** | Branch exists; `Linphone/TelecomManager/EarlyPushkitDelegate.swift` (PKPushRegistryDelegate for pre-core push cover) + `MDMManager` (`Linphone/Core/CoreContext.swift:71-103`, `observeMDMNotifications`) both present. |
| 2 | Xcode project = `LinphoneApp.xcodeproj` | **CONFIRMED** | `LinphoneApp.xcodeproj/` at repo root; `README.md:67` still says `linphone.xcodeproj` (stale) — but `README.md:248` uses `xcodebuild test -project LinphoneApp.xcodeproj -scheme LinphoneAppTests`. **Main scheme is `Linphone`** (`LinphoneApp.xcodeproj/xcshareddata/xcschemes/Linphone.xcscheme` → builds target `LinphoneApp` → `LinphoneApp.app`). GitLab CI vars confirm: `archive_scheme: Linphone`, `archive_path: Linphone.xcarchive` (`.gitlab-ci.yml`). |
| 3 | iOS ≥15, Xcode ≥15 | **CONFIRMED** | `IPHONEOS_DEPLOYMENT_TARGET = 15.0` (project.pbxproj); `LastUpgradeVersion = "1500"`. |
| 4 | SDK via SPM `XCRemoteSwiftPackageReference`; CI must use GitHub mirror pinned | **CONFIRMED + DETAIL** | **TWO** `XCRemoteSwiftPackageReference` blocks for `linphone-sdk-swift-ios` exist in `project.pbxproj`: `C618BF54` → `gitlab.linphone.org/BC/public/linphone-sdk-swift-ios.git` `kind=branch, branch=stable` (line 2581-2588) — **this is the one the `linphonesw` `XCSwiftPackageProductDependency` entries point at** (lines 2624-2632) — and `D7DCBDD9` → `github.com/BelledonneCommunications/linphone-sdk-swift-ios.git` `upToNextMajorVersion 5.5.13` (line 2605-2612) which is in the project's `packageReferences` list (line 1487). `LinphoneApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` already pins `linphone-sdk-swift-ios` → **github mirror, version 5.5.36, rev `06a666b86050851328dbf382f78a09591d973a7e`**. `rebrand.sh` repoints the gitlab URL to github and pins both refs to `exactVersion 5.5.36` — deterministic, matches Package.resolved. |
| 5 | No app-side PKPushRegistry — liblinphone IOSPlatformHelpers owns it | **CORRECTED** | There IS an app-side `PKPushRegistry`: `Linphone/LinphoneApp.swift:159` `private let voipRegistry = PKPushRegistry(queue: coreQueue)`, wired to `EarlyPushkitDelegate` **only when `!configAvailable`** (lines 165-168) — pre-core cover for voip pushes arriving before first-launch config exists; its `pushRegistry(didUpdate:)` **discards credentials** (`EarlyPushkitDelegate.swift:37-39` "ignoring until core is ready"). Once `CoreContext.shared` initializes, the SDK's `IOSPlatformHelpers` owns push registration (confirmed: no other `didUpdate` consumer; `mCore.pushNotificationEnabled = true` at `CoreContext.swift:191`). So: app-side registry exists but is intentionally inert for tokens after config loads — **the token must be read back from linphonesw's `PushNotificationConfig`, which is exactly what the patch does.** |
| 6 | SDK builds `pn-param`/`pn-prid` from bundle ID | **CONFIRMED (API surface)** | `PushNotificationConfig` (linphonesw 5.5.36, `Sources/linphonesw/LinphoneWrapper.swift:41602+`) exposes `bundleIdentifier`, `teamId`, `param`, `prid`, `provider`, `remoteToken`, `voipToken` — the SDK fills these itself. With `PRODUCT_BUNDLE_IDENTIFIER = net.blount.phone` the SDK emits `pn-param=S77XPPF572.net.blount.phone.voip&remote` and `pn-prid=<voip-tok>:voip&<remote-tok>:remote` with zero patch. |
| 7 | Token→shim seam = CoreContext.swift, read `account.params.pushNotificationConfig.prid`, split `:voip` | **CONFIRMED with BETTER API** | Both `AccountParams.pushNotificationConfig` (`LinphoneWrapper.swift:8922`) and `Core.pushNotificationConfig` (`:25861`) exist. **`voipToken` is the raw 64-hex token directly** — no `:voip` split needed; patch reads `account.params?.pushNotificationConfig?.voipToken ?? core.pushNotificationConfig?.voipToken` with a `prid` `:voip`-split fallback for older behavior. Insertion point = `onAccountRegistrationStateChanged` `.Ok` case (CoreContext.swift:408-424) — fires on every successful REGISTER (incl. refresh + re-login), self-healing; retry loop covers PushKit credential lag. `coreQueue` used by the patch is the linphonesw-exported global (`LinphoneWrapper.swift:1027`), already in scope. |
| 8 | CallKit in `Linphone/TelecomManager/` | **CONFIRMED** | `TelecomManager.swift`, `ProviderDelegate.swift` (`CXProvider.reportNewIncomingCall` line 113, `PushIncomingReceived` handling line 118), `EarlyPushkitDelegate.swift`. |
| 9 | Extension targets: msgNotificationService, intentsExtension, linphoneExtension | **CONFIRMED** | PBXNativeTargets at pbxproj lines 1306/1395/1417; bundle IDs at 1958/2001 (`org.linphone.phone.msgNotificationService`), 2395/2429 (`org.linphone.phone.linphoneExtension`), 2462/2498 (`org.linphone.phone.intentsExtension`). Test targets `org.linphone.LinphoneAppTests`/`org.linphone.LinphoneAppUITests` at 2027/2055/2084/2113. `intentsExtension` has **no .entitlements file** (only Info.plist). |
| 10 | App group in Shared.xcconfig | **CONFIRMED + MORE** | `Shared.xcconfig` (sole content): `APP_GROUP_NAME = group.org.linphone.phone.msgNotification` — consumed via `$(APP_GROUP_NAME)` in `Linphone/Info.plist`, `msgNotificationService/Info.plist`; read at runtime by `SharedMainViewModel.appGroupName` (SharedMainViewModel.swift:27), `FileUtil.appGroupName` (FileUtils.swift:26), `Log.swift:38`, `NotificationService.swift:30`. **But entitlements carry THREE groups** in `Linphone/Linphone.entitlements`: `group.belledonne-communications.linphone`, `group.org.linphone.phone.linphoneExtension`, `group.org.linphone.phone.msgNotification`; plus `group.org.linphone.phone.msgNotification` in msgNotificationService.entitlements and `group.org.linphone.phone.linphoneExtension` in linphoneExtension.entitlements; **plus a hardcoded `group.org.linphone.phone.linphoneExtension` in `linphoneExtension/ShareViewController.swift:140`**; plus `$(AppIdentifierPrefix)org.linphone.phone` keychain-access-groups in 2 entitlements. |
| 11 | Display name via plist | **CORRECTED location** | `INFOPLIST_KEY_CFBundleDisplayName = Linphone;` in pbxproj build settings (lines 2269, 2331 — Debug+Release of LinphoneApp target) — generated Info.plist key, not in the static `Info.plist`. Extensions' display names = their target names (1946/1989/2385/2419/2452/2488). |
| 12 | AppIcon.appiconset | **CONFIRMED** | `Linphone/Assets.xcassets/AppIcon.appiconset/Contents.json` — single iOS image `1024x1024.png` (universal/1024) + 10 mac slots w/o filenames. Icon replacement = drop a new `1024x1024.png`. `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. |

## Additional findings (not in A1)

- **`USE_CRASHLYTICS=1` is compiled in** — `GCC_PREPROCESSOR_DEFINITIONS` + `OTHER_SWIFT_FLAGS = "-DUSE_CRASHLYTICS"` on the app target (pbxproj 2265/2299, 2327/2361) and msgNotificationService (1942/1957, 1985/2000). `GoogleService-Info.plist` (root + msgNotificationService) carry Belledonne's Firebase `BUNDLE_ID`/`API_KEY`. Fork should NOT phone home to Belledonne's Firebase project → `rebrand.sh` strips `-DUSE_CRASHLYTICS` (all Firebase code is `#if USE_CRASHLYTICS`-guarded) and neutralizes the plist BUNDLE_IDs. Firebase SPM refs left in place (unused, harmless).
- **`DEVELOPMENT_TEAM = Z2V957B3D6`** (Belledonne) in every build config (11×) → `S77XPPF572`.
- `org.linphone` misc refs: `Linphone/Info.plist` `CFBundleURLName` ×**12** + a literal `org.linphone` **URL scheme** at Info.plist:116 (cosmetic reverse-DNS for `linphone-mention`/`linphone-message`/`linphone-config`/`sip`/`sips`/`callto`/`tel`/`org.linphone` schemes — schemes KEPT except the `org.linphone://` one → `net.blount`, `URIHandler`/`linphone-message://` deep links depend on the `linphone-*` names); `SingleSignOnManager.swift:31` `org.linphone:/openidcallback` (SSO redirect — renamed for cleanliness; linphone.org SSO unused in our build); `intentsExtension/IntentHandler.swift:39` `org.linphone.startCall` activityType; `scripts/run-mdm-tests.sh:81,90,91` (sim-only test script); `GoogleService-Info.plist` BUNDLE_IDs.
- **Shim is plain HTTP**, not HTTPS (`http.server.ThreadingHTTPServer`, no TLS) listening `0.0.0.0:8777` on pbx-wazo-01 (`192.168.200.158`, reached over tailnet subnet route `192.168.200.0/24`). → patch adds `NSAppTransportSecurity/NSAllowsLocalNetworking` to Info.plist (RFC1918 IP loads). If a MagicDNS name is used later, add an `NSExceptionDomains` entry.
- **Shim schema correction vs task brief**: body key is `"user"` (accepts extNNNN username → confd `users?search=` match, OR wazo-auth uuid when it looks like `36-char with -`), NOT `"user_uuid"`. Optional `"apns_notification_token"` — patch sends `core.pushNotificationConfig?.remoteToken` when present (enables webhookd alert pushes: missedCall/voicemail/message). `apns_call_topic`/`apns_default_topic` sent as `<bundle>.voip` / `<bundle>` — matches shim defaults; sent explicitly so a bundle rename stays consistent.
- `aps-environment = development` in `Linphone/Linphone.entitlements` (both `aps-environment` and `com.apple.developer.aps-environment` keys) — rebrand.sh flips to `production` by default (`APS_ENVIRONMENT=development ./rebrand.sh` for dev-signed builds); webhookd `use_sandbox` must match.
- Signing: `CODE_SIGN_STYLE = Automatic`, `PROVISIONING_PROFILE_SPECIFIER = ""` — CI will override via `xcodebuild` args. 4 profiles needed: `net.blount.phone` + `.msgNotificationService` + `.linphoneExtension` + `.intentsExtension`.
- `productName = Linphone` / `PRODUCT_NAME = LinphoneApp` left as-is — only `CFBundleDisplayName` is user-visible.
- Strings/localization ("Linphone" in Localizable.strings, AppIntentVocabulary examples, welcome screens) — cosmetic surface, deferred; `rebrand.sh` only touches AppIntentVocabulary example phrases.

## Exact insertion point (CoreContext.swift)

The patch anchors on `Linphone/Core/CoreContext.swift` `onAccountRegistrationStateChanged`, `.Ok` case (lines 408-424):

```swift
			}, onAccountRegistrationStateChanged: { (core: Core, account: Account, state: RegistrationState, message: String) in
				// If account has been configured correctly, we will go through Progress and Ok states
				// Otherwise, we will be Failed.
				Log.info("New registration state is \(state) for user id " +
						 "\( String(describing: account.params?.identityAddress?.asString())) = \(message)\n")
				
				switch state {
				case .Ok:
					DispatchQueue.main.async {
						NotificationCenter.default.post(name: NSNotification.Name("CoreStarted"), object: nil)
					}
					ContactsManager.shared.fetchContacts()
					
					if let defaultAccountParams = self.mCore.defaultAccount?.params, defaultAccountParams.publishEnabled == false {
						let params = defaultAccountParams
						let clonedParams = params.clone()
						clonedParams?.publishEnabled = true
						self.mCore.defaultAccount?.params = clonedParams
					}
					
					if self.mCore.consolidatedPresence !=  ConsolidatedPresence.Online {
						self.updatePresence(core: self.mCore, presence: ConsolidatedPresence.Online)
					}
					// >>> PATCH INSERTS PushShimReporter.reportVoipTokenIfNeeded(core:account:) HERE <<<
				case .Cleared:
```

## Rename checklist (all executed by `rebrand.sh`)

- [x] `org.linphone.phone` → `net.blount.phone` — pbxproj ×6 lines (12 configs), Info.plist CFBundleURLName ×4, keychain-access-groups ×2, GoogleService-Info.plist ×1
- [x] `org.linphone.phone.{msgNotificationService,linphoneExtension,intentsExtension}` → same-substitution suffixes (upstream camelCase style kept)
- [x] `org.linphone.LinphoneApp{Tests,UITests}` → `net.blount.LinphoneApp{Tests,UITests}`
- [x] `group.org.linphone.phone.*` + `group.belledonne-communications.linphone` → `group.net.blount.phone` (Shared.xcconfig, 3 entitlements, ShareViewController.swift:140, run-mdm-tests.sh; Linphone.entitlements array collapsed to single group)
- [x] `APP_GROUP_NAME = group.org.linphone.phone.msgNotification` → `group.net.blount.phone` (single shared group for app+extensions — register ONE app group in portal)
- [x] `DEVELOPMENT_TEAM Z2V957B3D6` → `S77XPPF572` (11×)
- [x] `INFOPLIST_KEY_CFBundleDisplayName = Linphone` → `"Blount Phone"` (2×)
- [x] `aps-environment` → `production` (env-tunable)
- [x] strip `-DUSE_CRASHLYTICS` / `"USE_CRASHLYTICS=1"` (Firebase out of binary path)
- [x] SPM: gitlab URL → `github.com/BelledonneCommunications/linphone-sdk-swift-ios.git`, `branch=stable` → `exactVersion 5.5.36` (both refs), keeps Package.resolved consistent
- [x] `org.linphone:/openidcallback` → `net.blount.phone:/openidcallback`; `org.linphone.startCall` → `net.blount.phone.startCall`
- [x] AppIntentVocabulary "with Linphone" → "with Blount Phone" (all lproj copies)
- [x] `org.linphone` URL scheme (Info.plist:116) → `net.blount` (provisioning deep-link scheme)
- [x] Appends `PBX_SHIM_URL`/`PBX_SHIM_TOKEN` build settings to Shared.xcconfig (token empty default — CI injects via `xcodebuild` arg so no secret touches source)

**Live-tested 2026-10-24:** `rebrand.sh` + `git apply corecontext-shim.patch` run against the real `/tmp/linphone-iphone-6.2` checkout — idempotent (2 runs clean), final `org.linphone`/`Z2V957B3D6`/`gitlab.linphone.org`/`USE_CRASHLYTICS` greps all empty, all positive assertions pass.

## Manual leftovers (NOT scripted — deliberate)

- ~~`Linphone/Assets.xcassets/AppIcon.appiconset/1024x1024.png`~~ — NOW SCRIPTED: `make-icon.py` renders + `rebrand.sh` step 6b drops an opaque RGB Blount icon (TestFlight rejects alpha).
- `illus-belledonne` image assets + "Linphone" strings in Localizable.strings/welcome flows — cosmetic, later pass.
- `sip.linphone.org` default domain / `linphone-iphone@belledonne-communications.com` log-email — upstream defaults kept (harmless; can revisit).
- `linphone-*` URL schemes — internal deep links (`linphone-message://` used by `LinphoneApp.swift:321`, remote provisioning uses `linphone-config://`) — kept.
- TestFlight/App-Store metadata, icon — at submission.

## Pre-portal checklist (A4 dependency)

App IDs to register (all with Push Notifications; app also needs app-group + keychain-sharing):
`net.blount.phone`, `net.blount.phone.msgNotificationService`, `net.blount.phone.linphoneExtension`, `net.blount.phone.intentsExtension`.
App group: `group.net.blount.phone`. 4 provisioning profiles — RESOLVED app-store method: `BlountDist <bundle-id>` minted via ASC API under dist cert `LY27K966XJ`; b64 blobs live in fork secrets `PROV_PROFILE_*` (CI manual export-signing).
