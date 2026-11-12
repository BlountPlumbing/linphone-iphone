//
//  BlountTransferMachineTests.swift
//  Atom 4.27 — transfer event-sequence tests.
//  Covers: local method return is NOT remote confirmation; consultation hold
//  preserves the original call; cancel/failure restores controls.
//

import XCTest
import linphonesw
@testable import LinphoneApp

final class BlountTransferMachineTests: XCTestCase {

	private func dest() -> BlountDialDestination {
		BlountDialDestination(kind: .ext, address: "101", reviewLabel: "Extension 101")
	}

	// Local transferTo() returning is never remote confirmation.
	func testLocalMethodReturnIsNotRemoteConfirmation() {
		var m = BlountTransferMachine()
		m.reduce(.reviewOpened)
		m.reduce(.destinationConfirmed(dest()))
		m.reduce(.transferRequested)          // local method returned
		XCTAssertEqual(m.state, .requested)
		XCTAssertNotEqual(m.state, .remoteConfirmed)
	}

	// Remote StreamsRunning is the only path to remoteConfirmed.
	func testRemoteStreamsRunningConfirms() {
		var m = BlountTransferMachine()
		m.reduce(.reviewOpened)
		m.reduce(.destinationConfirmed(dest()))
		m.reduce(.transferRequested)
		m.reduce(.remoteStateChanged(.StreamsRunning))
		XCTAssertEqual(m.state, .remoteConfirmed)
	}

	// Consultation hold keeps original call id until terminal state.
	func testConsultationHoldPreservesOriginal() {
		var m = BlountTransferMachine()
		m.reduce(.reviewOpened)
		m.reduce(.destinationConfirmed(dest()))
		m.beginConsultation(originalCallID: "call-abc")
		XCTAssertTrue(m.consultationHeld)
		XCTAssertEqual(m.originalCallID, "call-abc")
		m.reduce(.remoteStateChanged(.Paused))
		XCTAssertEqual(m.state, .pending)
		XCTAssertTrue(m.consultationHeld)      // still held through pending
	}

	// Cancel restores: machine resets, hold released, ids cleared.
	func testCancelRestoresOriginal() {
		var m = BlountTransferMachine()
		m.reduce(.reviewOpened)
		m.reduce(.destinationConfirmed(dest()))
		m.beginConsultation(originalCallID: "call-abc")
		m.reduce(.cancelledByUser)
		XCTAssertEqual(m.state, .cancelled)
		m.restoreAfterCancelOrFailure()
		XCTAssertEqual(m.state, .idle)
		XCTAssertFalse(m.consultationHeld)
		XCTAssertNil(m.originalCallID)
	}

	// Remote End while pending = failure, then restore works.
	func testRemoteEndWhilePendingFailsThenRestores() {
		var m = BlountTransferMachine()
		m.reduce(.reviewOpened)
		m.reduce(.destinationConfirmed(dest()))
		m.reduce(.transferRequested)
		m.reduce(.remoteStateChanged(.Paused))
		m.reduce(.remoteStateChanged(.End))
		XCTAssertEqual(m.state, .failed)
		m.restoreAfterCancelOrFailure()
		XCTAssertEqual(m.state, .idle)
	}

	// Error during requested maps to failed immediately.
	func testErrorDuringRequestedFails() {
		var m = BlountTransferMachine()
		m.reduce(.reviewOpened)
		m.reduce(.destinationConfirmed(dest()))
		m.reduce(.transferRequested)
		m.reduce(.remoteStateChanged(.Error))
		XCTAssertEqual(m.state, .failed)
	}
}
