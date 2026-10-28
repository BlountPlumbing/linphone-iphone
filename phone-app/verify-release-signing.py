#!/usr/bin/env python3
"""Check the actual Release blocks after rebranding, before archive signing."""

from pathlib import Path
import re

project = Path("LinphoneApp.xcodeproj/project.pbxproj").read_text()
blocks = re.findall(
    r"/\* Release \*/ = \{\n\t+isa = XCBuildConfiguration;\n\t+buildSettings = \{\n(.*?)\n\t+\};\n\t+name = Release;",
    project,
    re.S,
)
for bundle in (
    "net.blount.phone",
    "net.blount.phone.msgNotificationService",
    "net.blount.phone.linphoneExtension",
    "net.blount.phone.intentsExtension",
):
    matched = [block for block in blocks if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};" in block]
    if len(matched) != 1:
        raise SystemExit(f"Expected one Release signing block for {bundle}, found {len(matched)}")
    block = matched[0]
    required = (
        "CODE_SIGN_STYLE = Manual;",
        'CODE_SIGN_IDENTITY = "Apple Distribution";',
        f'PROVISIONING_PROFILE_SPECIFIER = "BlountDist {bundle}";',
    )
    if not all(setting in block for setting in required):
        raise SystemExit(f"Invalid Release signing settings for {bundle}")
    print(f"Release signing settings verified: {bundle}")
