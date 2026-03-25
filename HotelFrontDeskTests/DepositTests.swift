import XCTest
@testable import HotelFrontDesk

final class DepositTests: XCTestCase {

    // MARK: - DepositSummary

    func testSummary_singleCollect() {
        let records = [makeDeposit(type: .collect, amount: 500)]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.totalCollected, 500)
        XCTAssertEqual(summary.totalRefunded, 0)
        XCTAssertEqual(summary.balance, 500)
    }

    func testSummary_collectAndPartialRefund() {
        let records = [
            makeDeposit(type: .collect, amount: 500),
            makeDeposit(type: .refund, amount: 200)
        ]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.totalCollected, 500)
        XCTAssertEqual(summary.totalRefunded, 200)
        XCTAssertEqual(summary.balance, 300)
    }

    func testSummary_collectAndFullRefund() {
        let records = [
            makeDeposit(type: .collect, amount: 500),
            makeDeposit(type: .refund, amount: 500)
        ]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.balance, 0)
    }

    func testSummary_multipleCollectsAndRefunds() {
        let records = [
            makeDeposit(type: .collect, amount: 300),
            makeDeposit(type: .collect, amount: 200),
            makeDeposit(type: .refund, amount: 100),
            makeDeposit(type: .refund, amount: 150)
        ]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.totalCollected, 500)
        XCTAssertEqual(summary.totalRefunded, 250)
        XCTAssertEqual(summary.balance, 250)
    }

    func testSummary_emptyRecords() {
        let summary = DepositSummary(records: [])
        XCTAssertEqual(summary.totalCollected, 0)
        XCTAssertEqual(summary.totalRefunded, 0)
        XCTAssertEqual(summary.balance, 0)
    }

    func testSummary_onlyRefunds_negativeBalance() {
        let records = [makeDeposit(type: .refund, amount: 100)]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.balance, -100, "Refund without collect should produce negative balance")
    }

    // MARK: - Helpers

    private func makeDeposit(type: DepositType, amount: Double) -> DepositRecord {
        DepositRecord(
            id: UUID().uuidString,
            reservationID: "res-1",
            type: type,
            amount: amount,
            paymentMethod: .cash,
            timestamp: Date()
        )
    }
}
