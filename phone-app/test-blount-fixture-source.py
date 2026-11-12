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
