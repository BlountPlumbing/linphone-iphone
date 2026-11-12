//
//  BlountVideo.swift
//  Atoms 4.40-4.44 — video permission, fallback, params, camera, peer states.
//  4.40 camera permission requested ONLY by explicit preview action.
//  4.41 audio-only fallback renders when camera access is denied.
//  4.42 video on/off bound to confirmed call.currentParams, not the tap.
//  4.43 front/back selection via existing core.setVideodevice device list.
//  4.44 peer-no-video and codec fallback states from remoteParams/currentParams.
//

import Foundation
import AVFoundation
import linphonesw

// MARK: - 4.40 camera permission (explicit preview action only)

enum BlountCameraPermission {
	static var status: AVAuthorizationStatus {
		AVCaptureDevice.authorizationStatus(for: .video)
	}

	static var granted: Bool { status == .authorized }

	/// The ONLY entry that may prompt — call from the preview button action.
	/// Never request at launch, tab appear, or call start.
	static func requestForPreview(_ completion: @escaping (Bool) -> Void) {
		AVCaptureDevice.requestAccess(for: .video) { granted in
			DispatchQueue.main.async { completion(granted) }
		}
	}
}

// MARK: - 4.41 audio-only fallback

enum BlountVideoFallback: String, Equatable {
	case videoAvailable
	case audioOnlyCameraDenied
	case audioOnlyPeerNoVideo
	case audioOnlyCallParams
}

// MARK: - 4.44 peer / codec fallback projection

enum BlountPeerVideoState: String, Equatable {
	case none               // no video negotiated
	case sending            // local→remote video active
	case receiving          // remote→local video active
	case both               // SendRecv
	case unknown            // params unavailable — honest indeterminate
}

enum BlountVideoProjector {
	/// Derive peer video state from call params — never assumes capability.
	static func peerState(call: Call?) -> BlountPeerVideoState {
		guard let params = call?.currentParams else { return .unknown }
		guard params.videoEnabled else { return .none }
		switch params.videoDirection {
		case .SendOnly: return .sending
		case .RecvOnly: return .receiving
		case .SendRecv: return .both
		default: return .unknown
		}
	}

	/// Fallback classification for the call surface.
	static func fallback(cameraGranted: Bool, peer: BlountPeerVideoState,
					   callVideoEnabled: Bool) -> BlountVideoFallback {
		if !cameraGranted { return .audioOnlyCameraDenied }
		if !callVideoEnabled { return .audioOnlyCallParams }
		if peer == .none || peer == .unknown { return .audioOnlyPeerNoVideo }
		return .videoAvailable
	}
}

// MARK: - 4.42/4.43 controls (engine-confirmed)

@MainActor
final class BlountVideoControls {
	static let shared = BlountVideoControls()
	private init() {}

	/// Confirmed video-enabled state per SDK call ID — set only after reading
	/// call.currentParams.videoEnabled back from the engine.
	@Published private(set) var confirmedVideo: [String: Bool] = [:]

	/// Atom 4.42 — request video on/off; publish the engine-confirmed value.
	func setVideo(sdkCallID: String, enabled: Bool) {
		CoreContext.shared.doOnCoreQueue { core in
			guard let call = BlountCallSession.findCall(sdkCallID: sdkCallID, core: core) else { return }
			do {
				let params = try core.createCallParams(call: call)
				params.videoEnabled = enabled
				try call.update(params: params)
			} catch {
				Log.error("[BlountVideo] setVideo failed: \(error)")
				return
			}
			// Confirm from engine params after the update lands.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
				let confirmed = call.currentParams?.videoEnabled ?? false
				Task { @MainActor in self.confirmedVideo[sdkCallID] = confirmed }
			}
		}
	}

	/// Atom 4.43 — cycle to the next non-static camera via the existing
	/// videoDevicesList/setVideodevice path (same mechanism as CallViewModel).
	func switchCamera() {
		CoreContext.shared.doOnCoreQueue { core in
			let current = core.videoDevice
			for camera in core.videoDevicesList
			where camera != current && camera != "StaticImage: Static picture" {
				do { try core.setVideodevice(newValue: camera); return } catch { continue }
			}
		}
	}
}
