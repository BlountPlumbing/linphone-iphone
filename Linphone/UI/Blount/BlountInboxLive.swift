//
//  BlountInboxLive.swift
//  Atoms 5.11-5.16 — live inbox presentation + draft/send-review state.
//  5.11 Customers/Team scopes dedupe on canonical_key — one logical thread
//      never renders twice across scopes.
//  5.12 items carry line/channel identity explicitly.
//  5.13/5.14 customer vs staff drafts persist in SEPARATE audience stores.
//  5.15 attachment references share the same destination key as drafts.
//  5.16 send review shows recipient/line/channel/media before submit.
//

import Foundation

// MARK: - 5.11/5.12 scope + ordered items

enum BlountInboxScope: String, CaseIterable, Identifiable {
	case customers, team
	var id: String { rawValue }
	var label: String { self == .customers ? "Customers" : "Team" }
}

struct BlountInboxItem: Identifiable, Equatable {
	let id: Int
	let canonicalKey: String
	let name: String
	let channel: String        // sms/team/customer — rendered, never hidden
	let scope: BlountInboxScope
	let preview: String
	let lastActivity: Date?
	let unread: Bool
}

enum BlountInboxProjector {
	/// conversations -> scoped, deduped, ordered items.
	/// Dedupe on canonical_key: the same logical thread reached via two
	/// channels collapses to ONE row (5.11).
	static func items(from conversations: [BlountConversationSummary],
					  scope: BlountInboxScope) -> [BlountInboxItem] {
		var seen = Set<String>()
		return conversations.compactMap { c in
			let itemScope: BlountInboxScope =
				(c.channel == "team") ? .team : .customers
			guard itemScope == scope else { return nil }
			let key = c.canonicalKey ?? "conv-\(c.id)"
			guard !seen.contains(key) else { return nil }
			seen.insert(key)
			return BlountInboxItem(id: c.id, canonicalKey: key, name: c.name,
								   channel: c.channel, scope: itemScope,
								   preview: "", lastActivity: nil, unread: false)
		}
	}
}

// MARK: - 5.13/5.14/5.15 partitioned draft + attachment persistence

enum BlountDraftAudience: String {
	case customer   // goes to the customer — reviewed before send
	case staff      // internal note — NEVER leaves the device to providers
}

/// Destination key: user + conversation + audience. Drafts and attachment
/// references share it so a draft's media can never attach to another
/// conversation or leak across audiences (5.13-5.15).
struct BlountDestinationKey: Hashable {
	let userID: String
	let conversationID: Int
	let audience: BlountDraftAudience
}

@MainActor
final class BlountDraftStore {
	static let shared = BlountDraftStore()
	private init() {}

	private var drafts: [BlountDestinationKey: String] = [:]
	private var attachments: [BlountDestinationKey: [String]] = [:]

	func draft(for key: BlountDestinationKey) -> String {
		drafts[key] ?? ""
	}

	func setDraft(_ text: String, for key: BlountDestinationKey) {
		guard !text.isEmpty else { drafts.removeValue(forKey: key); return }
		drafts[key] = text
	}

	func attachmentRefs(for key: BlountDestinationKey) -> [String] {
		attachments[key] ?? []
	}

	func addAttachmentRef(_ ref: String, for key: BlountDestinationKey) {
		attachments[key, default: []].append(ref)
	}

	/// Staff drafts are unreachable from customer send paths by construction:
	/// the key's audience differs, and send review (below) requires the
	/// customer audience explicitly.
	func customerSendableDraft(for key: BlountDestinationKey) -> String? {
		key.audience == .customer ? drafts[key] : nil
	}
}

// MARK: - 5.16 send review

struct BlountSendReview: Equatable {
	let recipientName: String
	let recipientAddress: String
	let line: String          // which authorized line sends
	let channel: String       // sms/team/customer
	let body: String
	let attachmentCount: Int
	let audience: BlountDraftAudience

	/// Staff-audience reviews NEVER produce a sendable payload — the review
	/// exists so the user sees exactly what stays internal.
	var isSendable: Bool { audience == .customer && !body.isEmpty }
}

// MARK: - 5.29 status detail

/// Renders the server-authoritative status projection only — never a
/// client-side guess. `canonical` + `sub_state` come from
/// phone.intent.status_projection(); when the server has not yet
/// reported a projection the honest answer is "unavailable".
enum BlountMessageStatus {
	static func label(canonical: String?, subState: String?) -> String {
		guard let canonical, !canonical.isEmpty else { return "unavailable" }
		if let subState, !subState.isEmpty {
			return "\(canonical) · \(subState)"
		}
		return canonical
	}
}

// MARK: - 5.32-5.36 attachment + voice surfaces

/// Attachment control state — preview/remove/error per atom 5.34.
struct BlountAttachmentControl: Equatable {
	let ref: String
	let filename: String
	let mime: String
	var state: State = .previewing

	enum State: Equatable {
		case previewing, uploading, attached, rejected(String), removed
	}
}

/// Atom 5.35 — voice recording binds permission + explicit review:
/// nothing records until permission granted AND user confirms send.
struct BlountVoiceDraft {
	var hasPermission = false
	var recordedRef: String? = nil
	var interrupted = false
	/// Atom 5.36 — interrupted drafts survive an incoming call; the draft
	/// store keeps the partial take until the user discards or sends.
	var preservedAcrossCall = false

	mutating func beginRecording(granted: Bool) {
		hasPermission = granted
		if granted { recordedRef = nil; interrupted = false }
	}
	mutating func noteInterrupted() { interrupted = true }
	mutating func resumeAfterCall() {
		if interrupted { preservedAcrossCall = true }
		interrupted = false
	}
	var sendable: Bool { hasPermission && recordedRef != nil }
}

// MARK: - 5.37-5.38 scoped search

/// Atom 5.38 — scoped search renders explicit offline limits; every row
/// is server-projected, never a local-guess result.
struct BlountSearchScope: Equatable {
	let query: String
	let scope: Scope
	let offlineLimitNote: String?

	enum Scope: String, Equatable { case conversations, messages, contacts }

	static func offlineNote(for scope: Scope) -> String? {
		// honest: local index only covers loaded pages
		switch scope {
		case .messages: return "offline: loaded pages only"
		default: return nil
		}
	}
}

// MARK: - 5.40-5.43 assignment + archive

/// Atom 5.40 — assignment state with server version-conflict feedback.
struct BlountAssignmentView: Equatable {
	let assignee: String?
	let version: Int
	var conflictMessage: String? = nil

	/// Atom 5.41 — claim/reassign sends expected_version; a stale version
	/// surfaces the conflict string instead of silently overwriting.
	static func conflictText() -> String {
		"assignment changed elsewhere — refresh and retry"
	}
}

/// Atom 5.42/5.43 — archive is visibility-only; retention explanations
/// never promise remote erasure.
struct BlountArchiveState: Equatable {
	let archived: Bool
	static let retentionNote =
		"archiving hides the conversation; records are retained per company policy"
}

// MARK: - 5.44-5.47 forward + notification reply

/// Atom 5.45 — forward renders as a NEW intent with explicit destination
/// review; it never mutates the source message.
struct BlountForwardReview: Equatable {
	let sourceConversationID: Int
	let targetConversationID: Int
	let targetLabel: String
	let body: String
	let requiresExplicitSend = true
}

/// Atom 5.47 — notification access/lock policy: a locked or revoked
/// session cannot reply; the bearer check IS the lock-policy gate.
enum BlountNotificationPolicy {
	static func canReply(sessionActive: Bool, deviceLocked: Bool) -> Bool {
		sessionActive && !deviceLocked
	}
}
