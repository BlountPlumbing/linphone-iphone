#!/usr/bin/env python3
"""fix_signing.py — correct manual-signing config in the rebranded pbxproj.

Line-wise editing only: replaces or inserts whole lines inside the
buildSettings region of each app target's Release XCBuildConfiguration.
Never restructures the file — the v1 object-splice corrupted the project
(run 45575337718: "project is damaged ... parse error").

Sets CODE_SIGN_STYLE=Manual, CODE_SIGN_IDENTITY="Apple Distribution",
PROVISIONING_PROFILE_SPECIFIER="BlountDist <bundle>" for the four
app/extension bundle ids; strips legacy PROVISIONING_PROFILE uuid lines.
Idempotent.
"""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'LinphoneApp.xcodeproj/project.pbxproj'
lines = open(path).readlines()

BUNDLES = {
    'net.blount.phone',
    'net.blount.phone.msgNotificationService',
    'net.blount.phone.linphoneExtension',
    'net.blount.phone.intentsExtension',
}

# --- pass 1: object map — id -> (start, end, isa) --------------------------
obj_start = re.compile(r'^\t\t([0-9A-F]{24}) /\* (.+?) \*/ = \{$')
objects = {}
cur = None
for i, ln in enumerate(lines):
    m = obj_start.match(ln)
    if m:
        cur = m.group(1)
        objects[cur] = {'start': i, 'end': None, 'comment': m.group(2)}
    elif cur and ln.rstrip() == '\t\t};':
        objects[cur]['end'] = i
        cur = None

def obj_lines(oid):
    o = objects[oid]
    return lines[o['start']:o['end']+1]

def field(oid, key):
    for ln in obj_lines(oid):
        m = re.match(r'\s*' + re.escape(key) + r' = ([^;]+);', ln)
        if m:
            return m.group(1).strip()
    return None

# --- pass 2: targets -> configuration list -> Release config ids -----------
edits = 0
for oid, o in objects.items():
    body = ''.join(obj_lines(oid))
    if 'isa = PBXNativeTarget' not in body:
        continue
    cl = field(oid, 'buildConfigurationList')
    if not cl:
        continue
    clid = cl.split()[0]
    if clid not in objects:
        continue
    # config ids inside the configuration list object
    for ln in obj_lines(clid):
        cm = re.match(r'\s*([0-9A-F]{24}) /\* Release \*/,?', ln)
        if not cm:
            continue
        cid = cm.group(1)
        if cid not in objects:
            continue
        cbody = ''.join(obj_lines(cid))
        bm = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = (net\.blount\.phone(?:\.[A-Za-z]+)?);', cbody)
        if not bm or bm.group(1) not in BUNDLES:
            continue
        # --- edit this config object line-wise ---
        bundle = bm.group(1)
        o0, o1 = objects[cid]['start'], objects[cid]['end']
        seg = lines[o0:o1+1]
        want = {
            'CODE_SIGN_STYLE': 'CODE_SIGN_STYLE = Manual;',
            'CODE_SIGN_IDENTITY': 'CODE_SIGN_IDENTITY = "Apple Distribution";',
            'CODE_SIGN_IDENTITY[sdk=iphoneos*]': '"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";',
            'PROVISIONING_PROFILE_SPECIFIER': f'PROVISIONING_PROFILE_SPECIFIER = "BlountDist {bundle}";',
        }
        seen = set()
        # buildSettings region bounds within seg
        bs_start = bs_end = None
        for j, ln in enumerate(seg):
            if 'buildSettings = {' in ln:
                bs_start = j
            elif bs_start is not None and bs_end is None and re.match(r'^\t\t\t\};', ln):
                bs_end = j
        if bs_start is None or bs_end is None:
            continue
        out_seg = seg[:]
        for j in range(bs_start+1, bs_end):
            ln = out_seg[j]
            km = re.match(r'^(\t\t\t\t)"?([A-Z_]+(?:\[sdk=[^\]]+\])?)"? = ', ln)
            if km and km.group(2) in want:
                key = km.group(2)
                newline = f'{km.group(1)}{want[key]}\n'
                if ln != newline:
                    out_seg[j] = newline
                    edits += 1
                seen.add(key)
            if re.match(r'^\t\t\t\tPROVISIONING_PROFILE = "[0-9a-fA-F-]+";', ln):
                out_seg[j] = ''
                edits += 1
        missing = [k for k in want if k not in seen]
        if missing:
            indent = '\t\t\t\t'
            ins = ''.join(f'{indent}{want[k]}\n' for k in missing)
            out_seg[bs_end] = ins + out_seg[bs_end]
            edits += len(missing)
        lines[o0:o1+1] = out_seg

open(path, 'w').write(''.join(lines))
print(f'fix_signing: applied {edits} line edits')
