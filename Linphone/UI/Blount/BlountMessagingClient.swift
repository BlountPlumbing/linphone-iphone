//
//  BlountMessagingClient.swift
//  Atom 5.06 — native messaging client with revoked-session invalidation.
//  Bearer token comes ONLY from BlountCredentialStore (Keychain). Any 401 /
//  verify-false response purges the token AND clears cached messaging state —
//  a revoked session cannot keep rendering stale authority.
//

import Foundation

struct BlountSessionClaims: Decodable {
	let ok: Bool
	let user: String?
	let company: String?
	let lines: String?
	let expires_at: String?
}

struct BlountConversationSummary: Decodable, Identifiable {
	let id: Int
	let name: String
	let channel: String
	let canonicalKey: String?

	enum CodingKeys: String, CodingKey {
		case id, name, channel
		case canonicalKey = "canonical_key"
	}
}

enum BlountMessagingError: Error {
	case noSession
	case unauthorized          // -> triggers purge
	case server(Int)
	case decoding
}

@MainActor
final class BlountMessagingClient {
	static let shared = BlountMessagingClient()
	private init() {}

	/// Base URL is deployment config — never hardcoded to production here.
	var baseURL: URL? = nil   // set by admitted config; nil = unavailable

	/// Cached claims — cleared on any auth failure.
	@Published private(set) var claims: BlountSessionClaims?

	private var sessionToken: String? {
		BlountCredentialStore.shared.sessionToken()
	}

	private func request(_ path: String, method: String = "GET",
						body: [String: Any]? = nil) async throws -> Data {
		guard let base = baseURL, var comps = URLComponents(
			url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
		else { throw BlountMessagingError.server(0) }
		guard let token = sessionToken else { throw BlountMessagingError.noSession }
		var req = URLRequest(url: comps.url!)
		req.httpMethod = method
		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

		let (data, resp) = try await URLSession.shared.data(for: req)
		let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
		if status == 401 || status == 403 {
			// Atom 5.06 — revoked/expired session: purge token + claims.
			BlountCredentialStore.shared.handleRevocation()
			claims = nil
			throw BlountMessagingError.unauthorized
		}
		guard (200..<300).contains(status) else { throw BlountMessagingError.server(status) }
		return data
	}

	/// Verify the session — populates claims; unauthorized purges (5.06).
	func verifySession() async throws -> BlountSessionClaims {
		let data = try await request("blount_pbx/phone/session/verify", method: "POST")
		let parsed = try JSONDecoder().decode(BlountSessionClaims.self, from: data)
		claims = parsed.ok ? parsed : nil
		if !parsed.ok { throw BlountMessagingError.unauthorized }
		return parsed
	}

	/// Atom 5.17 — durable client intent id minted BEFORE submit and kept
	/// until the server acknowledges binding. A retry reuses the SAME id so
	/// the server's immutable binding dedupes instead of double-sending.
	func newIntentID() -> String { UUID().uuidString }

	/// Atom 5.08 — paginated authorized conversation list.
	func conversations(limit: Int = 50, offset: Int = 0) async throws -> [BlountConversationSummary] {
		let data = try await request("blount_pbx/phone/conversations?limit=\(limit)&offset=\(offset)")
		struct Page: Decodable { let conversations: [BlountConversationSummary] }
		return try JSONDecoder().decode(Page.self, from: data).conversations
	}
}

// MARK: - 5.53-5.66 native transport + envelopes + intents

/// Atom 5.54 — paginated envelope decode: server page + cursor, never
/// a bare array the client must guess at.
struct BlountConversationPage: Decodable {
	let ok: Bool
	let conversations: [BlountConversationSummary]
	let nextCursor: String?

	enum CodingKeys: String, CodingKey {
		case ok, conversations
		case nextCursor = "next_cursor"
	}
}

/// Atom 5.55 — cursor-paginated fetch: refresh passes nil cursor,
/// load-more passes the last next_cursor. Server re-checks membership
/// every page — a revoked member's cursor yields an empty page, not data.
extension BlountMessagingClient {
	func conversationsPage(cursor: String?,
	                       limit: Int = 50) async throws -> BlountConversationPage {
		var path = "blount_pbx/phone/conversations?limit=\(limit)"
		if let cursor, let enc = cursor.addingPercentEncoding(
			withAllowedCharacters: .urlQueryAllowed) {
			path += "&cursor=\(enc)"
		}
		let data = try await request(path)
		return try JSONDecoder().decode(BlountConversationPage.self, from: data)
	}

	/// Atom 5.56 — report rendered read position to the per-user cursor.
	func markRead(conversationID: Int, cursor: String) async throws {
		_ = try await request(
			"blount_pbx/phone/conversations/\(conversationID)/read",
			method: "POST",
			body: ["cursor": cursor])
	}

	/// Atom 5.57/5.58 — normalized recipient resolution. Ambiguity or
	/// unknown addresses come back unresolved; the editor must deny
	/// proceeding to a guessed conversation.
	struct RecipientResolution: Decodable {
		let ok: Bool
		let resolution: String
		let normalized: String?
	}
	func resolveRecipient(_ address: String,
	                      channel: String = "sms") async throws -> RecipientResolution {
		let data = try await request(
			"blount_pbx/phone/resolve", method: "POST",
			body: ["address": address, "channel": channel])
		return try JSONDecoder().decode(RecipientResolution.self, from: data)
	}

	/// Atom 5.59 — staged media upload; a server-side reject marks the
	/// local preview rejected and cleans the staged ref (no orphan).
	struct StagedMedia: Decodable {
		let ok: Bool
		let mediaID: Int?
		let error: String?
		enum CodingKeys: String, CodingKey {
			case ok, error
			case mediaID = "media_id"
		}
	}
	func stageMedia(conversationID: Int, filename: String, mime: String,
	                size: Int, channel: String,
	                storageRef: String) async throws -> StagedMedia {
		let data = try await request(
			"blount_pbx/phone/media/stage", method: "POST",
			body: ["conv_id": conversationID, "filename": filename,
			       "mime": mime, "size": size, "channel": channel,
			       "storage_ref": storageRef])
		return try JSONDecoder().decode(StagedMedia.self, from: data)
	}

	/// Atom 5.61 — saved replies for the picker; substitution preview is
	/// client-side against the same {field} grammar the server enforces.
	struct SavedReply: Decodable, Identifiable {
		let id: Int
		let name: String
		let fields: [String]
	}
	func savedReplies() async throws -> [SavedReply] {
		struct Page: Decodable { let ok: Bool; let saved_replies: [SavedReply] }
		let data = try await request("blount_pbx/phone/saved_replies")
		return try JSONDecoder().decode(Page.self, from: data).saved_replies
	}

	/// Atom 5.39 client — substitute {field} placeholders; a missing
	/// field denies the preview exactly like the server render would.
	static func previewSubstitution(template: String,
	                                values: [String: String]) -> String? {
		var out = template
		for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
		if out.range(of: #"\{\w+\}"#, options: .regularExpression) != nil {
			return nil   // unresolved placeholder -> deny
		}
		return out
	}

	/// Atom 5.62 — submit through the intent pipeline: durable intent id,
	/// immutable server binding, eligibility + single dispatch claim.
	struct SendResult: Decodable {
		let ok: Bool
		let state: String?
		let error: String?
		let attemptID: Int?
		enum CodingKeys: String, CodingKey {
			case ok, state, error
			case attemptID = "attempt_id"
		}
	}
	func send(conversationID: Int, intentID: String, body: String,
	          audience: String = "customer",
	          attachments: [String] = []) async throws -> SendResult {
		let data = try await request(
			"blount_pbx/phone/conversations/\(conversationID)/send",
			method: "POST",
			body: ["intent_id": intentID, "body": body,
			       "audience": audience, "attachments": attachments])
		return try JSONDecoder().decode(SendResult.self, from: data)
	}

	/// Atom 5.63/5.64 — inbound Odoo change arrives as an opaque APNs
	/// nudge; the ONLY correct response is an authenticated cursor
	/// refresh — never trust payload content, never render from it.
	func handleMessageNudge() async throws -> BlountConversationPage {
		try await conversationsPage(cursor: nil)
	}
}
