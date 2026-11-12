//
//  BlountInboxScreen.swift
//  Fixture Inbox: loading/empty/denied states and a conversation surface with
//  separate customer and staff-note drafts. Staff notes are visibly staff-only
//  and never leave the device in fixture mode.
//

import SwiftUI

struct BlountInboxScreen: View {
	@State private var state: FixtureInboxState = .ready
	@State private var openThreadID: UUID?

	var body: some View {
		VStack(spacing: 0) {
			// Fixture state switcher — preview control, clearly fixture-only.
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(BlountFixtureData.inboxStates, id: \.self) { s in
						Button(stateLabel(s)) { state = s; openThreadID = nil }
							.font(BlountTypography.caption)
							.padding(.horizontal, 12).padding(.vertical, 6)
							.background(state == s ? BlountTheme.Colors.actionTeal : BlountTheme.Colors.card)
							.foregroundColor(state == s ? .white : BlountTheme.Colors.primaryInk)
							.cornerRadius(14)
					}
				}
				.padding(.horizontal, 12).padding(.vertical, 8)
			}
			.background(BlountTheme.Colors.card)

			if let threadID = openThreadID,
			   let thread = BlountFixtureData.threads.first(where: { $0.id == threadID }) {
				BlountConversationView(thread: thread, onBack: { openThreadID = nil })
			} else {
				inboxBody
			}
		}
		.background(BlountTheme.Colors.workspace)
	}

	private func stateLabel(_ s: FixtureInboxState) -> String {
		switch s {
		case .loading: return "Loading"
		case .empty: return "Empty"
		case .denied: return "Denied"
		case .ready: return "Ready"
		}
	}

	@ViewBuilder
	private var inboxBody: some View {
		switch state {
		case .loading:
			statePanel(icon: "arrow.triangle.2.circlepath", title: "Loading conversations",
				   message: "Checking your message service…")
		case .empty:
			statePanel(icon: "bubble.left", title: "No conversations yet",
				   message: "Customer texts and staff notes will appear here.")
		case .denied:
			statePanel(icon: "lock.shield", title: "Inbox unavailable",
				   message: "Your staff account doesn't have messaging access. Contact your administrator.")
		case .ready:
			ScrollView {
				VStack(spacing: 10) {
					ForEach(BlountFixtureData.threads) { thread in
						Button { openThreadID = thread.id } label: {
							HStack(spacing: 12) {
								Image(systemName: "bubble.left.fill")
									.font(BlountTypography.callout)
									.foregroundColor(BlountTheme.Colors.actionTeal)
									.frame(width: 32, height: 32)
									.background(BlountTheme.Colors.actionTeal.opacity(0.1))
									.clipShape(Circle())
								VStack(alignment: .leading, spacing: 2) {
									Text(thread.title).font(BlountTypography.body.weight(.medium))
										.foregroundColor(BlountTheme.Colors.primaryInk)
									Text(thread.subtitle).font(BlountTypography.caption)
										.foregroundColor(BlountTheme.Colors.secondaryInk)
									if let last = thread.messages.last {
										Text(last.isStaffNote ? "Staff note: \(last.body)" : last.body)
											.font(BlountTypography.footnote)
											.foregroundColor(BlountTheme.Colors.secondaryInk)
											.lineLimit(1)
									}
								}
								Spacer()
							}
							.padding(12)
							.background(BlountTheme.Colors.card)
							.cornerRadius(10)
						}
						.buttonStyle(PlainButtonStyle())
						.accessibilityLabel("Conversation \(thread.title)")
					}
				}
				.padding(16)
			}
		}
	}

	private func statePanel(icon: String, title: String, message: String) -> some View {
		VStack(spacing: 12) {
			Spacer()
			Image(systemName: icon).font(.largeTitle)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
			Text(title).font(BlountTypography.headline)
				.foregroundColor(BlountTheme.Colors.primaryInk)
			Text(message).font(BlountTypography.callout)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
				.multilineTextAlignment(.center)
			Spacer()
		}
		.frame(maxWidth: .infinity)
		.padding(24)
	}
}

/// Conversation with separate customer/staff drafts (atom 3.12).
/// Customer send shows exact recipient/channel; staff notes are labelled and
/// can never be addressed to the customer.
struct BlountConversationView: View {
	let thread: FixtureThread
	let onBack: () -> Void
	@State private var customerDraft = ""
	@State private var staffDraft = ""

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Button(action: onBack) {
					Image(systemName: "chevron.left").font(BlountTypography.headline)
						.foregroundColor(BlountTheme.Colors.actionTeal)
				}
				.accessibilityLabel("Back to inbox")
				VStack(alignment: .leading, spacing: 2) {
					Text(thread.title).font(BlountTypography.headline)
						.foregroundColor(BlountTheme.Colors.primaryInk)
					Text(thread.subtitle).font(BlountTypography.caption)
						.foregroundColor(BlountTheme.Colors.secondaryInk)
				}
				Spacer()
			}
			.padding(.horizontal, 12).padding(.vertical, 8)
			.background(BlountTheme.Colors.card)

			ScrollView {
				VStack(spacing: 10) {
					ForEach(thread.messages) { msg in
						messageBubble(msg)
					}
				}
				.padding(16)
			}

			draftArea
		}
		.background(BlountTheme.Colors.workspace)
	}

	@ViewBuilder
	private func messageBubble(_ msg: FixtureMessage) -> some View {
		if msg.isStaffNote {
			// Staff note — amber, left-aligned, labelled Staff only.
			VStack(alignment: .leading, spacing: 4) {
				Label("Staff only · \(msg.author)", systemImage: "lock.fill")
					.font(BlountTypography.staffLabel)
					.foregroundColor(BlountTheme.Colors.primaryInk)
				Text(msg.body).font(BlountTypography.callout)
					.foregroundColor(BlountTheme.Colors.primaryInk)
				Text(msg.time).font(BlountTypography.caption)
					.foregroundColor(BlountTheme.Colors.secondaryInk)
			}
			.padding(10)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(BlountTheme.Colors.staffAmberSurface)
			.cornerRadius(10)
		} else {
			HStack {
				if msg.author == "You" { Spacer(minLength: 40) }
				VStack(alignment: .leading, spacing: 4) {
					Text(msg.body).font(BlountTypography.callout)
						.foregroundColor(BlountTheme.Colors.primaryInk)
					Text("\(msg.author) · \(msg.time)").font(BlountTypography.caption)
						.foregroundColor(BlountTheme.Colors.secondaryInk)
				}
				.padding(10)
				.background(msg.author == "You" ? BlountTheme.Colors.actionTeal.opacity(0.12)
														: BlountTheme.Colors.card)
				.cornerRadius(10)
				if msg.author != "You" { Spacer(minLength: 40) }
			}
		}
	}

	private var draftArea: some View {
		VStack(spacing: 8) {
			// Customer draft — exact recipient/channel review before send.
			HStack(spacing: 8) {
				TextField("Message \(thread.title) via SMS…", text: $customerDraft)
					.font(BlountTypography.callout)
					.padding(10)
					.background(BlountTheme.Colors.card)
					.cornerRadius(10)
				Button("Send") { customerDraft = "" }
					.font(BlountTypography.callout.weight(.semibold))
					.foregroundColor(BlountTheme.Colors.onAction)
					.padding(.horizontal, 14).padding(.vertical, 10)
					.background(BlountTheme.Colors.actionTeal)
					.cornerRadius(10)
					.disabled(customerDraft.isEmpty)
					.opacity(customerDraft.isEmpty ? 0.5 : 1)
			}
			Text("Sends to \(thread.subtitle) as SMS — review recipient before sending.")
				.font(BlountTypography.caption)
				.foregroundColor(BlountTheme.Colors.secondaryInk)

			// Staff-note draft — separate audience, never customer-visible.
			HStack(spacing: 8) {
				Image(systemName: "lock.fill").font(BlountTypography.caption)
					.foregroundColor(BlountTheme.Colors.primaryInk)
				TextField("Staff note (team only)…", text: $staffDraft)
					.font(BlountTypography.callout)
					.padding(10)
					.background(BlountTheme.Colors.staffAmberSurface)
					.cornerRadius(10)
				Button("Save staff note") { staffDraft = "" }
					.font(BlountTypography.callout.weight(.semibold))
					.foregroundColor(BlountTheme.Colors.primaryInk)
					.padding(.horizontal, 14).padding(.vertical, 10)
					.background(BlountTheme.Colors.staffAmber)
					.cornerRadius(10)
					.disabled(staffDraft.isEmpty)
					.opacity(staffDraft.isEmpty ? 0.5 : 1)
			}
			Text("Staff notes stay inside Blount — they are never sent to the customer.")
				.font(BlountTypography.caption)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
		}
		.padding(12)
		.background(BlountTheme.Colors.card)
	}
}
