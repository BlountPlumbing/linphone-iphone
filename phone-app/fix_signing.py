#!/usr/bin/env python3
"""fix_signing.py — correct manual-signing config in the rebranded pbxproj.

Replaces rebrand.sh's retired perl block transform, which matched config
blocks by text order and landed Manual/specifier keys on the wrong targets'
wrong configs (Release stayed Automatic -> "conflicting provisioning
settings" archive failure; the original workaround — CODE_SIGNING_ALLOWED=NO
— shipped entitlements-stripped binaries that crash every launch).

Parses the object graph properly: PBXNativeTarget -> buildConfigurationList
-> XCBuildConfiguration(Release) for the four app/extension bundle ids, and
writes CODE_SIGN_STYLE=Manual, CODE_SIGN_IDENTITY="Apple Distribution",
PROVISIONING_PROFILE_SPECIFIER="BlountDist <bundle>". Idempotent.
"""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'LinphoneApp.xcodeproj/project.pbxproj'
src = open(path).read()

BUNDLES = [
    'net.blount.phone',
    'net.blount.phone.msgNotificationService',
    'net.blount.phone.linphoneExtension',
    'net.blount.phone.intentsExtension',
]

# --- parse objects: HEXID /* comment */ = { ... }; -------------------------
obj_re = re.compile(r'([0-9A-F]{24}) /\* ([^*]+) \*/ = \{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\};', re.S)
objects = {}
for m in obj_re.finditer(src):
    objects[m.group(1)] = {'comment': m.group(2), 'body': m.group(3), 'span': m.span()}

def field(body, key):
    m = re.search(re.escape(key) + r' = ([^;]+);', body)
    return m.group(1).strip() if m else None

# --- XCBuildConfiguration objects: map id -> (name, body) ------------------
configs = {}
for oid, o in objects.items():
    if 'isa = XCBuildConfiguration' in o['body']:
        configs[oid] = o

# --- XCConfigurationList -> {listid: [configids]} --------------------------
conflists = {}
for oid, o in objects.items():
    if 'isa = XCConfigurationList' in o['body']:
        ids = re.findall(r'([0-9A-F]{24}) /\* (?:Release|Debug) \*/', o['body'])
        conflists[oid] = ids

# --- PBXNativeTarget -> (name, conflist id) --------------------------------
targets = []
for oid, o in objects.items():
    if 'isa = PBXNativeTarget' in o['body']:
        cl = field(o['body'], 'buildConfigurationList')
        clid = cl.split()[0] if cl else None
        targets.append((oid, o['comment'], clid))

def rewrite_config(body, bundle):
    def upsert(b, key, val):
        if re.search(re.escape(key) + r'\s*=', b):
            return re.sub(re.escape(key) + r' = [^;]+;', f'{key} = {val};', b)
        # append at end of buildSettings body, matching tab indent
        return b.rstrip() + f'\n\t\t\t\t{key} = {val};\n\t\t\t'
    body = upsert(body, 'CODE_SIGN_STYLE', 'Manual')
    body = upsert(body, 'CODE_SIGN_IDENTITY', '"Apple Distribution"')
    body = upsert(body, 'CODE_SIGN_IDENTITY[sdk=iphoneos*]', '"Apple Distribution"')
    body = upsert(body, 'PROVISIONING_PROFILE_SPECIFIER', f'"BlountDist {bundle}"')
    # strip legacy uuid key that forces automatic-style conflict
    body = re.sub(r'\n\t\t\t+PROVISIONING_PROFILE = "[0-9a-fA-F-]+";', '', body)
    return body

edits = 0
out = src
spans = []
for oid, name, clid in targets:
    if not clid or clid not in conflists:
        continue
    for cid in conflists[clid]:
        cfg = configs.get(cid)
        if not cfg or 'name = Release' not in cfg['body']:
            continue
        b = cfg['body']
        m = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = (net\.blount\.phone(?:\.[A-Za-z]+)?);', b)
        if not m or m.group(1) not in BUNDLES:
            continue
        nb = rewrite_config(b, m.group(1))
        if nb != b:
            spans.append((cfg['span'], nb))
            edits += 1

# apply edits from the end backwards so spans stay valid
for (s, e), nb in sorted(spans, reverse=True):
    header = out[s:e]
    # replace only the body portion inside the object text
    objtext = out[s:e]
    # body is everything after '= {' up to before final '}'
    pre = objtext[:objtext.index('{')+1]
    post = objtext[objtext.rindex('}'):]
    out = out[:s] + pre + nb + post + out[e:]

open(path, 'w').write(out)
print(f'fix_signing: {edits} Release config(s) rewritten')
if edits < 4:
    print(f'WARNING: expected 4 app-target Release configs, rewrote {edits}')
    sys.exit(1)
