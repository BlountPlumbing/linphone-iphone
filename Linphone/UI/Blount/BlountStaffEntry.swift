//
//  BlountStaffEntry.swift
//  Fixture staff-access welcome — mirrors the staff owner's candidate
//  interface contract (Blount-only staff sign-in, no generic provider/QR
//  bypass). Auth binding is HELD (atom 2.29): actions render disabled with
//  an honest unavailable note. A clearly-labelled fixture-only continue
//  affordance opens the workspace preview; it is not an auth bypass.
//

import SwiftUI

struct BlountStaffEntry: View {
	let onContinueToFixture: () -> Void

	var body: some View {
		VStack(spacing: 24) {
			Spacer()
			Image(systemName: "phone.fill")
				.font(.system(size: 44))
				.foregroundColor(BlountTheme.Colors.actionTeal)
				.accessibilityHidden(true)
			Text("Blount Phone")
				.font(BlountTypography.pageTitle)
				.foregroundColor(BlountTheme.Colors.primaryInk)
			Text("Your staff phone, connected to Blount Plumbing.")
				.font(BlountTypography.callout)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
				.multilineTextAlignment(.center)

			VStack(spacing: 12) {
				Button("Sign in with your staff passkey") {}
					.buttonStyle(.borderedProminent)
					.disabled(true)
					.tint(BlountTheme.Colors.actionTeal)
				Button("Scan your company setup code") {}
					.buttonStyle(.bordered)
					.disabled(true)
			}

			Text("Staff sign-in is awaiting secure connection to the company account service.")
				.font(BlountTypography.footnote)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
				.multilineTextAlignment(.center)
				.accessibilityIdentifier("staff-auth-unavailable")

			Text("Use your existing staff account. Contact your administrator if you need access.")
				.font(BlountTypography.footnote)
				.foregroundColor(BlountTheme.Colors.secondaryInk)
				.multilineTextAlignment(.center)

			// Fixture-only preview entry — not an authentication path.
			Button("Preview workspace (fixture only)") { onContinueToFixture() }
				.font(BlountTypography.footnote.weight(.semibold))
				.foregroundColor(BlountTheme.Colors.actionTeal)
				.padding(.top, 8)
				.accessibilityLabel("Preview workspace, fixture mode only")
			Spacer()
		}
		.padding(28)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(BlountTheme.Colors.workspace)
	}
}
