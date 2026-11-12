//
//  BlountCallLog.swift
//  Atoms 4.14-4.15 — call-log segments + call detail labels.
//  4.14 Recent/Missed segments over the existing device call log (HistoryModel).
//  4.15 Detail renders source + recording-access labels honestly:
//       source = device call log / live call / server record — never merged.
//       recording access = authorized/unavailable — withheld until backend proof.
//

import Foundation
import linphonesw

enum BlountCallLogSegment: String, CaseIterable, Identifiable {
	case recent, missed
	var id: String { rawValue }
	var label: String { self == .recent ? "Recent" : "Missed" }
}

/// Recording-access label states — honest, no invented capability.
enum BlountRecordingAccess: String {
	case authorized       // server issued authorized source access
	case unavailable      // no recording exists or access not proven
	case withheld         // exists but policy withheld it from this viewer
}

/// Call-detail presentation — source is explicit, never implied.
struct BlountCallDetail: Equatable {
	enum Source: String {
		case deviceCallLog   // local Linphone call log record
		case liveCall        // in-progress presentation store record
		case serverRecord    // server/PBX-side record (requires backend proof)
	}
	let source: Source
	let address: String
	let displayName: String
	let startedAt: Date?
	let durationSeconds: Int?
	let wasMissed: Bool
	let recordingAccess: BlountRecordingAccess
	/// Transcript/retention actions render ONLY when their source is proven.
	var transcriptActionLabel: String? {
		recordingAccess == .authorized ? "Transcript" : nil
	}
}

enum BlountCallLogPresenter {
	/// Segment membership over the existing call log. Missed = Call.Status.Missed;
	/// Recent = everything (the log is already recency-ordered by the engine).
	static func segment(of model: HistoryModel) -> BlountCallLogSegment {
		model.status == .Missed ? .missed : .recent
	}

	static func models(_ all: [HistoryModel], in segment: BlountCallLogSegment) -> [HistoryModel] {
		all.filter { self.segment(of: $0) == segment }
	}

	/// Build detail for a call-log row. Recording access defaults to
	/// .unavailable — atom 4.37+ binds authorized access; nothing is invented.
	static func detail(for model: HistoryModel,
					   recordingAccess: BlountRecordingAccess = .unavailable) -> BlountCallDetail {
		BlountCallDetail(
			source: .deviceCallLog,
			address: model.address,
			displayName: model.addressName.isEmpty ? model.address : model.addressName,
			startedAt: Date(timeIntervalSince1970: TimeInterval(model.startDate)),
			durationSeconds: model.duration > 0 ? model.duration : nil,
			wasMissed: model.status == .Missed,
			recordingAccess: recordingAccess
		)
	}

	/// Live-call detail when the presentation store owns the call.
	static func detail(for presentation: BlountCallPresentation) -> BlountCallDetail {
		BlountCallDetail(
			source: .liveCall,
			address: presentation.remoteAddress,
			displayName: presentation.displayName.isEmpty
				? presentation.remoteAddress : presentation.displayName,
			startedAt: nil,          // engine does not expose start time here yet
			durationSeconds: nil,
			wasMissed: false,
			recordingAccess: .unavailable
		)
	}
}
