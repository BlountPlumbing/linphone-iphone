//
//  BlountCallEvents.swift
//  Atoms 4.02-4.03 — map engine/CallKit call events to presentation state.
//  Pure functions: no UIKit/CallKit types cross the boundary except UUID.
//  A local method return is never treated as remote confirmation.
//

import Foundation
import linphonesw

/// CallKit-side context the mapper needs beyond the SDK state.
enum BlountCallKitContext {
	case none
	case answeredElsewhere   // CXAnswerCallAction on another device / provider end
	case cancelledByCaller   // CXEndCallAction before StreamsRunning
	case declined
}

enum BlountCallEventMapper {
	/// SDK Call.State (+ optional CallKit context) → presentation phase.
	/// Connecting and StreamsRunning are deliberately distinct (atom 4.03):
	/// "Connecting" means negotiation in flight; "In call" requires StreamsRunning.
	static func phase(for state: Call.State, kit: BlountCallKitContext = .none,
					  wasConnected: Bool = false) -> BlountCallPhase {
		switch state {
		case .IncomingReceived, .PushIncomingReceived:
			return kit == .answeredElsewhere ? .answeredElsewhere : .incoming
		case .OutgoingInit, .OutgoingProgress:
			return .connecting
		case .StreamsRunning, .Connected:
			return .active
		case .Paused, .PausedByRemote:
			return wasConnected ? .held : .connecting
		case .Pausing, .Resuming:
			return wasConnected ? .held : .connecting
		case .End:
			if kit == .cancelledByCaller || kit == .declined { return .cancelled }
			if kit == .answeredElsewhere { return .answeredElsewhere }
			return wasConnected ? .ended : .cancelled
		case .Error:
			return .failed
		default:
			// Unconfirmed/future SDK states never invent a live phase.
			return wasConnected ? .ended : .connecting
		}
	}

	/// Human label for the phase — engine-confirmed wording only.
	static func label(for phase: BlountCallPhase) -> String {
		switch phase {
		case .incoming: return "Incoming call"
		case .outgoingDialing: return "Calling…"
		case .connecting: return "Connecting…"
		case .active: return "In call"
		case .held: return "On hold"
		case .ending: return "Ending…"
		case .ended: return "Call ended"
		case .failed: return "Call failed"
		case .answeredElsewhere: return "Answered on another device"
		case .cancelled: return "Call cancelled"
		}
	}

	/// CallKit UUID for a call: ProviderDelegate.uuids[callId] is the binding;
	/// returns nil when CallKit never reported the call (e.g. early engine states).
	static func callKitUUID(forSdkCallID callId: String,
							provider: ProviderDelegate? = TelecomManager.shared.providerDelegate) -> UUID? {
		provider?.uuids[callId]
	}
}
