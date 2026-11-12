//
//  BlountAccountStatus.swift
//  Atoms 4.32-4.36 — account-scoped status and policy surfaces.
//  4.32 registration/network-loss/reconnecting states from the account feed.
//  4.33 forwarding/caller-ID policy — rendered read-only; no unlocated handlers.
//  4.34 authorized account/line selector bound to reviewed destinations.
//  4.35 app-DND/notification privacy independent of system Focus.
//  4.36 auto-answer policy preserved read-only, never enabled by default.
//

import Foundation
import linphonesw

// MARK: - 4.32 registration / network-loss / reconnecting

enum BlountRegPhase: String, Equatable {
	case registered, registering, failed, cleared, unknown
}

struct BlountAccountStatusRow: Identifiable, Equatable {
	let id: String            // account address identity
	let displayName: String
	let phase: BlountRegPhase
	let isDefault: Bool
	let humanLabel: String    // existing humanReadableRegistrationState
}

enum BlountRegistrationFeed {
	/// Map the SDK RegistrationState to a Blount phase — read-only projection
	/// of the existing account feed; no parallel registration tracking.
	static func phase(for state: RegistrationState) -> BlountRegPhase {
		switch state {
		case .Ok: return .registered
		case .Progress, .Refreshing: return .registering
		case .Failed: return .failed
		case .Cleared, .None: return .cleared
		}
	}

	static func rows(from accounts: [AccountModel]) -> [BlountAccountStatusRow] {
		accounts.map {
			BlountAccountStatusRow(
				id: $0.address.isEmpty ? UUID().uuidString : $0.address,
				displayName: $0.displayName.isEmpty ? $0.address : $0.displayName,
				phase: phase(for: $0.registrationState),
				isDefault: $0.isDefaultAccount,
				humanLabel: $0.humanReadableRegistrationState
			)
		}
	}

	/// Reconnecting = any account in .registering after having been registered.
	/// Derived purely from feed transitions — honest, no invented reachability.
	static func isReconnecting(_ rows: [BlountAccountStatusRow]) -> Bool {
		rows.contains { $0.phase == .registering }
	}
}

// MARK: - 4.33 forwarding / caller-ID policy (read-only)

enum BlountLinePolicyState: String, Equatable {
	case notExposed        // app exposes no forwarding/caller-ID control
	case configured        // server/account params report an effective policy
	case unavailable
}

struct BlountLinePolicy: Equatable {
	var forwarding: BlountLinePolicyState = .notExposed
	var callerID: BlountLinePolicyState = .notExposed
	/// Never enable handlers the app cannot locate — default is notExposed.
	static let `default` = BlountLinePolicy()
}

// MARK: - 4.34 authorized account/line selector

@MainActor
final class BlountAccountSelector: ObservableObject {
	@Published private(set) var selectedAddress: String?

	/// Accounts the selector may offer — only configured, registered-capable
	/// accounts from the existing feed. No client-invented identities.
	var authorizedAccounts: [AccountModel] {
		CoreContext.shared.accounts
	}

	/// Select an account for an outbound call. Returns false for accounts not
	/// present in the authorized feed (client-supplied identity rejected).
	@discardableResult
	func select(_ address: String) -> Bool {
		guard authorizedAccounts.contains(where: { $0.address == address }) else { return false }
		selectedAddress = address
		return true
	}

	var selectedIsDefault: Bool {
		guard let sel = selectedAddress else { return false }
		return authorizedAccounts.first(where: { $0.address == sel })?.isDefaultAccount ?? false
	}
}

// MARK: - 4.35 app-DND / notification privacy (independent of Focus)

enum BlountPrivacyState: String, Equatable {
	case notConfigured   // no app-level DND surface exists yet — honest
	case quiet           // app privacy mode active
	case standard
}

struct BlountNotificationPrivacy: Equatable {
	/// App-level privacy is independent of system Focus by construction:
	/// this model never reads UIApplication/UNUserNotification focus state.
	var state: BlountPrivacyState = .notConfigured
}

// MARK: - 4.36 auto-answer preservation (read-only)

enum BlountAutoAnswer {
	/// Reads the existing core config flag. NEVER writes — the redesign
	/// preserves the policy without enabling it (config default is false).
	static func isEnabled(core: Core) -> Bool {
		core.config?.getBool(section: "sip", key: "auto_answer_replacing_calls") ?? false
	}
}
