//
//  BlountTheme.swift
//  Blount "Field desk" native color tokens — UX-DESIGN-SPEC color table.
//  Fixture-preview surface; Night shift remains an unimplemented alternate.
//

import SwiftUI

enum BlountTheme {
	enum Colors {
		/// Primary ink for text and icons on light surfaces.
		static let primaryInk = Color(hex: "#18343C")
		/// Call stage — dark navy surface that gives calls distinct focus.
		static let callStage = Color(hex: "#112F38")
		/// Workspace background.
		static let workspace = Color(hex: "#F7F8F4")
		/// Cards sit on white over the workspace.
		static let card = Color.white
		/// Primary action teal; labels use white.
		static let actionTeal = Color(hex: "#06776C")
		static let onAction = Color.white
		/// Pale mint — Answer treatment on the dark call stage.
		static let answerMint = Color(hex: "#CDEFE3")
		/// Staff-only accent (amber) and its pale surface treatment.
		static let staffAmber = Color(hex: "#E6C98A")
		static let staffAmberSurface = Color(hex: "#F5EBD2")
		/// Destructive call action — muted burgundy, never color-only.
		static let destructive = Color(hex: "#7A3B47")
		static let onDestructive = Color.white
		static let secondaryInk = Color(hex: "#4A5A60")
		static let hairline = Color(hex: "#D8DDD6")
		static let statusConnected = Color(hex: "#2E7D4F")
		static let statusDegraded = Color(hex: "#B07A1E")
		static let statusOffline = Color(hex: "#8A4A42")
	}
}
