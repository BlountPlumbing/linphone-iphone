//
//  BlountAccountAccess.swift
//  Atoms 4.16-4.19 — account-scoped access surfaces.
//  4.16 voicemail badge bound to the existing MWI feed (AccountModel.voicemailCount).
//  4.17 Call mailbox dials ONLY account.params.voicemailAddress (server-configured).
//  4.18 People search behind a provider protocol — server-authoritative results
//       only; the default provider honestly reports unavailable (no invented API).
//  4.19 Manual dialing stays available when Contacts permission is denied.
//

import Foundation
import Contacts

// MARK: - 4.16/4.17 voicemail

@MainActor
final class BlountVoicemailAccess {
	static let shared = BlountVoicemailAccess()
	private init() {}

	/// Badge count = sum of MWI new-message counts across configured accounts.
	/// Reads the existing AccountModel feed — no parallel MWI tracking.
	var waitingMessageCount: Int {
		CoreContext.shared.accounts.reduce(0) { $0 + $1.voicemailCount }
	}

	/// Whether any account has a server-configured voicemail URI.
	var mailboxConfigured: Bool {
		CoreContext.shared.accounts.contains { $0.account.params?.voicemailAddress != nil }
	}

	/// Atom 4.17 — dial the configured mailbox through the EXISTING path
	/// (AccountModel.callVoicemailUri → TelecomManager.doCallOrJoinConf).
	/// Returns false when no authorized mailbox URI exists — caller shows
	/// the unavailable label rather than guessing a number.
	@discardableResult
	func callMailbox() -> Bool {
		guard let account = CoreContext.shared.accounts.first(where: {
			$0.account.params?.voicemailAddress != nil
		}) else { return false }
		account.callVoicemailUri()
		return true
	}
}

// MARK: - 4.18 server-authoritative People search

struct BlountPersonResult: Identifiable, Equatable {
	let id: String
	let displayName: String
	let address: String
	let subtitle: String
}

enum BlountPeopleSearchState: Equatable {
	case idle
	case loading
	case results([BlountPersonResult])
	case unavailable   // provider cannot serve — honest empty state
	case denied         // authorization/policy denied
}

/// Provider contract: results come ONLY from the admitted backend.
/// No client-side contact scraping substitutes for server authority.
protocol BlountPeopleSearchProvider {
	func search(query: String) async -> BlountPeopleSearchState
}

/// Default until the staff/backend authority is admitted (HELD per T-2 2.29).
struct BlountUnavailablePeopleSearch: BlountPeopleSearchProvider {
	func search(query: String) async -> BlountPeopleSearchState { .unavailable }
}

@MainActor
final class BlountPeopleSearch: ObservableObject {
	@Published private(set) var state: BlountPeopleSearchState = .idle
	private let provider: BlountPeopleSearchProvider

	init(provider: BlountPeopleSearchProvider = BlountUnavailablePeopleSearch()) {
		self.provider = provider
	}

	func search(_ query: String) async {
		let q = query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { state = .idle; return }
		state = .loading
		state = await provider.search(query: q)
	}
}

// MARK: - 4.19 contacts-denied manual dial

enum BlountContactsAccess {
	static var authorizationStatus: CNAuthorizationStatus {
		CNContactStore.authorizationStatus(for: .contacts)
	}

	/// Manual dialing (BlountDialReviewModel) has zero Contacts dependency —
	/// it stays fully available in every authorization state.
	static var manualDialAvailable: Bool { true }

	static var denied: Bool {
		authorizationStatus == .denied || authorizationStatus == .restricted
	}
}
