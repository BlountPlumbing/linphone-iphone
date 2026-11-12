//
//  BlountCallsScreen.swift
//  Fixture Calls surface: ringing brief (five match states), fixed
//  Answer/Decline controls, active-call control grid, calls list.
//  All data is fictional fixture content — no engine calls are made.
//

import SwiftUI

struct BlountCallsScreen: View {
	@Binding var activeCallID: UUID?
	@State private var ringingCall: FixtureCall? = BlountFixtureData.calls.first
	@State private var showActiveCall = false
	@State private var callMuted = false
	@State private var callOnHold = false

	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				if let ringing = ringingCall {
					BlountRingingBrief(call: ringing, onAnswer: {
						activeCallID = ringing.id
						showActiveCall = true
						ringingCall = nil
					}, onDecline: { ringingCall = nil })
				}
				if showActiveCall, let call = BlountFixtureData.calls.first {
					BlountActiveCallGrid(call: call, muted: $callMuted, onHold: $callOnHold,
						onEnd: { showActiveCall = false; activeCallID = nil })
				}
				BlountCallsList(onSelect: { call in
					if call.isRinging { ringingCall = call } else { activeCallID = call.id }
				})
			}
			.padding(16)
		}
		.background(BlountTheme.Colors.workspace)
		.navigationBarTitleDisplayMode(.inline)
	}
}

/// Ringing brief — customer context above fixed Answer/Decline (atom 3.08).
/// Match states per CUSTOMER-CONTEXT-CONTRACT: matched/ambiguous/unmatched/
/// withheld/unavailable. Staff-only section is amber + labelled.
struct BlountRingingBrief: View {
	let call: FixtureCall
	let onAnswer: () -> Void
	let onDecline: () -> Void

	private var caller: FixtureCaller? { call.caller }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Incoming call")
					.font(BlountTypography.footnote.weight(.semibold))
					.foregroundColor(BlountTheme.Colors.secondaryInk)
				Spacer()
				if let freshness = caller?.freshness {
					Text(freshness)
						.font(BlountTypography.caption)
						.foregroundColor(BlountTheme.Colors.secondaryInk)
				}
			}

			Text(caller?.displayName ?? "Unknown caller")
				.font(BlountTypography.callerName)
				.foregroundColor(BlountTheme.Colors.primaryInk)

			Text(caller?.number ?? "")
				.font(BlountTypography.callout)
				.foregroundColor(BlountTheme.Colors.secondaryInk)

			// Match-state banner — honest identity state, never invented.
			Text(caller?.matchState.title ?? FixtureMatchState.unavailable.title)
				.font(BlountTypography.staffLabel)
				.padding(.horizontal, 10).padding(.vertical, 5)
				.background(matchBadgeColor.opacity(0.15))
				.foregroundColor(matchBadgeColor)
				.cornerRadius(6)

			if let site = caller?.site {
				briefRow(icon: "mappin.and.ellipse", text: site)
			}
			if let job = caller?.lastJob {
				briefRow(icon: "wrench.and.screwdriver", text: job)
			}

			// Staff-only context — amber surface + explicit label; never customer-visible.
			if let note = caller?.staffNote {
				VStack(alignment: .leading, spacing: 4) {
					Label("Staff only", systemImage: "lock.fill")
						.font(BlountTypography.staffLabel)
						.foregroundColor(BlountTheme.Colors.primaryInk)
					Text(note)
						.font(BlountTypography.footnote)
						.foregroundColor(BlountTheme.Colors.primaryInk)
				}
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(BlountTheme.Colors.staffAmberSurface)
				.cornerRadius(8)
			}
			if let balance = caller?.balanceMinor, let currency = caller?.currency {
				HStack {
					Image(systemName: "lock.fill").font(BlountTypography.caption)
					Text("Staff only · Balance \(currency) \(String(format: "%.2f", Double(balance) / 100))")
						.font(BlountTypography.footnote)
				}
				.foregroundColor(BlountTheme.Colors.primaryInk)
				.padding(8)
				.background(BlountTheme.Colors.staffAmberSurface)
				.cornerRadius(8)
			}

			// Fixed controls — Answer mint on navy stage; Decline destructive w/ label.
			HStack(spacing: 24) {
				Spacer()
				VStack(spacing: 6) {
					Button(action: onDecline) {
						Image(systemName: "phone.down.fill")
							.font(.title2)
							.foregroundColor(BlountTheme.Colors.onDestructive)
							.frame(width: 64, height: 64)
							.background(BlountTheme.Colors.destructive)
							.clipShape(Circle())
					}
					.accessibilityLabel("Decline call")
					Text("Decline").font(BlountTypography.caption).foregroundColor(BlountTheme.Colors.secondaryInk)
				}
				VStack(spacing: 6) {
					Button(action: onAnswer) {
						Image(systemName: "phone.fill")
							.font(.title2)
							.foregroundColor(BlountTheme.Colors.callStage)
							.frame(width: 64, height: 64)
							.background(BlountTheme.Colors.answerMint)
							.clipShape(Circle())
					}
					.accessibilityLabel("Answer call")
					Text("Answer").font(BlountTypography.caption).foregroundColor(BlountTheme.Colors.secondaryInk)
				}
				Spacer()
			}
			.padding(.top, 4)
		}
		.padding(16)
		.background(BlountTheme.Colors.callStage)
		.cornerRadius(16)
	}

	private var matchBadgeColor: Color {
		switch caller?.matchState {
		case .matched: return BlountTheme.Colors.statusConnected
		case .ambiguous: return BlountTheme.Colors.statusDegraded
		case .unmatched, .withheld, .unavailable, .none: return BlountTheme.Colors.statusOffline
		}
	}

	private func briefRow(icon: String, text: String) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon).font(BlountTypography.footnote)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
				.frame(width: 20)
			Text(text).font(BlountTypography.callout)
				.foregroundColor(BlountTheme.Colors.primaryInk)
		}
	}
}

/// Active-call control grid (atom 3.09) — labels reflect fixture state only;
/// engine confirmation semantics land in T-4.
struct BlountActiveCallGrid: View {
	let call: FixtureCall
	@Binding var muted: Bool
	@Binding var onHold: Bool
	let onEnd: () -> Void

	var body: some View {
		VStack(spacing: 14) {
			Text(call.caller?.displayName ?? "Unknown caller")
				.font(BlountTypography.callerName)
				.foregroundColor(BlountTheme.Colors.primaryInk)
			Text("Call in progress")
				.font(BlountTypography.footnote)
				.foregroundColor(BlountTheme.Colors.secondaryInk)

			LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
				controlButton(icon: muted ? "mic.slash.fill" : "mic.fill",
					label: muted ? "Unmute" : "Mute", active: muted) { muted.toggle() }
				controlButton(icon: "circle.grid.3x3.fill", label: "Keypad", active: false) {}
				controlButton(icon: onHold ? "play.fill" : "pause.fill",
					label: onHold ? "Resume" : "Hold", active: onHold) { onHold.toggle() }
				controlButton(icon: "speaker.wave.2.fill", label: "Audio", active: false) {}
				controlButton(icon: "arrow.left.arrow.right", label: "Transfer", active: false) {}
				controlButton(icon: "phone.down.fill", label: "End", active: false,
					destructive: true, action: onEnd)
			}
		}
		.padding(16)
		.background(BlountTheme.Colors.card)
		.cornerRadius(16)
	}

	private func controlButton(icon: String, label: String, active: Bool,
							   destructive: Bool = false, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 6) {
				Image(systemName: icon)
					.font(.title3)
					.foregroundColor(destructive
						? BlountTheme.Colors.onDestructive
						: (active ? BlountTheme.Colors.actionTeal : BlountTheme.Colors.primaryInk))
					.frame(width: 52, height: 52)
					.background(destructive
						? BlountTheme.Colors.destructive
						: (active ? BlountTheme.Colors.actionTeal.opacity(0.12) : BlountTheme.Colors.workspace))
					.clipShape(Circle())
				Text(label).font(BlountTypography.caption)
					.foregroundColor(BlountTheme.Colors.secondaryInk)
			}
		}
		.buttonStyle(PlainButtonStyle())
		.accessibilityLabel(label)
	}
}

/// Calls list with deliberate detail entry (atom 3.10).
struct BlountCallsList: View {
	let onSelect: (FixtureCall) -> Void
	@State private var filterMissedOnly = false

	private var visible: [FixtureCall] {
		filterMissedOnly ? BlountFixtureData.calls.filter { $0.direction == "missed" } : BlountFixtureData.calls
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Recent calls").font(BlountTypography.headline)
					.foregroundColor(BlountTheme.Colors.primaryInk)
				Spacer()
				Button(filterMissedOnly ? "Show all" : "Missed only") { filterMissedOnly.toggle() }
					.font(BlountTypography.footnote)
					.foregroundColor(BlountTheme.Colors.actionTeal)
			}
			ForEach(visible) { call in
				Button { onSelect(call) } label: {
					HStack(spacing: 12) {
						Image(systemName: call.direction == "missed" ? "phone.down.fill"
														 : (call.direction == "incoming" ? "phone.arrow.down.left" : "phone.arrow.up.right"))
							.font(BlountTypography.callout)
							.foregroundColor(call.direction == "missed"
								? BlountTheme.Colors.destructive : BlountTheme.Colors.secondaryInk)
							.frame(width: 28)
						VStack(alignment: .leading, spacing: 2) {
							Text(call.caller?.displayName ?? "Unknown caller")
								.font(BlountTypography.body.weight(.medium))
								.foregroundColor(BlountTheme.Colors.primaryInk)
							Text(call.startedLabel)
								.font(BlountTypography.caption)
								.foregroundColor(BlountTheme.Colors.secondaryInk)
						}
						Spacer()
						Image(systemName: "chevron.right")
							.font(BlountTypography.caption)
							.foregroundColor(BlountTheme.Colors.hairline)
					}
					.padding(12)
					.background(BlountTheme.Colors.card)
					.cornerRadius(10)
				}
				.buttonStyle(PlainButtonStyle())
				.accessibilityLabel("Call with \(call.caller?.displayName ?? "unknown")")
			}
		}
	}
}
