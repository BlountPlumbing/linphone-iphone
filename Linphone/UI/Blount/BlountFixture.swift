//
//  BlountFixture.swift
//  Reversible fixture-preview flag (atom 3.03) and fictional fixture data.
//  Networking is disabled by contract: fixture surfaces render only the
//  static data below — no CoreContext reads, no URLSession, no providers.
//

import Foundation

enum BlountFixtureConfig {
	static let launchArgument = "-BlountFixturePreview"
	static let environmentKey = "BLOUNT_FIXTURE_PREVIEW"

	static var isEnabled: Bool {
		ProcessInfo.processInfo.arguments.contains(launchArgument)
			|| ProcessInfo.processInfo.environment[environmentKey] == "1"
	}

	/// Fixture mode never touches the network or the SIP core.
	static let networkingAllowed = false
}

/// Customer-context match states per CUSTOMER-CONTEXT-CONTRACT.
enum FixtureMatchState: String, CaseIterable {
	case matched, ambiguous, unmatched, withheld, unavailable

	var title: String {
		switch self {
		case .matched: return "Matched"
		case .ambiguous: return "Ambiguous — choose a record"
		case .unmatched: return "No matching customer"
		case .withheld: return "Caller ID withheld"
		case .unavailable: return "Context unavailable"
		}
	}
}

struct FixtureCaller: Identifiable {
	let id = UUID()
	let displayName: String
	let number: String
	let matchState: FixtureMatchState
	let site: String?
	let lastJob: String?
	/// Staff-only section — rendered amber + labelled, never customer-visible.
	let staffNote: String?
	let balanceMinor: Int?
	let currency: String?
	let freshness: String // "Updated 2m ago" / "Cached 1h ago"
}

struct FixtureCall: Identifiable {
	let id = UUID()
	let caller: FixtureCaller?
	let direction: String // "incoming" | "outgoing" | "missed"
	let startedLabel: String
	let isRinging: Bool
}

struct FixtureMessage: Identifiable {
	let id = UUID()
	let author: String // "Customer" | "You" | "Staff note"
	let isStaffNote: Bool
	let body: String
	let time: String
}

struct FixtureThread: Identifiable {
	let id = UUID()
	let title: String
	let subtitle: String
	let messages: [FixtureMessage]
}

struct FixtureContact: Identifiable {
	let id = UUID()
	let name: String
	let role: String
	let phone: String
}

enum FixtureInboxState {
	case loading, empty, denied, ready
}

enum BlountFixtureData {
	static let callers: [FixtureCaller] = [
		FixtureCaller(displayName: "R. Alvarez — Alvarez Dental", number: "+1 (555) 014-2201",
			matchState: .matched, site: "210 Peachtree St", lastJob: "Water heater replacement — Jan 12",
			staffNote: "Prefers morning windows; gate code on file.", balanceMinor: 18750, currency: "USD",
			freshness: "Updated 2m ago"),
		FixtureCaller(displayName: "2 candidates — same number", number: "+1 (555) 014-8842",
			matchState: .ambiguous, site: nil, lastJob: nil,
			staffNote: nil, balanceMinor: nil, currency: nil,
			freshness: "Updated just now"),
		FixtureCaller(displayName: "Unknown caller", number: "+1 (555) 019-3310",
			matchState: .unmatched, site: nil, lastJob: nil,
			staffNote: nil, balanceMinor: nil, currency: nil,
			freshness: "Updated just now"),
		FixtureCaller(displayName: "Withheld number", number: "—",
			matchState: .withheld, site: nil, lastJob: nil,
			staffNote: nil, balanceMinor: nil, currency: nil,
			freshness: "Updated just now"),
		FixtureCaller(displayName: "Context service slow", number: "+1 (555) 017-0098",
			matchState: .unavailable, site: nil, lastJob: nil,
			staffNote: nil, balanceMinor: nil, currency: nil,
			freshness: "Cached 1h ago"),
	]

	static let calls: [FixtureCall] = [
		FixtureCall(caller: callers[0], direction: "incoming", startedLabel: "Now ringing", isRinging: true),
		FixtureCall(caller: callers[1], direction: "incoming", startedLabel: "2m ago", isRinging: false),
		FixtureCall(caller: callers[2], direction: "outgoing", startedLabel: "Today 8:14 AM", isRinging: false),
		FixtureCall(caller: callers[3], direction: "missed", startedLabel: "Today 7:52 AM", isRinging: false),
	]

	static let threads: [FixtureThread] = [
		FixtureThread(title: "Alvarez Dental", subtitle: "SMS · (555) 014-2201",
			messages: [
				FixtureMessage(author: "Customer", isStaffNote: false, body: "Can someone confirm tomorrow's arrival window?", time: "9:02 AM"),
				FixtureMessage(author: "You", isStaffNote: false, body: "On it — tech assigned for 8–10.", time: "9:04 AM"),
				FixtureMessage(author: "Staff note", isStaffNote: true, body: "Customer prefers AM; remind tech about gate code.", time: "9:05 AM"),
			]),
		FixtureThread(title: "Unknown caller", subtitle: "SMS · (555) 019-3310",
			messages: [
				FixtureMessage(author: "Customer", isStaffNote: false, body: "Hi, do you service tankless heaters?", time: "Yesterday"),
			]),
	]

	static let contacts: [FixtureContact] = [
		FixtureContact(name: "Alvarez Dental", role: "Customer", phone: "(555) 014-2201"),
		FixtureContact(name: "M. Okafor", role: "Technician", phone: "(555) 010-4417"),
		FixtureContact(name: "Dispatch", role: "Internal", phone: "(555) 010-2200"),
		FixtureContact(name: "Sunrise Property Mgmt", role: "Customer", phone: "(555) 016-7788"),
	]

	static let inboxStates: [FixtureInboxState] = [.loading, .empty, .denied, .ready]
}
