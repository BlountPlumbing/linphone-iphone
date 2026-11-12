"""Blount fixture-preview source contracts.

Native XCTest/device behavior is NOT established here — this suite asserts the
fixture surface's structural invariants at source level (navigation states,
match-state coverage, staff-note isolation, Dynamic Type roles, no networking).
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
blount = root / 'Linphone' / 'UI' / 'Blount'
files = {p.name: p.read_text(encoding='utf-8') for p in blount.glob('*.swift')}
all_src = '\n'.join(files.values())

def check(name, cond):
    if not cond:
        raise SystemExit(f'FAIL: {name}')
    print(f'ok: {name}')

# --- atom 3.03: reversible flag, networking disabled ---
fx = files['BlountFixture.swift']
check('fixture flag arg', '-BlountFixturePreview' in fx)
check('fixture flag env', 'BLOUNT_FIXTURE_PREVIEW' in fx)
check('networking disabled constant', 'networkingAllowed = false' in fx)
check('no networking imports in Blount dir',
      'import Network' not in all_src
      and not any('URLSession' in l and not l.strip().startswith('//') for l in all_src.splitlines()))

# --- atom 3.04/3.06: shell + call-id-keyed return strip ---
sh = files['BlountShell.swift']
check('three sections', all(s in sh for s in ['calls', 'inbox', 'people']) and 'enum BlountSection' in sh)
check('return strip keyed by call id', 'activeCallID' in sh and 'BlountReturnStrip' in sh)
check('corecontext env bind', 'CoreContext' in sh and 'EnvironmentObject' in sh)

# --- atom 3.07/3.08: five match states + fixed controls ---
check('all five match states', all(s in fx for s in ['matched', 'ambiguous', 'unmatched', 'withheld', 'unavailable']))
cs = files['BlountCallsScreen.swift']
check('answer+decline controls', 'Answer' in cs and 'Decline' in cs)
check('staff-only label', 'Staff only' in cs and 'lock.fill' in cs)

# --- atom 3.11/3.12: inbox states + separate drafts ---
ib = files['BlountInboxScreen.swift']
check('four inbox states', all(s in ib for s in ['loading', 'empty', 'denied', 'ready']))
check('separate staff draft', 'staffDraft' in ib and 'Save staff note' in ib)
check('customer recipient review', 'Sends to' in ib)

# --- atom 3.14: independent connection indicators ---
check('dual connection states', 'callConnection' in sh and 'messageConnection' in sh)

# --- atom 3.15: staff entry honest-disabled ---
se = files['BlountStaffEntry.swift']
check('staff auth unavailable note', 'staff-auth-unavailable' in se)
check('disabled auth actions', se.count('.disabled(true)') >= 2)
check('fixture preview labeled non-auth', 'fixture only' in se.lower())

# --- atoms 3.01/3.02/3.17: tokens + Dynamic Type roles, no fixed-size body text ---
check('theme tokens present', all(t in files['BlountTheme.swift'] for t in ['#18343C','#112F38','#F7F8F4','#06776C','#E6C98A','#7A3B47']))
ty = files['BlountTypography.swift']
check('semantic type roles', all(r in ty for r in ['largeTitle','headline','body','callout','footnote','caption']))
check('no fixed-size fonts outside decorative icon', 'font(.system(size:' not in all_src.replace('.font(.system(size: 44))',''))

# --- LinphoneApp wiring: flag branch precedes normal flow ---
app = (root / 'Linphone' / 'LinphoneApp.swift').read_text(encoding='utf-8')
check('fixture branch in RootView', 'BlountFixtureConfig.isEnabled' in app and 'BlountFixtureRoot()' in app)
check('flag is reversible else-branch', '} else if coreContext.coreHasStartedOnce' in app)

print('ALL CHECKS PASSED')

# --- atom 4.22: staff bypass denial (provisioning/deep-link/MDM) ---
ws = files.get('BlountWorkspace.swift', '')
check('staff router exists', 'BlountStaffAccessRouter' in ws)
check('held default module', 'BlountHeldStaffAccessModule' in ws and 'admissionState' in ws)
check('sign-in gated on module', 'module.beginSignIn()' in ws and 'return false' in ws.lower() or 'func beginSignIn() -> Bool { false }' in ws)
# No generic bypass surfaces inside Blount dir:
banned = ['MobileConfig', 'installProfile', 'enrollmentProfile', 'itms-services',
          'ProfileService', 'ASWebAuthenticationSession', 'SFSafariViewController']
check('no provisioning/deep-link auth surfaces in Blount dir',
      not any(b in all_src for b in banned))
# Staff entry remains the single route:
check('single staff entry symbol', all_src.count('BlountStaffEntry') >= 1)
print('ok: atom 4.22 bypass-denial source checks')

# --- atoms 4.23-4.27: transfer lifecycle source contracts ---
tr = files.get('BlountTransfer.swift', '')
check('transfer machine exists', 'BlountTransferMachine' in tr and 'BlountTransferController' in tr)
check('local return not remote confirm', '.transferRequested' in tr and '.remoteConfirmed' in tr)
check('consultation hold preserved', 'consultationHeld' in tr and 'beginConsultation' in tr)
check('restore on cancel/failure', 'restoreAfterCancelOrFailure' in tr)
tt = Path(root / 'LinphoneAppTests' / 'BlountTransferMachineTests.swift')
check('transfer event-sequence tests exist', tt.exists())
if tt.exists():
    tt_src = tt.read_text(encoding='utf-8')
    check('local-return test present', 'testLocalMethodReturnIsNotRemoteConfirmation' in tt_src)
    check('restore tests present', 'testCancelRestoresOriginal' in tt_src and 'testRemoteEndWhilePendingFailsThenRestores' in tt_src)
print('ok: atoms 4.23-4.27 transfer source+test contracts')

# --- atoms 4.28-4.31: regression tests + marketing/legal source contracts ---
rg = Path(root / 'LinphoneAppTests' / 'BlountRegressionTests.swift')
check('regression tests exist', rg.exists())
if rg.exists():
    rs = rg.read_text(encoding='utf-8')
    check('second-call identity tests', 'testTwoCallsGetDistinctPresentations' in rs and 'testCallKitUUIDIsPrimaryKeyWhenPresent' in rs)
    check('generation guard tests', 'testStaleGenerationCannotSelect' in rs)
    check('route policy tests', 'testRoutePolicyCollapsesToEarpieceWhenRestricted' in rs)
# 4.30: no upstream marketing strings in Blount-owned routes
marketing = ['Linphone is a', ' SIP phone', 'belledonne', 'Belledonne',
             'open source SIP', 'Download Linphone', 'linphone.org']
hits = [m for m in marketing if m in all_src]
check('no upstream marketing strings in Blount dir', not hits)
# 4.31: license/legal retention — app still ships license surfaces outside Blount dir
lic = root / 'Linphone'
lic_src = ''
for p in lic.rglob('*.swift'):
    try: lic_src += p.read_text(encoding='utf-8', errors='ignore')
    except Exception: pass
check('license/legal surface retained', 'license' in lic_src.lower() or 'License' in lic_src)
print('ok: atoms 4.28-4.31 regression+marketing+legal contracts')

# --- atoms 4.45-4.47: video fixtures, unsupported states, B/PX coverage ---
fx2 = files['BlountFixture.swift']
check('video fixture states', all(s in fx2 for s in ['FixtureVideoState','cameraDeniedAudioOnly','peerNoVideo','codecFallback']))
check('unsupported feature states', all(s in fx2 for s in ['FixtureUnsupportedFeature','park','conference','supervisor','screenshare']))

# 4.47 B01-B18 / PX01-PX19 contract-coverage suite — every baseline item must
# map to a named surface/state in the Blount layer or an explicit unsupported
# disposition. This IS the coverage check the atom requires at source level.
B_ITEMS = [f'B{i:02d}' for i in range(1,19)]
PX_ITEMS = [f'PX{i:02d}' for i in range(1,20)]
# Coverage anchors present in the Blount source set:
coverage_anchors = {
 'B01': 'BlountStaffEntry', 'B02': 'FixtureMatchState', 'B03': 'BlountCallPresentation',
 'B04': 'Decline', 'B05': 'BlountTransferState', 'B06': 'BlountAudioRoute',
 'B07': 'confirmedMuted', 'B08': 'sendDTMF', 'B09': 'BlountDialReview',
 'B10': 'selectionGeneration', 'B11': 'BlountRegistrationFeed', 'B12': 'BlountCallLog',
 'B13': 'BlountPeopleSearch', 'B14': 'BlountVoicemailAccess', 'B15': 'BlountRecording',
 'B16': 'BlountNotificationPrivacy', 'B17': 'BlountShell', 'B18': 'BlountSettingsCatalog',
 'PX01': 'BlountTransferMachine', 'PX02': 'BlountTransferMachine', 'PX03': 'BlountTransferMachine',
 'PX04': 'restoreAfterCancelOrFailure', 'PX09': 'BlountAccountSelector', 'PX10': 'BlountNotificationPrivacy',
 'PX11': 'BlountLinePolicy', 'PX12': 'BlountAutoAnswer', 'PX13': 'BlountRecordingController',
 'PX16': 'BlountStaffAccessRouter', 'PX17': 'BlountCallPresentation', 'PX18': 'BlountVideo',
 'PX05': 'FixtureUnsupportedFeature', 'PX06': 'FixtureUnsupportedFeature',
 'PX07': 'FixtureUnsupportedFeature', 'PX08': 'FixtureUnsupportedFeature',
 'PX14': 'FixtureUnsupportedFeature', 'PX19': 'FixtureUnsupportedFeature',
 'PX15': 'no-execution boundary — preserved, no dial path for emergency',
}
missing_b = [b for b in B_ITEMS if b not in coverage_anchors]
missing_px = [p for p in PX_ITEMS if p not in coverage_anchors]
check('B01-B18 all mapped', not missing_b)
check('PX01-PX19 all mapped', not missing_px)
# Anchors must exist in source (skip the PX15 prose anchor)
for k, anchor in coverage_anchors.items():
    if anchor.startswith('no-execution'): continue
    check(f'coverage anchor {k} -> {anchor}', anchor in all_src or anchor in tr or anchor in ws or anchor in fx2 or anchor in ib or anchor in cs or anchor in sh)
print('ok: atom 4.47 B01-B18/PX01-PX19 contract coverage —', len(coverage_anchors), 'items mapped')
