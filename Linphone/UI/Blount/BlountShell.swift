//
//  BlountShell.swift
//  Blount product shell — stable Calls / Inbox / People selection.
//  Wraps the fixture preview only; the real ContentView integration is T-4.
//  Consumes the app-wide CoreContext environment object without recreating it.
//

import SwiftUI

struct BlountFixtureRoot: View {
	@State private var showWorkspace = false

	var body: some View {
		if showWorkspace {
			BlountShell()
		} else {
			BlountStaffEntry(onContinueToFixture: { showWorkspace = true })
		}
	}
}

enum BlountSection: Hashable {
	case calls, inbox, people

	var title: String {
		switch self {
		case .calls: return "Calls"
		case .inbox: return "Inbox"
		case .people: return "People"
		}
	}

	var icon: String {
		switch self {
		case .calls: return "phone.fill"
		case .inbox: return "bubble.left.and.bubble.right.fill"
		case .people: return "person.2.fill"
		}
	}
}

struct BlountShell: View {
	@EnvironmentObject private var coreContext: CoreContext
	@State private var selection: BlountSection = .calls
	@State private var activeCallID: UUID?
	@State private var callConnection: FixtureConnection = .connected
	@State private var messageConnection: FixtureConnection = .connected

	var body: some View {
		VStack(spacing: 0) {
			if let call = BlountFixtureData.calls.first(where: { $0.id == activeCallID }) {
				BlountReturnStrip(call: call) { activeCallID = nil }
			}
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			connectionBar
			BlountSectionPicker(selection: $selection)
		}
		.background(BlountTheme.Colors.workspace)
		.environmentObject(coreContext)
	}

	/// Independent call/message connection indicators (atom 3.14) — the two
	/// channels report separately; one degrading never implies the other.
	private var connectionBar: some View {
		HStack(spacing: 16) {
			Label("Calls", systemImage: "phone.fill")
				.font(BlountTypography.caption)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
			BlountConnectionBadge(connection: callConnection)
			Divider().frame(height: 12)
			Label("Messages", systemImage: "bubble.left.fill")
				.font(BlountTypography.caption)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
			BlountConnectionBadge(connection: messageConnection)
			Spacer()
		}
		.padding(.horizontal, 16).padding(.vertical, 6)
		.background(BlountTheme.Colors.card)
		.overlay(Rectangle().frame(height: 1).foregroundColor(BlountTheme.Colors.hairline), alignment: .bottom)
	}

	@ViewBuilder
	private var content: some View {
		switch selection {
		case .calls:
			BlountCallsScreen(activeCallID: $activeCallID)
		case .inbox:
			BlountInboxScreen()
		case .people:
			BlountPeopleScreen()
		}
	}
}

/// Independent call/message connection indicators (atom 3.14).
enum FixtureConnection {
	case connected, degraded, offline

	var label: String {
		switch self {
		case .connected: return "Connected"
		case .degraded: return "Degraded"
		case .offline: return "Offline — drafts saved locally"
		}
	}

	var color: Color {
		switch self {
		case .connected: return BlountTheme.Colors.statusConnected
		case .degraded: return BlountTheme.Colors.statusDegraded
		case .offline: return BlountTheme.Colors.statusOffline
		}
	}
}

struct BlountConnectionBadge: View {
	let connection: FixtureConnection

	var body: some View {
		HStack(spacing: 6) {
			Circle().fill(connection.color).frame(width: 8, height: 8)
			Text(connection.label)
				.font(BlountTypography.footnote)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Call connection \(connection.label)")
	}
}

/// Active-call return strip keyed by call ID (atom 3.06): reachable from any
/// section without losing the call.
struct BlountReturnStrip: View {
	let call: FixtureCall
	let onDismiss: () -> Void

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "phone.fill")
				.foregroundColor(BlountTheme.Colors.answerMint)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(call.caller?.displayName ?? "Unknown caller")
					.font(BlountTypography.subheadline.weight(.semibold))
					.foregroundColor(.white)
					.lineLimit(1)
				Text(call.isRinging ? "Incoming call" : "Call in progress")
					.font(BlountTypography.caption)
					.foregroundColor(BlountTheme.Colors.answerMint)
			}
			Spacer()
			Button(action: onDismiss) {
				Image(systemName: "xmark")
					.font(BlountTypography.footnote.weight(.bold))
					.foregroundColor(.white)
					.padding(8)
					.background(Circle().fill(Color.white.opacity(0.15)))
			}
			.accessibilityLabel("Hide call banner")
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(BlountTheme.Colors.callStage)
	}
}

struct BlountSectionPicker: View {
	@Binding var selection: BlountSection

	var body: some View {
		HStack(spacing: 0) {
			ForEach([BlountSection.calls, .inbox, .people], id: \.self) { section in
				Button {
					selection = section
				} label: {
					VStack(spacing: 4) {
						Image(systemName: section.icon)
							.font(BlountTypography.callout)
						Text(section.title)
							.font(BlountTypography.caption.weight(.medium))
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.foregroundColor(selection == section
						? BlountTheme.Colors.actionTeal
						: BlountTheme.Colors.secondaryInk)
					.background(selection == section
						? BlountTheme.Colors.actionTeal.opacity(0.08)
						: Color.clear)
				}
				.buttonStyle(PlainButtonStyle())
				.accessibilityLabel(section.title)
				.accessibilityAddTraits(selection == section ? .isSelected : [])
			}
		}
		.background(BlountTheme.Colors.card)
		.overlay(Rectangle().frame(height: 1).foregroundColor(BlountTheme.Colors.hairline), alignment: .top)
	}
}
