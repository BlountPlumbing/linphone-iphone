//
//  BlountDialReview.swift
//  Atoms 4.11-4.13 — deliberate destination review for outbound calls.
//  4.11 review model: raw keypad input → classified destination → explicit Call.
//  4.12 validation: extension OR full E.164; NEVER last-digit/prefix matching.
//  4.13 keypad Call action binds the REVIEWED destination to TelecomManager.startCall.
//

import Foundation
import linphonesw

/// A validated outbound destination. Produced only by BlountDialReviewModel.
struct BlountDialDestination: Equatable {
	enum Kind: String {
		case ext        // short internal extension
		case e164       // full international number, +-prefixed
		case sipURI     // complete sip: URI entered deliberately
	}
	let kind: Kind
	/// Normalized address passed to TelecomManager.startCall.
	let address: String
	/// Human-facing review line (what the user confirms before Call).
	let reviewLabel: String
}

enum BlountDialValidator {
	/// Classify + validate keypad input. Returns nil when ambiguous/invalid.
	/// Rules are exact — no suffix/prefix guessing, no last-digit completion.
	static func validate(_ raw: String) -> BlountDialDestination? {
		let trimmed = raw.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return nil }

		// Complete SIP URI — deliberate, reviewed verbatim.
		if trimmed.lowercased().hasPrefix("sip:") {
			guard trimmed.count > 4, !trimmed.contains(" ") else { return nil }
			return BlountDialDestination(kind: .sipURI, address: trimmed,
										 reviewLabel: "SIP: \(trimmed)")
		}

		let allowed = CharacterSet(charactersIn: "0123456789*#+")
		guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

		// E.164: leading + then 8...15 digits (ITU-T max). Exact length required.
		if trimmed.hasPrefix("+") {
			let digits = trimmed.dropFirst()
			guard digits.allSatisfy({ $0.isNumber }), (8...15).contains(digits.count) else { return nil }
			return BlountDialDestination(kind: .e164, address: trimmed,
										 reviewLabel: trimmed)
		}

		// Extension: 2...6 digits, optionally *-prefixed service codes.
		// Exact-length rule only — a 7+ digit string is NOT an extension and
		// is rejected rather than silently truncated or prefix-matched.
		let digitCount = trimmed.filter { $0.isNumber }.count
		if (2...6).contains(digitCount), trimmed.allSatisfy({ $0.isNumber || $0 == "*" || $0 == "#" }) {
			return BlountDialDestination(kind: .ext, address: trimmed,
										 reviewLabel: "Extension \(trimmed)")
		}

		// National-format numbers without + are ambiguous — reject rather than guess.
		return nil
	}
}

/// Review state for one outbound dialing attempt.
@MainActor
final class BlountDialReviewModel: ObservableObject {
	@Published private(set) var input = ""
	/// The reviewed destination — set only after validate(); nil until then.
	@Published private(set) var reviewed: BlountDialDestination?
	@Published private(set) var validationMessage: String?

	func appendKey(_ key: String) {
		guard input.count < 32 else { return }
		input += key
		reviewed = nil
		validationMessage = nil
	}

	func deleteKey() {
		guard !input.isEmpty else { return }
		input.removeLast()
		reviewed = nil
		validationMessage = nil
	}

	/// Atom 4.12 — validate produces the reviewed destination or an honest message.
	@discardableResult
	func review() -> BlountDialDestination? {
		if let d = BlountDialValidator.validate(input) {
			reviewed = d
			validationMessage = nil
			return d
		}
		reviewed = nil
		validationMessage = input.isEmpty ? nil :
			"Enter an extension (2–6 digits) or a full +country number."
		return nil
	}

	/// Atom 4.13 — Call binds ONLY the reviewed destination, never raw input.
	/// Returns the address to pass to TelecomManager.startCall, or nil if unreviewed.
	func commitCallAddress() -> String? {
		reviewed?.address
	}

	func reset() {
		input = ""
		reviewed = nil
		validationMessage = nil
	}
}
