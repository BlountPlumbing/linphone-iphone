//
//  BlountCallContextBridge.swift
//  Atom 6.02 — CallKit reporting MUST precede customer lookup.
//  Atom 6.03 — guarded mustReport measurement harness for the T-7 run.
//

import Foundation

/// Ordering guarantee: the incoming-call report to CallKit completes
/// (or fails) BEFORE any customer-brief request is issued. The brief
/// key carries the CallKit UUID — the same identity the report used.
@MainActor
final class BlountCallContextBridge {
	static let shared = BlountCallContextBridge()
	private init() {}

	/// States the harness records for the T-7 device measurement.
	struct Measurement: Equatable {
		var callKitReported = false
		var lookupStartedAfterReport = false
		var briefAppliedToLiveCall = false
		var lateResponseDiscarded = false
	}
	private(set) var measurement = Measurement()

	/// Call once reportIncomingCall's completion fires (ProviderDelegate
	/// line ~113). Until this is true, requestBrief refuses to start —
	/// a brief can never race ahead of the system call report.
	func markCallKitReported() {
		measurement.callKitReported = true
	}

	func mayStartLookup() -> Bool { measurement.callKitReported }

	/// Atom 6.03 — guarded harness: records ordering facts only; the
	/// actual mustReport timing measurement runs on-device in T-7.
	func recordLookupStart() {
		measurement.lookupStartedAfterReport = mayStartLookup()
	}
	func recordBriefApplied() { measurement.briefAppliedToLiveCall = true }
	func recordLateDiscard() { measurement.lateResponseDiscarded = true }

	func reset() { measurement = Measurement() }
}
