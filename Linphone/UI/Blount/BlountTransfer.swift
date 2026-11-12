//
//  BlountTransfer.swift
//  Atoms 4.23-4.27 — transfer lifecycle for the Blount call surface.
//  4.23 deliberate destination review reuses the dial validator.
//  4.24 consultation hold keeps the original call addressable (never lost).
//  4.25 requested/pending/remoteConfirmed/failed/cancelled state mapping —
//       a local method return is NEVER remote confirmation.
//  4.26 cancel/failure restores the original call's controls.
//  4.27 the machine is pure — event sequences are unit-testable without engine.
//

import Foundation
import linphonesw

// MARK: - 4.25 pure transfer state machine (4.27-testable)

enum BlountTransferEvent {
	case reviewOpened
	case destinationConfirmed(BlountDialDestination)
	case transferRequested          // local method invoked
	case remoteStateChanged(Call.State)
	case cancelledByUser
	case failed(String)
}

/// Pure reducer: (state, event) -> state. No engine, no UI — 4.27 tests drive it.
struct BlountTransferMachine {
	private(set) var state: BlountTransferState = .idle
	private(set) var originalCallID: String?
	private(set) var destinationAddress: String?

	/// Consultation hold is tracked separately — the original call is NEVER
	/// removed from the presentation store while a transfer is in flight (4.24).
	private(set) var consultationHeld = false

	mutating func reduce(_ event: BlountTransferEvent) {
		switch (state, event) {
		case (.idle, .reviewOpened):
			state = .destinationReview

		case (.destinationReview, .destinationConfirmed(let dest)):
			destinationAddress = dest.address
			state = .requested

		case (.requested, .remoteStateChanged(let s)):
			// Only StreamsRunning/Connected from the REMOTE side counts as
			// confirmation; Paused/End/Error map honestly.
			switch s {
			case .StreamsRunning, .Connected: state = .remoteConfirmed
			case .Paused, .PausedByRemote: state = .pending
			case .Error: state = .failed
			case .End: state = consultationHeld ? .pending : .failed
			default: state = .pending
			}

		case (.pending, .remoteStateChanged(let s)):
			switch s {
			case .StreamsRunning, .Connected: state = .remoteConfirmed
			case .End: state = .failed
			case .Error: state = .failed
			default: break
			}

		case (_, .cancelledByUser) where state != .idle && state != .remoteConfirmed:
			state = .cancelled
			consultationHeld = false

		case (_, .failed) where state != .idle && state != .remoteConfirmed:
			state = .failed
			consultationHeld = false

		case (.remoteConfirmed, _):
			break   // terminal for this machine; original call is gone by design

		case (.cancelled, .reviewOpened), (.failed, .reviewOpened):
			state = .destinationReview
			consultationHeld = false

		case (.idle, .transferRequested), (.destinationReview, .transferRequested):
			state = .requested

		default:
			break
		}
	}

	/// Begin consultation hold on the original call (4.24).
	mutating func beginConsultation(originalCallID: String) {
		self.originalCallID = originalCallID
		consultationHeld = true
		if state == .requested || state == .pending { state = .pending }
	}

	/// 4.26 — after cancel/failure the original call's controls restore:
	/// consultation hold released, machine resets to idle for next attempt.
	mutating func restoreAfterCancelOrFailure() {
		guard state == .cancelled || state == .failed else { return }
		consultationHeld = false
		originalCallID = nil
		destinationAddress = nil
		state = .idle
	}
}

// MARK: - 4.23/4.24/4.26 controller over the presentation store

@MainActor
final class BlountTransferController {
	static let shared = BlountTransferController()
	private init() {}

	@Published private(set) var machines: [String: BlountTransferMachine] = [:]

	private func machine(for sdkCallID: String) -> BlountTransferMachine {
		machines[sdkCallID] ?? BlountTransferMachine()
	}

	private func store(_ m: BlountTransferMachine, for sdkCallID: String) {
		machines[sdkCallID] = m
		// Mirror onto the presentation record (update keys on presentation id,
		// which is callKitUUID when present — resolve via sdkCallID lookup).
		if let pres = BlountCallPresentationStore.shared.call(sdkCallID: sdkCallID) {
			BlountCallPresentationStore.shared.update(pres.id) { p in
				p.transferState = m.state
				p.displacedByCallID = m.consultationHeld ? m.originalCallID : nil
			}
		}
	}

	/// 4.23 — open destination review for a call; returns validated destination.
	func reviewDestination(for sdkCallID: String) -> BlountDialDestination? {
		var m = machine(for: sdkCallID)
		m.reduce(.reviewOpened)
		store(m, for: sdkCallID)
		return nil   // caller runs BlountDialValidator, then confirmDestination()
	}

	func confirmDestination(for sdkCallID: String, _ dest: BlountDialDestination) {
		var m = machine(for: sdkCallID)
		m.reduce(.destinationConfirmed(dest))
		m.beginConsultation(originalCallID: sdkCallID)
		store(m, for: sdkCallID)
	}

	/// Local method return — NEVER treated as remote confirmation (4.25).
	func noteTransferRequested(for sdkCallID: String) {
		var m = machine(for: sdkCallID)
		m.reduce(.transferRequested)
		store(m, for: sdkCallID)
	}

	/// Remote-side Call.State from onTransferStateChanged.
	func noteRemoteState(for sdkCallID: String, _ state: Call.State) {
		var m = machine(for: sdkCallID)
		m.reduce(.remoteStateChanged(state))
		store(m, for: sdkCallID)
	}

	func cancel(for sdkCallID: String) {
		var m = machine(for: sdkCallID)
		m.reduce(.cancelledByUser)
		m.restoreAfterCancelOrFailure()
		store(m, for: sdkCallID)
	}

	func fail(for sdkCallID: String, reason: String = "") {
		var m = machine(for: sdkCallID)
		m.reduce(.failed(reason))
		m.restoreAfterCancelOrFailure()
		store(m, for: sdkCallID)
	}
}
