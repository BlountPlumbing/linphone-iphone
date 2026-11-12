//
//  BlountRecording.swift
//  Atoms 4.37-4.39 — recording metadata/playback/unavailable states.
//  4.37 metadata renders ONLY for authorized source access.
//  4.38 playback binds the existing engine/media adapter — never a parallel player.
//  4.39 unavailable actions render honestly and NEVER delete source records.
//

import Foundation

/// A recording the server/account feed may expose. Metadata fields stay nil
/// until an authorized source supplies them — nothing is invented.
struct BlountRecordingItem: Identifiable, Equatable {
	let id: String
	let callReference: String
	var durationSeconds: Int?
	var recordedAt: Date?
	var transcriptAvailable: Bool = false
	var retentionLabel: String?
}

/// Access verdict for one recording — mirrors BlountRecordingAccess.
enum BlountRecordingVerdict: Equatable {
	case authorized(BlountRecordingItem)
	case unavailable(reason: String)
	case withheld
}

/// Controller binding access verdicts to UI action availability.
/// Playback goes through the EXISTING recordings adapter path only when the
/// verdict is authorized; unavailable verdicts expose no destructive action.
@MainActor
final class BlountRecordingController {
	static let shared = BlountRecordingController()
	private init() {}

	/// Registered authorized sources — populated ONLY by admitted backend code.
	/// Client code must never fabricate entries here.
	private var authorizedSources: [String: BlountRecordingItem] = [:]

	func registerAuthorizedSource(_ item: BlountRecordingItem) {
		authorizedSources[item.id] = item
	}

	/// Atom 4.37 — metadata for a call is visible only with authorized access.
	func metadata(forCallReference ref: String) -> BlountRecordingItem? {
		authorizedSources.values.first { $0.callReference == ref }
	}

	/// Atom 4.38 — playback is offered only for authorized items. The actual
	/// playback still routes through the existing recordings/media adapter;
	/// this controller never instantiates a player.
	var playbackAvailable: Bool { !authorizedSources.isEmpty }

	/// Atom 4.39 — action labels for the detail surface. Unavailable verdicts
	/// render an honest note; no delete/retention-purge action is ever exposed
	/// for sources the app did not authorize.
	func actionLabels(for ref: String) -> (playback: String?, transcript: String?, retention: String?) {
		guard let item = metadata(forCallReference: ref) else {
			return (nil, nil, "Recording unavailable")
		}
		return (
			playbackAvailable ? "Play recording" : nil,
			item.transcriptAvailable ? "Transcript" : nil,
			item.retentionLabel
		)
	}
}
