# E2E ring test runbook — Blount Phone (net.blount.phone)

State at 2026-10-24 06:40 CDT: TestFlight build `ebd47dca` v1 VALID,
internal group `132742bc` (all builds), provisioning files live.

## Install + provision (per device)

1. TestFlight app → Blount Phone → Install (Nick = account holder; Catherine
   pending ASC invite or external-review link).
2. Ensure **Tailscale is ON** (192.168.200.0/24 route is advertised from the
   R740 — verified live).
3. Remote provisioning URL (in-app "remote provisioning" / linphonerc fetch):
   - Nick:      `http://192.168.200.158:8777/provisioning/ext9001-c1c2c502855ea9fede600e3b.linphonerc`
   - Catherine: `http://192.168.200.158:8777/provisioning/ext9002-20fe2bae16824d9250543493.linphonerc`
4. App should register `ext900x` → SIP TLS `192.168.200.158:5061`.

## Watch the token write (PBX side, run during first registration)

```bash
ssh nick@192.168.1.2 'virsh qemu-agent-command --domain pbx-wazo-01 "$(cat <<\"J\"
{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/bash\",\"arg\":[\"-lc\",\"journalctl -u pbx-push-shim -f --no-pager | grep --line-buffered -E \\\"register|token|voip\\\"\"],\"capture-output\":true}}
J
)"'
```

Expected: `POST /register` from the phone → shim writes wazo-auth
`external/mobile` row → webhookd mobile subscription materializes.

Verify MobileData landed:

```bash
ssh nick@192.168.1.2 'virsh qemu-agent-command --domain pbx-wazo-01 "$(cat <<\"J\"
{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/bash\",\"arg\":[\"-lc\",\"wazo-auth-cli user show <uuid> 2>/dev/null | grep -iE \\\"apns|mobile\\\" ; psql -U asterisk -d wazo -tc \\\"select auth_type,metadata from auth_external_auth_data\\\"\"],\"capture-output\":true}}
J
)"'
```

Expected keys: `apns_voip_token`, `apns_call_topic=net.blount.phone.voip`,
`apns_default_topic=net.blount.phone`.

## Ring matrix (call vector: `15547` → office branch → ext900x)

| State | Expected |
|---|---|
| unlocked/foreground | in-app call UI + CallKit |
| locked | CallKit native ring UI |
| backgrounded | APNs push → CallKit ring |
| terminated | APNs push → app wakes → CallKit ring |

For each: watch shim journal (token), `journalctl -u wazo-webhookd -f`
(APNs POST + result), and asterisk SIP trace (`asterisk -rx 'pjsip set
logger on'`).

## Failure triage

- No `POST /register` → app didn't push token: check PushShimReporter log
  (Xcode console / device sysdiagnose), `PBX_SHIM_*` values baked at build.
- Token written but no APNs → webhookd log `apns`/`external/mobile`; cert
  `2X66W784ZX` `use_sandbox=false` matches TestFlight (production).
- Push fires but no ring → `net.blount.phone.voip` topic vs cert entitlement;
  EarlyPushkitDelegate/CallKit path.
- Rings but no audio → SIP TLS reachability (Tailscale on?), SRTP keys.
