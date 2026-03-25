import XCTest
@testable import HotelFrontDesk

/// Tests for CheckOutViewModel validation logic.
@MainActor
final class CheckOutValidationTests: XCTestCase {

    private var vm: CheckOutViewModel!

    override func setUp() {
        super.setUp()
        vm = CheckOutViewModel()
    }

    // MARK: - canRefund

    func testCanRefund_validAmount() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500)
        ]
        vm.refundAmount = "300"
        XCTAssertTrue(vm.canRefund)
    }

    func testCanRefund_fullBalance() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500)
        ]
        vm.refundAmount = "500"
        XCTAssertTrue(vm.canRefund)
    }

    func testCanRefund_exceedsBalance() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500)
        ]
        vm.refundAmount = "600"
        XCTAssertFalse(vm.canRefund, "Should not allow refund exceeding balance")
    }

    func testCanRefund_zeroAmount() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500)
        ]
        vm.refundAmount = "0"
        XCTAssertFalse(vm.canRefund, "Should not allow zero refund")
    }

    func testCanRefund_emptyAmount() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500)
        ]
        vm.refundAmount = ""
        XCTAssertFalse(vm.canRefund)
    }

    func testCanRefund_noDeposits() {
        vm.depositRecords = []
        vm.refundAmount = "100"
        XCTAssertFalse(vm.canRefund, "Should not refund when no deposits collected")
    }

    func testCanRefund_afterPartialRefund() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500),
            makeDeposit(type: .refund, amount: 200)
        ]
        vm.refundAmount = "300" // exactly remaining balance
        XCTAssertTrue(vm.canRefund)
    }

    func testCanRefund_afterPartialRefund_exceedsRemaining() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500),
            makeDeposit(type: .refund, amount: 200)
        ]
        vm.refundAmount = "301" // exceeds remaining ¥300
        XCTAssertFalse(vm.canRefund)
    }

    func testCanRefund_invalidString() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500)
        ]
        vm.refundAmount = "abc"
        XCTAssertFalse(vm.canRefund)
    }

    // MARK: - refundValue

    func testRefundValue_parsesNumber() {
        vm.refundAmount = "299.5"
        XCTAssertEqual(vm.refundValue, 299.5, accuracy: 0.01)
    }

    func testRefundValue_invalidString_returnsZero() {
        vm.refundAmount = "invalid"
        XCTAssertEqual(vm.refundValue, 0)
    }

    // MARK: - depositSummary

    func testDepositSummary_computedFromRecords() {
        vm.depositRecords = [
            makeDeposit(type: .collect, amount: 500),
            makeDeposit(type: .collect, amount: 200),
            makeDeposit(type: .refund, amount: 100),
        ]
        XCTAssertEqual(vm.depositSummary.totalCollected, 700)
        XCTAssertEqual(vm.depositSummary.totalRefunded, 100)
        XCTAssertEqual(vm.depositSummary.balance, 600)
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
