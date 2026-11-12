//
//  BlountCallPresentation.swift
//  Atom 4.01 — call presentation state keyed by SDK call ID and CallKit UUID.
//  One entry per engine call; CallKit UUID and Linphone call-log ID are both
//  retained so CallKit actions and SDK events reconcile to the same record.
//

import Foundation
import SwiftUI
import linphonesw

/// Lifecycle phases the Blount call presenter renders. Labels are derived
/// only from engine-confirmed state — never optimistic.
enum BlountCallPhase: String {
	case incoming            // ringing locally, not yet answered
	case outgoingDialing     // CallKit startCall accepted, not yet connecting
	case connecting          // engine connecting (Call.State.OutgoingProgress/IncomingReceived early)
	case active              // StreamsRunning confirmed
	case held                // engine-confirmed Paused
	case ending
	case ended
	case failed
	case answeredElsewhere   // CallKit/another device took the call
	case cancelled           // caller cancelled before answer
}

/// Presentation record for exactly one call. `id` is the CallKit UUID when
/// present (system-call identity), falling back to the SDK call ID.
struct BlountCallPresentation: Identifiable, Equatable {
	var sdkCallID: String?
	var callKitUUID: UUID?

	var id: String { callKitUUID?.uuidString ?? sdkCallID ?? UUID().uuidString }

	var phase: BlountCallPhase = .incoming
	var displayName: String = ""
	var remoteAddress: String = ""
	var isOutgoing = false
	var hasVideo = false
	var muted = false
	var onHold = false
	var audioRouteLabel: String = ""
	/// Set when a second call displaces this one; original-call recovery strip.
	var displacedByCallID: String?
	/// Transfer lifecycle — local method return is NOT remote completion.
	var transferState: BlountTransferState = .idle
	var contextGeneration = 0
	var updatedAt = Date()

	static func == (l: BlountCallPresentation, r: BlountCallPresentation) -> Bool {
		l.id == r.id && l.phase == r.phase && l.muted == r.muted && l.onHold == r.onHold
			&& l.audioRouteLabel == r.audioRouteLabel && l.transferState == r.transferState
			&& l.displacedByCallID == r.displacedByCallID && l.contextGeneration == r.contextGeneration
	}
}

enum BlountTransferState: String, Equatable {
	case idle
	case destinationReview      // deliberate destination review open
	case requested              // transfer method invoked
	case pending                // consultation/negotiation in flight
	case remoteConfirmed        // engine/PBX confirmed completion
	case failed
	case cancelled
}

/// Store owning all live call presentations. Keyed by stable call identity;
/// CallKit UUID is the primary key when the system reported the call.
@MainActor
final class BlountCallPresentationStore: ObservableObject {
	@Published private(set) var calls: [String: BlountCallPresentation] = [:]
	/// Most recent call for strip/banner display.
	@Published private(set) var keyCallID: String?

	static let shared = BlountCallPresentationStore()

	/// Select a call as the key call (drives strip/banner + return target).
	func select(sdkCallID: String) {
		keyCallID = sdkCallID
	}

	func upsert(_ p: BlountCallPresentation) {
		var p = p
		p.updatedAt = Date()
		calls[p.id] = p
		keyCallID = p.id
	}

	func update(_ id: String, _ mutate: (inout BlountCallPresentation) -> Void) {
		guard var p = calls[id] else { return }
		mutate(&p)
		calls[id] = p
	}

	func remove(_ id: String) {
		calls.removeValue(forKey: id)
		if keyCallID == id { keyCallID = calls.keys.last }
	}

	func call(id: String) -> BlountCallPresentation? { calls[id] }
	func call(sdkCallID: String) -> BlountCallPresentation? {
		calls.values.first { $0.sdkCallID == sdkCallID }
	}
	func call(callKitUUID: UUID) -> BlountCallPresentation? {
		calls.values.first { $0.callKitUUID == callKitUUID }
	}

	/// Engine event entry point — invoked from TelecomManager.onCallStateChanged.
	/// Maps SDK state (+ CallKit binding) into the keyed presentation record.
	func ingestEngineEvent(call: Call, state: Call.State) {
		let sdkId = call.callLog?.callId ?? ""
		let uuid = BlountCallEventMapper.callKitUUID(forSdkCallID: sdkId)
		let existing = call(sdkCallID: sdkId) ?? (uuid.flatMap { call(callKitUUID: $0) })
		let wasConnected = existing?.phase == .active || existing?.phase == .held
		let phase = BlountCallEventMapper.phase(for: state, wasConnected: wasConnected)

		if phase == .ended || phase == .cancelled || phase == .failed || phase == .answeredElsewhere {
			if let id = existing?.id { update(id) { $0.phase = phase } ; scheduleRemoval(id) }
			return
		}

		var p = existing ?? BlountCallPresentation(sdkCallID: sdkId.isEmpty ? nil : sdkId,
												 callKitUUID: uuid)
		p.sdkCallID = sdkId.isEmpty ? p.sdkCallID : sdkId
		p.callKitUUID = uuid ?? p.callKitUUID
		p.phase = phase
		if let remote = call.remoteAddress {
			let addr = remote.asStringUriOnly()
			if !addr.isEmpty {
				p.remoteAddress = addr
				if p.displayName.isEmpty { p.displayName = addr }
			}
		}
		p.isOutgoing = call.dir == .Outgoing
		p.hasVideo = call.currentParams?.videoEnabled ?? false
		upsert(p)
	}

	private func scheduleRemoval(_ id: String) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
			self?.remove(id)
		}
	}
}
