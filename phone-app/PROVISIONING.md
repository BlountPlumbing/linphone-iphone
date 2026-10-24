# Blount Phone — zero-touch account provisioning

Researched 2026-10-24 against the real fork checkout (`/tmp/linphone-iphone-6.2`,
branch `release/6.2-blount`, upstream `release/6.2` @ `694f17de`, SDK 5.5.36) and
liblinphone `coreapi/remote_provisioning.c` (master). Goal: when the app lands on
Nick's (ext9001) and Catherine's (ext9002) iPhones, no SIP fields are typed by hand.

## TL;DR — chosen path

**Primary: in-app QR scan** — welcome → "Use a SIP account" → **Scan QR code** →
point at a per-user QR encoding
`http://192.168.200.158:8777/provisioning/ext9001-<token>.linphonerc`.
The scanned string goes straight to `core.setProvisioninguri` + core restart;
the fetch itself is liblinphone's own HTTP stack (belle-sip/belle-http), **not**
URLSession — so plain HTTP on the tailnet works and ATS is not in play.

**Fallback A: paste URL** — Settings → Advanced → "Remote provisioning URL" →
paste the same URL → "Download and apply". Same engine, typed once.

**Fallback B (only once an HTTPS host exists): `linphone-config://` deep link** —
the app's handler **force-prepends `https://`** (`URIHandler.swift:109-111`), so
it cannot address the current plain-HTTP shim. Works later if the shim gains TLS
(e.g. `tailscale cert` on a `*.ts.net` name) or the files move behind an HTTPS
edge; format `linphone-config://<host>/<path>` (host/path becomes
`https://host/path`) or `linphone-config://https://<host>/<path>`.

**MDM (`xmlConfig`) is supported but unused** — no MDM server exists in the
fleet. Keys verified: `xmlConfig` (lpconfig XML via `Config.loadFromXmlString`),
`rootCa` (PEM → `core.rootCaData`), `configUri` (= provisioning URI, applied
last + core restart) — `MDMManager.swift:75-160`, README.md:146-150. If a real
MDM ever appears, push `configUri` at the same per-user URLs — zero code change.

## Evidence — where provisioning is triggered in-app

| Entry point | File:line | Behaviour |
|---|---|---|
| `linphone-config://` URL scheme registered | `Linphone/Info.plist:36` | `CFBundleURLSchemes` includes `linphone-config` |
| URL dispatch | `Linphone/Utils/URIHandler.swift:30,60-77` | `configurationSchemes=["linphone-config"]` → `initiateConfiguration` |
| Deep-link → provisioning | `URIHandler.swift:98-125` | strips leading `//`, **prepends `https://` if absent** (`:109-111`), writes `misc/config-uri` (`:113`), `setProvisioninguri` + `core.stop()/start()` (`:114-116`). Gated by `[app] auto_apply_provisioning_config_uri_handler` (default true, `:171-173`) |
| QR scanner (assistant login) | `Linphone/UI/Assistant/Viewmodel/QRScanner.swift:60-96` | scanned QR → `NSURL` + `canOpenURL` check (http/https always pass) → `setProvisioninguri(result)` + restart (`:79-83`); result toast via `onConfiguringStatus` (`:98-126`) |
| QR button location | `Linphone/UI/Assistant/Fragments/LoginFragment.swift:285-310` | "assistant_scan_qr_code" button → `QrCodeScannerFragment` — on the SIP-account login page, no account needed |
| Settings paste field | `Linphone/UI/Main/Settings/Fragments/SettingsAdvancedFragment.swift:90-125` | "Remote provisioning URL" field + "Download and apply" button → `SettingsViewModel.downloadAndApplyRemoteProvisioning` (`SettingsViewModel.swift:223-237`) → `setProvisioninguri` + stop/start — **no scheme forced** |
| MDM payload | `Linphone/Utils/MDMManager.swift:75-95,136-149` | `xmlConfig` → `config.loadFromXmlString`; `configUri` → `setProvisioninguri` + restart; `rootCa` → `core.rootCaData` |
| Core hooks | `Linphone/Core/CoreContext.swift:105-124,182-187` | `handleConfigurationChanged` rebuilds account list on `ConfiguringState .Successful`; `MDMManager.applyMdmConfigToCore` runs at core init |
| Fetch engine (upstream) | liblinphone `coreapi/remote_provisioning.c` | `linphone_remote_provisioning_download_and_apply` parses URI with `belle_generic_uri_parse`, handles `file://` locally, downloads via belle-http; apply = `_linphone_config_load_from_xml_string` after **pruning all `auth_info_N` sections**, then re-applying factory rc |

**ATS note:** the provisioning download runs inside liblinphone's belle-http
provider — raw sockets, not `NSURLSession`/`WKWebView` — so iOS App Transport
Security does **not** gate it. `NSAllowsLocalNetworking` (already added by the
patch for `PBX_SHIM_URL`) only covers the app-side `URLSession` POST to the
shim in `PushShimReporter`. The `linphone-config://` https-forcing is an
app-code policy (URIHandler.swift:109-111), not an OS requirement.

## Payload format

Template: `phone-app/provisioning-template.linphonerc`. The body MUST be
lpconfig **XML** (`xmlns="http://www.linphone.org/xsds/lpconfig.xsd"`) — the
name/extension is ignored. Verified working shape in-tree
(`LinphoneAppUITests/MDMChatFeatureUITests.swift:123-144`): `proxy_0`
(`reg_identity`, `reg_proxy`, `reg_route`, `realm`) + `auth_info_0`
(`username`, `domain`, `ha1`/`passwd`, `realm`, `algorithm`).

Our template sets:

- `[proxy_0]` — `reg_identity=sip:__EXT__@__DOMAIN__`,
  `reg_proxy`/`reg_route` = `<sip:__DOMAIN__;transport=tls>` where
  `__DOMAIN__ = 192.168.200.158:5061` (direct TLS to pbx-wazo-01 over the
  tailnet route); `push_notification_allowed=1` +
  `remote_push_notification_allowed=1` (pn-* params stay on; the SDK
  auto-derives `pn-param=S77XPPF572.net.blount.phone.voip&remote` and
  `pn-prid` from the bundle ID — no push keys beyond the allow-flags needed).
- `[auth_info_0]` — `username=__EXT__`, `passwd=__PASSWORD__`,
  `domain=__DOMAIN__`, `realm=asterisk` (chan_pjsip default; provisioner sets
  no realm), `algorithm=MD5`. Optional hardening: replace `passwd` with
  `ha1 = md5(__EXT__:asterisk:__PASSWORD__)` — password-equivalent either way.
- `[sip]` — `media_encryption=srtp` (endpoint is `sdes32` = SDES-SRTP).
- `[misc]` — `config-uri=__SELF_URI__` so the core re-fetches on every start
  (password rotation propagates on next launch; same thing URIHandler writes).

## What hosts the XML — IMPLEMENTED 2026-10-24

`pbx-push-shim` extended + deployed + live-verified
(`wazo-appliance/runtime/pbx-push-shim.py`, systemd `pbx-push-shim.service`
on pbx-wazo-01, `/opt/pbx/pbx-push-shim.py`, `:8777`):

1. `GET /provisioning/<name>` serves files from
   `/etc/pbx-push-shim/provisioning/` (dir root-owned `0700`, files `0600`)
   — strict basename regex `[A-Za-z0-9._-]+\.linphonerc` + realpath
   containment, **no listing, no traversal** (live-verified: missing name →
   404, encoded `..` path → 404). `Cache-Control: no-store` on responses.
2. Per-user files rendered from k8s `blount-pbx-secrets`
   (`SIP_EXT900x_USER`/`_PASSWORD` → `__EXT__`/`__PASSWORD__`,
   `__DOMAIN__=192.168.200.158:5061`, `__SELF_URI__` = the file's own URL)
   and written to the guest via `virsh guest-exec` — **live-verified:
   on-VM sha == served sha for both ext9001 + ext9002.**
3. **Gate by capability URL**: filename = `extNNNN-<24-hex-token>.linphonerc`
   (24-hex from `secrets.token_hex(12)`). **The live filenames are never
   committed** — they are the auth secret. Retrieve them:
   `ssh nick@192.168.1.2 "virsh qemu-agent-command pbx-wazo-01 '{...guest-exec ls /etc/pbx-push-shim/provisioning...}'"`
   (or `guest-exec` `journalctl -u pbx-push-shim` for the fetched names).
4. URL shape (one per phone):
   `http://192.168.200.158:8777/provisioning/<name>`
5. QR payload = that URL verbatim. Generate images on demand — never commit:
   `qrencode -o ext9001-qr.png '<url>'` or `python3 -c "import qrcode; qrcode.make('<url>').save('ext9001-qr.png')"`.

A static file on any other tailnet-reachable web server works identically —
the shim option just keeps phone-app surface in one service. If the shim ever
gets TLS (`tailscale cert` gives a valid `*.ts.net` cert), the same URLs gain
the `linphone-config://` tappable-link form.

## Exact steps — Nick (ext9001) and Catherine (ext9002)

Once per phone:

1. **Tailscale ON** on the iPhone (required — the whole path rides
   `192.168.200.0/24`).
2. Install **Blount Phone** via TestFlight.
3. Open it → welcome pages → **Skip**; permission prompts → **Allow**
   (microphone/notifications; contacts optional).
4. On the assistant screen choose **"Use a SIP account"** → tap
   **"Scan QR code"** → point at the per-user QR (sent by Nick over Signal /
   shown on his screen / printed — payload is just the URL above).
5. `linphonerc` is fetched + applied → the account materializes → the app
   registers `ext900x` to `192.168.200.158:5061` over TLS. Toast
   "QR code validated" = provisioning succeeded.
6. On the first successful REGISTER, `PushShimReporter` (from
   `corecontext-shim.patch`, hooked at `onAccountRegistrationStateChanged`
   `.Ok`) reads `pushNotificationConfig.voipToken` and POSTs it to the shim
   — the webhookd mobile subscription materializes. **No user action; it
   re-fires on every REGISTER so token refresh self-heals.**
7. Verify: account shows registered; test call `9001`↔`9002`;
   `journalctl -u pbx-push-shim` shows one `POST /register` 200 per device.

Fallback if QR fails (camera, lighting): reach the main screen (skip
assistant) → Settings → Advanced → paste the URL under "Remote provisioning
URL" → **Download and apply**.

If the app was already used once with a manual account, remote provisioning
still applies cleanly — liblinphone prunes all `auth_info_N` sections before
loading the payload.

## URL cheat-sheet

| Mechanism | String to deliver | Transport needed |
|---|---|---|
| QR payload / paste field | `http://192.168.200.158:8777/provisioning/ext9001-<tok>.linphonerc` | plain HTTP — works today |
| `linphone-config://` link | `linphone-config://<host>/provisioning/ext9001-<tok>.linphonerc` | **requires HTTPS host** — handler prepends `https://` |
| MDM `configUri` | same URL in the managed dict | whatever scheme the host offers |

## Security notes

- The rendered file **contains the SIP password** — treat as a secret:
  capability-URL filename, `0600` on the VM, tailnet-only reach, never in
  git. The template itself is safe to commit (placeholders only).
- `ha1` substitution (see template comment) avoids cleartext in the file but
  is still password-equivalent — same handling.
- Rotation: re-render the file on the VM; every app start re-fetches it via
  the embedded `misc/config-uri`. To retire a file, rename/delete it — the
  device keeps the last applied config but cannot re-pull.
- `rootCa` (MDM) / `root_ca` rc keys are NOT needed: SIP TLS on pbx-wazo-01
  uses the cert the endpoints already trust — verify at first REGISTER; if
  the cert is self-signed, add `[sip] verify_server_certs=0` or ship the CA
  via `rootCa` once an MDM/HTTPS path exists.
