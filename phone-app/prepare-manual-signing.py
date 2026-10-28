#!/usr/bin/env python3
"""Bind each branded target to its installed App Store profile for archive signing."""

from pathlib import Path
import re

project = Path("LinphoneApp.xcodeproj/project.pbxproj")
source = project.read_text()
profiles = {
    "net.blount.phone": "BlountDist net.blount.phone",
    "net.blount.phone.msgNotificationService": "BlountDist net.blount.phone.msgNotificationService",
    "net.blount.phone.linphoneExtension": "BlountDist net.blount.phone.linphoneExtension",
    "net.blount.phone.intentsExtension": "BlountDist net.blount.phone.intentsExtension",
}
counts = {bundle: 0 for bundle in profiles}


def sign_configuration(match: re.Match[str]) -> str:
    block = match.group(0)
    for bundle, profile in profiles.items():
        if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};" not in block:
            continue
        if "CODE_SIGN_STYLE = Automatic;" not in block:
            raise SystemExit(f"Missing automatic signing style for {bundle}")
        block = block.replace("CODE_SIGN_STYLE = Automatic;", "CODE_SIGN_STYLE = Manual;")
        specifier = f'PROVISIONING_PROFILE_SPECIFIER = "{profile}";'
        if 'PROVISIONING_PROFILE_SPECIFIER = "";' in block:
            block = block.replace('PROVISIONING_PROFILE_SPECIFIER = "";', specifier)
        elif "PROVISIONING_PROFILE_SPECIFIER =" not in block:
            block = block.replace("CODE_SIGN_STYLE = Manual;", f"CODE_SIGN_STYLE = Manual;\n\t\t\t\t{specifier}")
        else:
            raise SystemExit(f"Unexpected profile setting for {bundle}")
        counts[bundle] += 1
        return block
    return block


updated = re.sub(r"\t\t[A-F0-9]{24} /\* [^\n]* \*/ = \{\n\t\t\tisa = XCBuildConfiguration;.*?\n\t\t\};", sign_configuration, source, flags=re.S)
if any(count != 2 for count in counts.values()):
    raise SystemExit(f"Expected Debug and Release signing settings for each target: {counts}")
project.write_text(updated)
print("Prepared manual archive signing for four app targets")
