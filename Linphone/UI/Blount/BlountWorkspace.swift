//
//  BlountWorkspace.swift
//  Atoms 4.20-4.21 — workspace settings surface + staff-access routing.
//  4.20 reduced Settings/help/legal set: only admitted rows render.
//  4.21 staff entry routes through the staff-access module INTERFACE;
//       the module is HELD until the owner admits it — the router reports
//       .held honestly instead of simulating sign-in.
//

import Foundation

// MARK: - 4.20 reduced Settings/help/legal set

enum BlountSettingsRowKind {
	case status        // service/connection status
	case privacy       // preview/privacy controls
	case help          // help/procedures
	case legal         // license/legal notices (retained)
	case staffAccess   // staff sign-in entry
	case signOut
	case unavailable   // row exists in spec but capability not admitted
}

struct BlountSettingsRow: Identifiable, Equatable {
	let id: String
	let title: String
	let subtitle: String
	let kind: BlountSettingsRowKind
	/// Rows render disabled with this note when their capability is not admitted.
	var unavailableNote: String? = nil
}

/// The approved reduced set — no upstream marketing, no invented entries.
enum BlountSettingsCatalog {
	static let rows: [BlountSettingsRow] = [
		.init(id: "status", title: "Connection status",
			  subtitle: "Call and message service state", kind: .status),
		.init(id: "privacy", title: "Preview privacy",
			  subtitle: "What appears on lock screen and notifications", kind: .privacy),
		.init(id: "permissions", title: "Permissions help",
			  subtitle: "Microphone, camera, notifications", kind: .help),
		.init(id: "legal", title: "Licenses and legal",
			  subtitle: "Open-source notices and terms", kind: .legal),
		.init(id: "staff", title: "Staff access",
			  subtitle: "Company sign-in for staff features", kind: .staffAccess),
		.init(id: "signout", title: "Sign out",
			  subtitle: "Remove this device from the account", kind: .signOut),
	]
}

// MARK: - 4.21 staff-access module routing

/// Admission state of the staff-access module — mirrors the HELD receipt.
enum BlountStaffAccessState: Equatable {
	case held            // contract exists, backend binding unresolved
	case admitted        // owner admitted the module; real auth available
	case denied          // policy denied this device/user
}

/// Module interface — the admitted staff-access owner implements this.
/// The app NEVER invents credentials, issuer, or endpoints behind it.
protocol BlountStaffAccessModule {
	var admissionState: BlountStaffAccessState { get }
	/// Begin the module's own sign-in flow. Only callable when admitted.
	func beginSignIn() -> Bool
}

/// Default until admission — reports HELD and refuses sign-in.
struct BlountHeldStaffAccessModule: BlountStaffAccessModule {
	let admissionState: BlountStaffAccessState = .held
	func beginSignIn() -> Bool { false }
}

/// Router — the single entry path for staff features.
/// Generic provisioning/deep-link/MDM paths must NOT reach staff functions;
/// they funnel here and get .held/.denied honestly.
@MainActor
final class BlountStaffAccessRouter {
	static let shared = BlountStaffAccessRouter()
	private var module: BlountStaffAccessModule = BlountHeldStaffAccessModule()

	private init() {}

	/// Install the admitted module when the owner delivers it.
	func install(module: BlountStaffAccessModule) {
		self.module = module
	}

	var state: BlountStaffAccessState { module.admissionState }

	/// The ONLY path to staff sign-in. Returns false while HELD/denied —
	/// callers render the unavailable state, never a fake flow.
	@discardableResult
	func requestStaffAccess() -> Bool {
		module.beginSignIn()
	}
}
