//
//  BlountTheme.swift
//  Blount "Field desk" native color tokens — UX-DESIGN-SPEC color table.
//  Fixture-preview surface; Night shift remains an unimplemented alternate.
//

import SwiftUI

enum BlountTheme {
	enum Colors {
		/// Primary ink for text and icons on light surfaces.
		static let primaryInk = Color(hex: 0x18343C)
		/// Call stage — dark navy surface that gives calls distinct focus.
		static let callStage = Color(hex: 0x112F38)
		/// Workspace background.
		static let workspace = Color(hex: 0xF7F8F4)
		/// Cards sit on white over the workspace.
		static let card = Color.white
		/// Primary action teal; labels use white.
		static let actionTeal = Color(hex: 0x06776C)
		static let onAction = Color.white
		/// Pale mint — Answer treatment on the dark call stage.
		static let answerMint = Color(hex: 0xCDEFE3)
		/// Staff-only accent (amber) and its pale surface treatment.
		static let staffAmber = Color(hex: 0xE6C98A)
		static let staffAmberSurface = Color(hex: 0xF5EBD2)
		/// Destructive call action — muted burgundy, never color-only.
		static let destructive = Color(hex: 0x7A3B47)
		static let onDestructive = Color.white
		static let secondaryInk = Color(hex: 0x4A5A60)
		static let hairline = Color(hex: 0xD8DDD6)
		static let statusConnected = Color(hex: 0x2E7D4F)
		static let statusDegraded = Color(hex: 0xB07A1E)
		static let statusOffline = Color(hex: 0x8A4A42)
	}
}

extension Color {
	init(hex: UInt32, opacity: Double = 1) {
		self.init(
			.red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255,
			opacity: opacity
		)
	}
}
