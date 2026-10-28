#!/usr/bin/env python3
"""Fail CI if the exported IPA lacks the app group needed at launch."""

import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: verify-exported-entitlements.py <ipa>")

ipa = Path(sys.argv[1]).resolve()
group = "group.net.blount.phone"
with tempfile.TemporaryDirectory() as directory:
    subprocess.run(["unzip", "-q", str(ipa), "-d", directory], check=True)
    app = Path(directory) / "Payload/LinphoneApp.app"
    targets = [
        app,
        app / "PlugIns/msgNotificationService.appex",
        app / "PlugIns/linphoneExtension.appex",
    ]
    for target in targets:
        subprocess.run(["codesign", "--verify", "--strict", str(target)], check=True)
        signed = subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(target)],
            check=True,
            capture_output=True,
        )
        entitlements = plistlib.loads(signed.stdout)
        if group not in entitlements.get("com.apple.security.application-groups", []):
            raise SystemExit(f"Missing signed app group entitlement: {target.name}")
        print(f"Signed app group verified: {target.name}")
