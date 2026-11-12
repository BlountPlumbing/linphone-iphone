//
//  BlountCredentialStore.swift
//  Atom 5.05 — native credential store bound to the admitted Keychain policy.
//  Stores ONLY the server-issued session bearer token (blount.pbx.phone.session).
//  Never stores SIP passwords, AOR secrets, APNs tokens, or PBX credentials —
//  those remain in the engine's own secure surfaces. Device-bound access
//  control + revocation = delete; a revoked session purges the token so the
//  next request fails closed (server verify() is the authority regardless).
//

import Foundation
import Security

enum BlountKeychainError: Error {
	case storeFailed(OSStatus)
	case notFound
}

@MainActor
final class BlountCredentialStore {
	static let shared = BlountCredentialStore()
	private init() {}

	private let service = "net.blount.phone.session"
	private let account = "phone-session-token"

	/// Persist the session token issued by /phone/session endpoints.
	/// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — survives reboot,
	/// never migrates to another device, never enters iCloud Keychain.
	func storeSessionToken(_ token: String) throws {
		guard let data = token.data(using: .utf8) else { return }
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		SecItemDelete(query as CFDictionary)
		var add = query
		add[kSecValueData as String] = data
		add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		let status = SecItemAdd(add as CFDictionary, nil)
		guard status == errSecSuccess else { throw BlountKeychainError.storeFailed(status) }
	}

	/// Read the token for Authorization: Bearer — nil when absent/revoked-purged.
	func sessionToken() -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var item: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
			  let data = item as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	/// Revocation path — purge the token so subsequent requests fail closed.
	/// The server remains the authority; this is the client-side consequence.
	func purgeSessionToken() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		SecItemDelete(query as CFDictionary)
	}

	/// Atom 5.06 hook — call when the server reports the session revoked:
	/// purge locally so cached state cannot outlive authority.
	func handleRevocation() {
		purgeSessionToken()
	}
}
