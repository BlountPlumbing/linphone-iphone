//
//  BlountCustomerBrief.swift
//  T-6 customer-context client — atoms 6.12-6.21, 6.27-6.29.
//  Contract: shared-customer-context.v1 (receipt WATCH:24.09,
//  produced sha256 be7f3340…). Brief lookup is keyed by the CallKit
//  call identity + account + auth + request generations — a late or
//  cancelled response can never resurrect a dead call's brief.
//

import Foundation

// MARK: - Contract models (6.05-6.10 field semantics)

enum BlountMatchState: String, Decodable {
	case matched, ambiguous, unmatched, withheld, unavailable
}

/// Per-section availability — omitted finance is NEVER promoted to zero.
enum BlountFieldAvailability: String, Decodable {
	case available, unavailable, permissionDenied = "permission_denied"
	case notApplicable = "not_applicable", stale
}

struct BlountBriefScope: Decodable {
	let companyID: Int
	let accountWide: Bool
	let accountID: Int?
	let siteID: Int?

	enum CodingKeys: String, CodingKey {
		case accountWide = "account_wide"
		case companyID = "company_id"
		case accountID = "account_id"
		case siteID = "site_id"
	}
}

struct BlountBriefAmount: Decodable {
	let minorUnits: Int?
	let currency: String?
	let availability: BlountFieldAvailability

	enum CodingKeys: String, CodingKey {
		case currency, availability
		case minorUnits = "minor_units"
	}
}

struct BlountCustomerBrief: Decodable {
	let schemaVersion: String
	let callID: String
	let briefRevision: Int
	let matchState: BlountMatchState
	let scope: BlountBriefScope
	let displayName: String?
	let balanceDue: BlountBriefAmount?
	let overdue: BlountBriefAmount?
	let totalPaid: BlountBriefAmount?
	let completedJobs: Int?
	let mostRecentTechnician: String?
	let dataAsOf: String?
	let expiresAt: String?
	let sections: [String: BlountFieldAvailability]?

	enum CodingKeys: String, CodingKey {
		case scope, displayName = "display_name"
		case balanceDue = "balance_due"
		case overdue
		case totalPaid = "total_paid"
		case completedJobs = "completed_jobs"
		case mostRecentTechnician = "most_recent_technician"
		case dataAsOf = "data_as_of"
		case expiresAt = "expires_at"
		case schemaVersion = "schema_version"
		case callID = "call_id"
		case briefRevision = "brief_revision"
		case matchState = "match_state"
		case sections
	}
}

// MARK: - Request lifecycle (6.12-6.17)

/// Atom 6.12 — request key binds call/account/auth/request generations.
/// A response whose key doesn't match the CURRENT generation is stale.
struct BlountBriefRequestKey: Equatable {
	let callID: String          // CallKit UUID string — stable identity
	let accountGeneration: Int  // account switch bumps this
	let authGeneration: Int     // sign-in/out bumps this
	let requestGeneration: Int  // each new lookup bumps this
}

@MainActor
final class BlountCustomerBriefClient {
	static let shared = BlountCustomerBriefClient()
	private init() {}

	/// Contract defaults (reviewable product settings, not guarantees):
	static let lookupTimeout: TimeInterval = 2.0      // 6.14
	static let financeGrantTTL: TimeInterval = 300    // 6.16 — 5 min
	static let cacheMaxLifetime: TimeInterval = 86400 // 6.15 — 24 h

	private var currentKey: BlountBriefRequestKey?
	private var pending: Task<BlountCustomerBrief?, Never>?

	/// Dated service cache — survives within 24h ONLY while authorized;
	/// finance fields additionally require an unexpired 5-min grant.
	private struct CacheEntry {
		let brief: BlountCustomerBrief
		let storedAt: Date
		var financeGrantExpiresAt: Date?
	}
	private var cache: [String: CacheEntry] = [:]   // keyed by callID

	/// Atom 6.16/6.17 — finance grant + purge on revocation.
	func noteRevocation() {
		cache.removeAll()
		currentKey = nil
		pending?.cancel()
		pending = nil
	}

	/// Atom 6.12-6.15 — issue a brief request. Returns nil on timeout,
	/// stale generation, or transport failure — callers render the
	/// contract's unavailable states, never a fabricated brief.
	@discardableResult
	func requestBrief(callID: String,
	                  accountGeneration: Int,
	                  authGeneration: Int,
	                  transport: @escaping (String) async throws -> BlountCustomerBrief?) async -> BlountCustomerBrief? {
		let key = BlountBriefRequestKey(
			callID: callID, accountGeneration: accountGeneration,
			authGeneration: authGeneration,
			requestGeneration: (currentKey?.requestGeneration ?? 0) + 1)
		currentKey = key
		pending?.cancel()

		// serve dated cache immediately if still authorized (CC contract)
		if let entry = cache[callID],
		   Date().timeIntervalSince(entry.storedAt) < Self.cacheMaxLifetime {
			return entry.brief
		}

		let task = Task<BlountCustomerBrief?, Never> { [weak self] in
			guard let self else { return nil }
			do {
				let brief = try await withThrowingTaskGroup(of: BlountCustomerBrief?.self) { group in
					group.addTask { try await transport("mobile/v1/calls/\(callID)/customer-brief") }
					group.addTask {
						try await Task.sleep(nanoseconds: UInt64(Self.lookupTimeout * 1e9))
						return nil    // 2s timeout -> unavailable, ring continues
					}
					let first = try await group.next() ?? nil
					group.cancelAll()
					return first
				}
				// atom 6.13 — discard late/cancelled responses: key must
				// still match when the response lands
				guard let brief, self.currentKey == key else { return nil }
				self.cache[callID] = CacheEntry(
					brief: brief, storedAt: Date(),
					financeGrantExpiresAt: Date().addingTimeInterval(Self.financeGrantTTL))
				return brief
			} catch {
				return nil
			}
		}
		pending = task
		return await task.value
	}

	/// Atom 6.16 — finance fields require an unexpired grant; after
	/// expiry they require online revalidation (a fresh requestBrief).
	func financeFieldsAuthorized(for callID: String) -> Bool {
		guard let entry = cache[callID],
		      let grant = entry.financeGrantExpiresAt else { return false }
		return grant > Date()
	}

	/// Atom 6.18-6.20 — render model for the ringing card.
	struct RingingCard: Equatable {
		let matchState: BlountMatchState
		let displayName: String?
		let balanceDue: String?        // pre-formatted ONLY when authorized
		let completedJobs: Int?
		let technician: String?
		let freshnessLabel: String
		let detailURL: String?

		static func unavailable() -> RingingCard {
			RingingCard(matchState: .unavailable, displayName: nil,
			            balanceDue: nil, completedJobs: nil,
			            technician: nil, freshnessLabel: "unavailable",
			            detailURL: nil)
		}
	}

	func ringingCard(for brief: BlountCustomerBrief,
	                 financeAuthorized: Bool) -> RingingCard {
		// atom 6.19 — independent unavailable/denied/zero/not-applicable
		let balance: String? = financeAuthorized
			? (brief.balanceDue?.availability == .available
			   ? formatted(brief.balanceDue) : nil)
			: nil
		return RingingCard(
			matchState: brief.matchState,
			displayName: brief.displayName,
			balanceDue: balance,
			completedJobs: brief.completedJobs,
			technician: brief.mostRecentTechnician,
			freshnessLabel: brief.dataAsOf ?? "unknown",
			detailURL: nil)   // 6.20 — authorized Odoo links land via config, never secrets
	}

	private func formatted(_ a: BlountBriefAmount?) -> String? {
		guard let a, a.availability == .available,
		      let units = a.minorUnits, let cur = a.currency else { return nil }
		return String(format: "%@ %.2f", cur, Double(units) / 100.0)
	}
}
