#!/usr/bin/env python3
"""deploy-apns-config — write the iOS APNs VoIP cert+key to wazo-auth
external/mobile config so wazo-webhookd can send native APNs pushes.

Plan atom A3a (docs/PHONE-APP-FORMAL-PLAN-20261023.md). Runs ONCE after A4
delivers the Apple VoIP Services certificate (.cer) paired with the CSR's
private key.

VERIFIED LIVE 2026-10-24 on pbx-wazo-01 (wazo 26.10):
  - Endpoint: /0.1/external/mobile/config (= /external/{auth_type}/config,
    auth_type=mobile). GET 200|404, POST 201|409-dup, PUT 201|404.
    ACL auth.mobile.external.config.{create,read,update} — covered by the
    root `wazo-auth-cli` admin token (same as pbx-push-shim.py).
  - Fields (ExternalConfig): ios_apn_certificate (str = PEM text),
    ios_apn_private (str = unencrypted PEM text — api.yml says "boolean",
    that is a SPEC BUG: webhookd plugin.py:65 types it `str` and writes it
    into the client-cert PEM file), use_sandbox (bool).
  - Tenant scope: `Wazo-Tenant` header, optional — default = token's
    tenant. pbx-wazo-01 has ONE tenant: master
    fa1e607d-8e2b-47a4-9735-905c2c237ff7. webhookd reads the config under
    the PUSHED USER's tenant (plugin.py:403 get_config('mobile',
    tenant_uuid)) — single-tenant box, omit the header.
  - NO webhookd restart needed: _fetch_external_data() calls
    auth.external.get_config() per push event (plugin.py:403), not cached.
  - Cert usage (plugin.py:902 _certificate_filename): cert + "\\r\\n" + key
    concatenated into ONE temp PEM file used as the APNs HTTP/2 client cert
    for POST https://api[.sandbox].push.apple.com:443/3/device/<voip-token>.
    => private key MUST be unencrypted PEM (no passphrase field exists).
  - use_sandbox=False -> api.push.apple.com; True -> api.sandbox.push.apple.com
    (+ X-Use-Sandbox: 1). Xcode/dev-profile installs need sandbox;
    TestFlight/App Store need production (False, the default).

USAGE — the script must run INSIDE pbx-wazo-01 (wazo-auth-cli + wazo-auth on
127.0.0.1:9497 only exist there). Inputs staged locally at /tmp/voip-cert/
(voip.cer = Apple download, voip-apns.key = CSR's private key).

Option A (this VM, no guest SSH — the METHODS.md wazo-vm-access path):
    tar czf - -C /home/nick/Windows/blount-platform/phone-app deploy-apns-config.py \
        -C /tmp/voip-cert voip.cer voip-apns.key | base64 -w0 > /tmp/apns-deploy.b64
    ssh nick@192.168.1.2 "virsh qemu-agent-command pbx-wazo-01 \
      '{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/bash\",\"arg\":[\"-c\",\
      \"mkdir -p /tmp/apns-deploy && base64 -d <<< $(cat /tmp/apns-deploy.b64) \
      | tar xz -C /tmp/apns-deploy && python3 /tmp/apns-deploy/deploy-apns-config.py \
      /tmp/apns-deploy/voip.cer /tmp/apns-deploy/voip-apns.key\"],\"capture-output\":true}}'"
    (the base64 blob embeds unquoted — its alphabet is shell-safe; adding
    quotes would collide with the remote-level single-quoted JSON)
    then poll: virsh qemu-agent-command pbx-wazo-01
      '{"execute":"guest-exec-status","arguments":{"pid":<pid>}}'
    and base64-decode out-data for the script's output.

Option B (inside the guest, e.g. ssh debian@192.168.200.158 via
~/.ssh/wazo-appliance-ed25519 on the build host):
    sudo python3 deploy-apns-config.py /path/to/voip.cer /path/to/voip-apns.key
    add --sandbox for dev-profile builds; --dry-run to preview; --tenant-uuid
    to write a non-master tenant.

Idempotent: GET first; POST on 404, PUT on drift, no-op when already correct.
Never prints full PEM — masked heads + SHA-256 fingerprints only.
"""
import argparse
import hashlib
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

AUTH = os.environ.get("WAZO_AUTH", "http://127.0.0.1:9497/0.1")
CONFIG_PATH = "/external/mobile/config"

CERT_BEGIN = "-----BEGIN CERTIFICATE-----"
CERT_END = "-----END CERTIFICATE-----"
KEY_BEGIN = re.compile(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----")


# --- auth/HTTP idiom: verbatim convention from pbx-push-shim.py -------------
def admin_token():
    out = subprocess.check_output(
        ["wazo-auth-cli", "token", "create", "--expiration", "300"])
    return out.decode().strip()


def api(tok, method, path, body=None, tenant=None):
    req = urllib.request.Request(
        AUTH + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method)
    req.add_header("X-Auth-Token", tok)
    req.add_header("Content-Type", "application/json")
    if tenant:
        req.add_header("Wazo-Tenant", tenant)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, {"_error": e.read().decode(errors="replace")[:400]}


# --- file loading ------------------------------------------------------------
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def load_cert_pem(path):
    """Accept Apple's .cer (DER) or an already-PEM file; return PEM text."""
    raw = open(path, "rb").read()
    if CERT_BEGIN.encode() in raw:
        text = raw.decode()
        if CERT_END not in text:
            sys.exit("cert %s: PEM begin marker but no END marker" % path)
        return text.strip()
    # DER — prefer stdlib; openssl fallback
    try:
        return ssl.DER_cert_to_PEM_cert(raw).strip()
    except Exception:
        p = run(["openssl", "x509", "-inform", "DER", "-in", path,
                 "-outform", "PEM"])
        if p.returncode != 0:
            sys.exit("cert %s: not PEM and DER->PEM failed: %s"
                     % (path, p.stderr.strip()))
        return p.stdout.strip()


def load_key_pem(path):
    """Private key must be unencrypted PEM; try DER convert if it isn't."""
    raw = open(path, "rb").read()
    text = raw.decode(errors="replace") or ""
    if "BEGIN ENCRYPTED PRIVATE KEY" in text:
        sys.exit("key %s is passphrase-encrypted (PKCS#8) — webhookd has no "
                 "passphrase field; export unencrypted PEM" % path)
    if KEY_BEGIN.search(text):
        return text.strip()
    p = run(["openssl", "pkey", "-inform", "DER", "-in", path,
             "-outform", "PEM"])
    if p.returncode != 0:
        sys.exit("key %s: not PEM and DER->PEM failed: %s"
                 % (path, p.stderr.strip()))
    return p.stdout.strip()


class tempfile_pem:
    def __init__(self, text):
        self._t = text

    def __enter__(self):
        fd, self.name = tempfile.mkstemp()
        os.write(fd, self._t.encode())
        os.close(fd)
        return self.name

    def __exit__(self, *a):
        os.unlink(self.name)


def cert_info(cert_pem):
    """subject / issuer / enddate / sha256 fp via openssl — masked facts only."""
    with tempfile_pem(cert_pem) as f:
        p = run(["openssl", "x509", "-in", f, "-noout",
                 "-subject", "-issuer", "-enddate",
                 "-fingerprint", "-sha256"])
    return p.stdout.strip() if p.returncode == 0 else "(openssl info failed)"


def check_key_matches_cert(cert_pem, key_pem):
    """openssl x509 -pubkey == openssl pkey -pubout (RSA+EC safe)."""
    with tempfile_pem(cert_pem) as cf, tempfile_pem(key_pem) as kf:
        cp = run(["openssl", "x509", "-in", cf, "-pubkey", "-noout"])
        kp = run(["openssl", "pkey", "-in", kf, "-pubout"])
        if kp.returncode != 0:
            sys.exit("key is not a readable unencrypted private key: %s"
                     % kp.stderr.strip())
        ok = cp.returncode == 0 and cp.stdout.strip() == kp.stdout.strip()
    if not ok:
        sys.exit("cert/key MISMATCH — voip.cer is not paired with this key")


def mask(pem):
    lines = pem.strip().splitlines()
    if len(lines) <= 4:
        return "(too short to mask)"
    h = hashlib.sha256(pem.encode()).hexdigest()[:16]
    return "%s\n  ...<%d lines>...\n%s   [sha256:%s...]" % (
        lines[0], len(lines) - 2, lines[-1], h)


# --- main --------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("cert", help="voip.cer — Apple VoIP Services cert (DER .cer or PEM)")
    ap.add_argument("key", help="voip-apns.key — unencrypted PEM private key from the CSR")
    ap.add_argument("--sandbox", action="store_true",
                    help="use_sandbox=true (Xcode/dev-profile installs only; "
                         "TestFlight/App Store = production, keep unset)")
    ap.add_argument("--tenant-uuid", default=None,
                    help="Wazo-Tenant header (default: token's tenant = master)")
    ap.add_argument("--dry-run", action="store_true",
                    help="parse+verify inputs, show payload shape, write nothing")
    args = ap.parse_args()

    cert_pem = load_cert_pem(args.cert)
    key_pem = load_key_pem(args.key)
    if "ENCRYPTED" in key_pem:
        sys.exit("key is passphrase-encrypted — webhookd has no passphrase "
                 "field; export unencrypted PEM")
    check_key_matches_cert(cert_pem, key_pem)

    body = {
        "ios_apn_certificate": cert_pem,
        "ios_apn_private": key_pem,
        "use_sandbox": bool(args.sandbox),
    }
    print("== inputs ==")
    print(cert_info(cert_pem))
    print("cert PEM:\n" + mask(cert_pem))
    print("key  PEM:\n" + mask(key_pem))
    print("use_sandbox: %s" % body["use_sandbox"])
    if args.dry_run:
        print("--dry-run: verified inputs, no write.")
        return

    tok = admin_token()
    code, cur = api(tok, "GET", CONFIG_PATH, tenant=args.tenant_uuid)
    if code == 404:
        code, res = api(tok, "POST", CONFIG_PATH, body, args.tenant_uuid)
        if code == 409:  # raced — fall back to update
            code, res = api(tok, "PUT", CONFIG_PATH, body, args.tenant_uuid)
        print("write result: HTTP %s" % code)
        if code not in (200, 201):
            sys.exit("config write failed: %s" % res)
    elif code == 200:
        if (cur.get("ios_apn_certificate") == cert_pem
                and cur.get("ios_apn_private") == key_pem
                and cur.get("use_sandbox") == body["use_sandbox"]):
            print("already up-to-date — no write needed")
        else:
            code, res = api(tok, "PUT", CONFIG_PATH, body, args.tenant_uuid)
            print("PUT result: HTTP %s" % code)
            if code not in (200, 201):
                sys.exit("config update failed: %s" % res)
    else:
        sys.exit("GET %s failed: HTTP %s %s" % (CONFIG_PATH, code, cur))

    # read-back verify — masked, fingerprints only
    code, back = api(tok, "GET", CONFIG_PATH, tenant=args.tenant_uuid)
    if code != 200:
        sys.exit("read-back GET failed: HTTP %s %s" % (code, back))
    ok = True
    for f, want in body.items():
        got = back.get(f)
        if f == "ios_apn_private" and not isinstance(got, str):
            # api.yml spec bug types this 'boolean' — accept truthy as "set",
            # but a missing/falsy value means the key didn't round-trip
            ok &= bool(got)
            status = "present(non-str: %r) — spec-bug form; ok" % got \
                if got else "MISSING/non-str %r — FAIL" % got
        else:
            match = got == want
            ok &= match
            status = "MATCH" if match else "MISMATCH"
        print("verify %-20s %s" % (f, status))
    if not ok:
        sys.exit("read-back verification FAILED")
    print("DONE — webhookd consumes this config per-push (no restart needed).")
    print("Next: push a call to a registered device; expect APNs POST to "
          "api%s.push.apple.com." % (".sandbox" if args.sandbox else ""))


if __name__ == "__main__":
    main()
