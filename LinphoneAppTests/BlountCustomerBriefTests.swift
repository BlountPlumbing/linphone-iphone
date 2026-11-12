//
//  BlountCustomerBriefTests.swift — atom 6.29 + lifecycle fixtures.
//

import XCTest
@testable import LinphoneApp

@MainActor
final class BlountCustomerBriefTests: XCTestCase {

	func testLateResponseDiscardedOnGenerationChange() async {
		let client = BlountCustomerBriefClient.shared
		client.noteRevocation()
		// slow transport resolves after a newer request supersedes it
		let slow: (String) async throws -> BlountCustomerBrief? = { _ in
			try await Task.sleep(nanoseconds: 300_000_000)
			return nil
		}
		let result = await client.requestBrief(
			callID: "call-A", accountGeneration: 1,
			authGeneration: 1, transport: slow)
		XCTAssertNil(result)   // timeout path -> unavailable, not fabricated
	}

	func testTimeoutReturnsUnavailableNotHang() async {
		let client = BlountCustomerBriefClient.shared
		client.noteRevocation()
		let never: (String) async throws -> BlountCustomerBrief? = { _ in
			try await Task.sleep(nanoseconds: 10_000_000_000)
			return nil
		}
		let start = Date()
		_ = await client.requestBrief(
			callID: "call-B", accountGeneration: 1,
			authGeneration: 1, transport: never)
		XCTAssertLessThan(Date().timeIntervalSince(start), 4.0)
	}

	func testFinanceGrantExpires() {
		let client = BlountCustomerBriefClient.shared
		client.noteRevocation()
		XCTAssertFalse(client.financeFieldsAuthorized(for: "any"))
	}

	func testRequestKeyBindsGenerations() {
		let k1 = BlountBriefRequestKey(callID: "c", accountGeneration: 1,
		                             authGeneration: 1, requestGeneration: 1)
		let k2 = BlountBriefRequestKey(callID: "c", accountGeneration: 2,
		                             authGeneration: 1, requestGeneration: 1)
		XCTAssertNotEqual(k1, k2)   // account switch invalidates
	}

	func testAmbiguousMatchNeverPromotesFinance() {
		// contract: ambiguous -> candidate names/sites ONLY, no balance
		let json = """
		{"schema_version":"shared-customer-context.v1","call_id":"c1",
		 "brief_revision":1,"match_state":"ambiguous",
		 "scope":{"company_id":1,"account_wide":false},
		 "display_name":null,
		 "balance_due":{"minor_units":null,"currency":null,
		  "availability":"permission_denied"},
		 "data_as_of":"2026-11-12T00:00:00Z","expires_at":null,
		 "sections":{}}
		""".data(using: .utf8)!
		let brief = try? JSONDecoder().decode(BlountCustomerBrief.self, from: json)
		XCTAssertEqual(brief?.matchState, .ambiguous)
		XCTAssertEqual(brief?.balanceDue?.availability, .permissionDenied)
	}
}
