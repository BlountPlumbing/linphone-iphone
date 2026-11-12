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

	/// Atom 5.08 — paginated authorized conversation list.
	func conversations(limit: Int = 50, offset: Int = 0) async throws -> [BlountConversationSummary] {
		let data = try await request("blount_pbx/phone/conversations?limit=\(limit)&offset=\(offset)")
		struct Page: Decodable { let conversations: [BlountConversationSummary] }
		return try JSONDecoder().decode(Page.self, from: data).conversations
	}
}
