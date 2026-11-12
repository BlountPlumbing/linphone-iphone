//
//  BlountCallControls.swift
//  Atoms 4.04-4.05 — call controls bound to confirmed engine state.
//  Mute is published ONLY after re-reading call.microphoneMuted + core.micEnabled;
//  the route chooser exposes the effective route policy (earpiece restriction).
//

import Foundation
import linphonesw

/// Effective audio-route policy for the Blount call UI.
enum BlountAudioRoutePolicy {
	/// Routes the user may pick right now. Earpiece-only restriction collapses
	/// the chooser to the single allowed route.
	static func allowedRoutes(restrictedToEarpiece: Bool) -> [BlountAudioRoute] {
		restrictedToEarpiece ? [.earpiece] : [.earpiece, .speaker, .bluetooth, .wiredHeadset]
	}

	static var currentRestriction: Bool {
		AppServices.corePreferences.onlyAllowEarpieceDuringCall
	}
}

enum BlountAudioRoute: String, CaseIterable, Identifiable {
	case earpiece, speaker, bluetooth, wiredHeadset
	var id: String { rawValue }
	var label: String {
		switch self {
		case .earpiece: return "iPhone"
		case .speaker: return "Speaker"
		case .bluetooth: return "Bluetooth"
		case .wiredHeadset: return "Headset"
		}
	}
}

@MainActor
final class BlountCallControls {
	static let shared = BlountCallControls()

	/// Confirmed mute state per SDK call ID — only set after engine read-back.
	@Published private(set) var confirmedMuted: [String: Bool] = [:]

	private init() {}

	/// Toggle mute and publish the state the ENGINE reports afterwards.
	/// Never trusts the requested value — reads call.microphoneMuted + core.micEnabled.
	func toggleMute(sdkCallID: String) {
		CoreContext.shared.doOnCoreQueue { core in
			guard let call = Self.findCall(sdkCallID: sdkCallID, core: core) else { return }
			let requested = !(call.microphoneMuted || !core.micEnabled)
			TelecomManager.shared.setMicMuted(core: core, call: call, muted: requested)
			// Confirm against engine state — CallKit path may defer the apply.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
				CoreContext.shared.doOnCoreQueue { core2 in
					let confirmed = call.microphoneMuted || !core2.micEnabled
					Task { @MainActor in
						self.confirmedMuted[sdkCallID] = confirmed
					}
				}
			}
		}
	}

	/// Whether the route chooser is restricted to earpiece by policy.
	var routePolicyRestricted: Bool { BlountAudioRoutePolicy.currentRestriction }

	var allowedRoutes: [BlountAudioRoute] {
		BlountAudioRoutePolicy.allowedRoutes(restrictedToEarpiece: routePolicyRestricted)
	}

	private static func findCall(sdkCallID: String, core: Core) -> Call? {
		// Calls are reachable through the core's current calls; match by callLog id.
		for c in core.calls {
			if c.callLog?.callId == sdkCallID || c == core.currentCall { return c }
		}
		return core.currentCall
	}
}
