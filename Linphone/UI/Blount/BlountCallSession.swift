//
//  BlountCallSession.swift
//  Atoms 4.06-4.10 — session-level call controls.
//  4.06 manual mute intent survives forced-route muting (two flags, not one).
//  4.07 DTMF bound to SDK sendDtmf gated on StreamsRunning.
//  4.08 hold/resume confirmed via engine state transitions (Paused/StreamsRunning).
//  4.09 recovery strip exposes the held original after a second call ends.
//  4.10 second-call selection carries a context generation token.
//

import Foundation
import linphonesw

@MainActor
final class BlountCallSession {
	static let shared = BlountCallSession()
	private init() {}

	// MARK: - 4.06 mute intent vs forced mute

	/// User's explicit mute choice per call — survives route-forced muting.
	@Published private(set) var userMuteIntent: [String: Bool] = [:]
	/// Route/policy-forced mute per call (e.g. disallowed audio route).
	@Published private(set) var forcedMute: [String: Bool] = [:]

	var effectiveMuted: [String: Bool] {
		var out = userMuteIntent
		for (id, f) in forcedMute where f { out[id] = true }
		return out
	}

	func setUserMuteIntent(sdkCallID: String, muted: Bool) {
		userMuteIntent[sdkCallID] = muted
	}

	/// Forced-route handler records forced mute WITHOUT touching user intent.
	func setForcedMute(sdkCallID: String, forced: Bool) {
		forcedMute[sdkCallID] = forced
	}

	// MARK: - 4.07 DTMF

	/// Send one DTMF digit to the call — engine path identical to the dialer:
	/// sendDtmf on the core queue + playDtmf local tone; StreamsRunning only.
	func sendDTMF(sdkCallID: String, digit: CChar) {
		CoreContext.shared.doOnCoreQueue { core in
			guard let call = BlountCallSession.findCall(sdkCallID: sdkCallID, core: core),
				  call.state == .StreamsRunning else { return }
			do {
				try call.sendDtmf(dtmf: digit)
				core.playDtmf(dtmf: digit, durationMs: 200)
			} catch {
				Log.error("[BlountCallSession] DTMF \(digit) failed: \(error)")
			}
		}
	}

	// MARK: - 4.08 hold / resume (engine-confirmed)

	/// Hold or resume a call. Confirmation arrives via the state mapper:
	/// pause() → Call.State.Paused → .held; resume() → StreamsRunning → .active.
	/// The UI must render the mapped phase, never the tapped button state.
	func setHeld(sdkCallID: String, held: Bool) {
		CoreContext.shared.doOnCoreQueue { core in
			guard let call = BlountCallSession.findCall(sdkCallID: sdkCallID, core: core) else { return }
			do {
				if held { try call.pause() } else { try call.resume() }
			} catch {
				Log.error("[BlountCallSession] hold=\(held) failed: \(error)")
			}
		}
	}

	// MARK: - 4.09 original-call recovery strip

	/// After a second call ends, the held original resurfaces here.
	/// Returns the SDK call ID of the best recovery candidate, if any.
	var recoveryCandidateID: String? {
		let store = BlountCallPresentationStore.shared
		// Prefer a held call; fall back to any non-terminal presentation.
		if let held = store.calls.values.first(where: { $0.phase == .held }) {
			return held.sdkCallID
		}
		return store.calls.values
			.filter { $0.phase == .active || $0.phase == .connecting }
			.sorted { ($0.updatedAt) > ($1.updatedAt) }
			.first?.sdkCallID
	}

	// MARK: - 4.10 second-call selection context generation

	/// Monotonic generation per selection context — a stale UI closure holding
	/// an old generation cannot select a call that has since been replaced.
	@Published private(set) var selectionGeneration: [String: Int] = [:]
	private var generationCounter = 0

	/// Begin a new selection context (e.g. user taps a different call row).
	/// Returns the generation the caller must echo back on select.
	func beginSelectionContext(for sdkCallID: String) -> Int {
		generationCounter += 1
		selectionGeneration[sdkCallID] = generationCounter
		return generationCounter
	}

	/// Select a call only if the caller's generation is still current.
	@discardableResult
	func selectCall(sdkCallID: String, expectedGeneration: Int) -> Bool {
		guard selectionGeneration[sdkCallID] == expectedGeneration else { return false }
		BlountCallPresentationStore.shared.select(sdkCallID: sdkCallID)
		return true
	}

	// MARK: - shared lookup

	static func findCall(sdkCallID: String, core: Core) -> Call? {
		for c in core.calls {
			if c.callLog?.callId == sdkCallID { return c }
		}
		return nil
	}
}
