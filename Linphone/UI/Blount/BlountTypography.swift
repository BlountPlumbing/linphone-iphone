//
//  BlountTypography.swift
//  Blount text roles. Semantic text styles are used throughout so every role
//  scales with Dynamic Type (including accessibility sizes) for free.
//

import SwiftUI

enum BlountTypography {
	/// Main page title / caller — about 29 native points at default size.
	static let pageTitle = Font.largeTitle.weight(.bold)
	/// Caller name on call surfaces.
	static let callerName = Font.title.weight(.semibold)
	/// Large secondary headings (directory avatars etc.).
	static let title2 = Font.title2
	/// Section headlines.
	static let headline = Font.headline
	/// Conversation body and primary list identity (~17pt at default).
	static let body = Font.body
	/// Secondary readable text (~16pt at default).
	static let callout = Font.callout
	/// List secondary lines.
	static let subheadline = Font.subheadline
	static let footnote = Font.footnote
	static let caption = Font.caption
	/// Staff-only labels, identifiers, diagnostic values.
	static let staffLabel = Font.footnote.weight(.semibold)
}
