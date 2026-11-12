//
//  BlountRegressionTests.swift
//  Atoms 4.28-4.29 — navigation/second-call identity + audio route policy.
//  4.28 second call gets its own keyed presentation; selection is
//      generation-guarded; keyCall follows selection not arrival order.
//  4.29 route chooser collapses to earpiece-only under restriction policy.
//

import XCTest
@testable import LinphoneApp

@MainActor
final class BlountRegressionTests: XCTestCase {

	// MARK: 4.28 second-call identity

	func testTwoCallsGetDistinctPresentations() {
		let store = BlountCallPresentationStore()
		store.upsert(BlountCallPresentation(sdkCallID: "call-A", callKitUUID: nil))
		store.upsert(BlountCallPresentation(sdkCallID: "call-B", callKitUUID: nil))
		XCTAssertEqual(store.calls.count, 2)
		XCTAssertNotNil(store.call(sdkCallID: "call-A"))
		XCTAssertNotNil(store.call(sdkCallID: "call-B"))
		XCTAssertNil(store.call(sdkCallID: "call-C"))
	}

	func testCallKitUUIDIsPrimaryKeyWhenPresent() {
		let store = BlountCallPresentationStore()
		let uuid = UUID()
		store.upsert(BlountCallPresentation(sdkCallID: "sdk-1", callKitUUID: uuid))
		XCTAssertNotNil(store.call(callKitUUID: uuid))
	}

	func testRemovalDoesNotDisturbOtherCall() {
		let store = BlountCallPresentationStore()
		store.upsert(BlountCallPresentation(sdkCallID: "call-A", callKitUUID: nil))
		store.upsert(BlountCallPresentation(sdkCallID: "call-B", callKitUUID: nil))
		let a = store.call(sdkCallID: "call-A")!
		store.remove(a.id)
		XCTAssertNil(store.call(sdkCallID: "call-A"))
		XCTAssertNotNil(store.call(sdkCallID: "call-B"))
	}

	// MARK: 4.10/4.28 selection generation guard

	func testStaleGenerationCannotSelect() {
		let session = BlountCallSession.shared
		// beginSelectionContext is instance state; use a fresh session per case.
		let gen1 = session.beginSelectionContext(for: "call-A")
		_ = session.beginSelectionContext(for: "call-A")   // gen2 supersedes
		XCTAssertFalse(session.selectCall(sdkCallID: "call-A", expectedGeneration: gen1))
	}

	func testCurrentGenerationSelects() {
		let store = BlountCallPresentationStore()
		store.upsert(BlountCallPresentation(sdkCallID: "call-A", callKitUUID: nil))
		let session = BlountCallSession.shared
		let gen = session.beginSelectionContext(for: "call-A")
		XCTAssertTrue(session.selectCall(sdkCallID: "call-A", expectedGeneration: gen))
	}

	// MARK: 4.29 audio interruption/headset policy

	func testRoutePolicyCollapsesToEarpieceWhenRestricted() {
		let routes = BlountAudioRoutePolicy.allowedRoutes(restrictedToEarpiece: true)
		XCTAssertEqual(routes, [.earpiece])
	}

	func testRoutePolicyFullSetWhenUnrestricted() {
		let routes = BlountAudioRoutePolicy.allowedRoutes(restrictedToEarpiece: false)
		XCTAssertTrue(routes.contains(.speaker))
		XCTAssertTrue(routes.contains(.bluetooth))
		XCTAssertTrue(routes.contains(.earpiece))
	}
}
