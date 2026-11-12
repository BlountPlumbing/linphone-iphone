//
//  BlountPeopleScreen.swift
//  Fixture People directory — customers and internal staff in one list.
//

import SwiftUI

struct BlountPeopleScreen: View {
	@State private var query = ""

	private var filtered: [FixtureContact] {
		let q = query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return BlountFixtureData.contacts }
		return BlountFixtureData.contacts.filter {
			$0.name.localizedCaseInsensitiveContains(q) || $0.phone.contains(q)
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			TextField("Search people…", text: $query)
				.font(BlountTypography.callout)
				.padding(10)
				.background(BlountTheme.Colors.card)
				.cornerRadius(10)
				.padding(.horizontal, 16).padding(.vertical, 10)

			ScrollView {
				VStack(spacing: 8) {
					ForEach(filtered) { contact in
						HStack(spacing: 12) {
							Image(systemName: contact.role == "Internal" ? "person.badge.shield.checkmark" : "person.crop.circle")
								.font(BlountTypography.title2)
								.foregroundColor(BlountTheme.Colors.actionTeal)
								.frame(width: 36, height: 36)
								.background(BlountTheme.Colors.actionTeal.opacity(0.1))
								.clipShape(Circle())
							VStack(alignment: .leading, spacing: 2) {
								Text(contact.name).font(BlountTypography.body.weight(.medium))
									.foregroundColor(BlountTheme.Colors.primaryInk)
								Text("\(contact.role) · \(contact.phone)")
									.font(BlountTypography.caption)
									.foregroundColor(BlountTheme.Colors.secondaryInk)
							}
							Spacer()
							Image(systemName: "phone.fill")
								.font(BlountTypography.callout)
								.foregroundColor(BlountTheme.Colors.actionTeal)
						}
						.padding(12)
						.background(BlountTheme.Colors.card)
						.cornerRadius(10)
						.accessibilityElement(children: .combine)
						.accessibilityLabel("\(contact.name), \(contact.role), \(contact.phone)")
					}
					if filtered.isEmpty {
						Text("No matching people.")
							.font(BlountTypography.callout)
							.foregroundColor(BlountTheme.Colors.secondaryInk)
							.padding(.top, 24)
					}
				}
				.padding(.horizontal, 16).padding(.bottom, 16)
			}
		}
		.background(BlountTheme.Colors.workspace)
	}
}
