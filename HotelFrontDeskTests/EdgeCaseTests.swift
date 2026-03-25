import XCTest
@testable import HotelFrontDesk

/// 第1组：极端边界测试 — 空数据、零值、负值、超大值
@MainActor
final class EdgeCaseTests: XCTestCase {

    // MARK: - 零房间场景

    func testAnalytics_zeroRooms_nocrash() {
        let vm = AnalyticsViewModel()
        vm.allRooms = []
        vm.monthlyReservations = []
        vm.dailyOccupancyData = []
        vm.prevDailyOccupancyData = []

        XCTAssertEqual(vm.monthlyRevenue, 0)
        XCTAssertEqual(vm.occupancyRate, 0)
        XCTAssertEqual(vm.averageDailyRate, 0)
        XCTAssertEqual(vm.monthlyCost, 0)
        XCTAssertEqual(vm.monthlyProfit, 0)
        XCTAssertEqual(vm.profitMargin, 0)
        XCTAssertNil(vm.revenueChange)
        XCTAssertNil(vm.adrChange)
        XCTAssertNil(vm.profitChange)
        XCTAssertNil(vm.occupancyChange)
        XCTAssertTrue(vm.dailyRevenueData.isEmpty || vm.dailyRevenueData.allSatisfy { $0.revenue == 0 })
        XCTAssertTrue(vm.dailyOccupancyRates.isEmpty)
        XCTAssertTrue(vm.roomTypeBreakdown.isEmpty)
        XCTAssertTrue(vm.topRooms.isEmpty)
        XCTAssertTrue(vm.topGuests.isEmpty)
    }

    // MARK: - 同日入住退房（0晚）

    func testReservation_sameDayCheckout_minimum1Night() {
        let date = Date()
        let res = Reservation(
            id: "same-day", guestID: "g1", roomID: "r1",
            checkInDate: date, expectedCheckOut: date,
            actualCheckOut: date, isActive: false,
            numberOfGuests: 1, dailyRate: 200
        )
        XCTAssertEqual(res.nightsStayed, 1, "Same-day should count as 1 night minimum")
        XCTAssertEqual(res.totalRevenue, 200)
    }

    // MARK: - 数据损坏：入住日期晚于退房日期

    func testReservation_checkInAfterCheckOut_clampedTo1() {
        let checkIn = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let checkOut = Date()
        let res = Reservation(
            id: "corrupt", guestID: "g1", roomID: "r1",
            checkInDate: checkIn, expectedCheckOut: checkOut,
            actualCheckOut: checkOut, isActive: false,
            numberOfGuests: 1, dailyRate: 300
        )
        // Should clamp to 1, not crash or go negative
        XCTAssertEqual(res.nightsStayed, 1)
        XCTAssertEqual(res.totalRevenue, 300)
    }

    // MARK: - 零房价

    func testReservation_zeroDailyRate() {
        let checkIn = Date()
        let checkOut = Calendar.current.date(byAdding: .day, value: 3, to: checkIn)!
        let res = Reservation(
            id: "free", guestID: "g1", roomID: "r1",
            checkInDate: checkIn, expectedCheckOut: checkOut,
            actualCheckOut: checkOut, isActive: false,
            numberOfGuests: 1, dailyRate: 0
        )
        XCTAssertEqual(res.totalRevenue, 0)
    }

    // MARK: - 押金：退款超过余额验证

    func testDeposit_refundExceedsBalance() {
        let records = [
            DepositRecord(id: "d1", reservationID: "r1", type: .collect, amount: 500, paymentMethod: .cash, timestamp: Date()),
            DepositRecord(id: "d2", reservationID: "r1", type: .refund, amount: 600, paymentMethod: .cash, timestamp: Date()),
        ]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.balance, -100, "Over-refund should show negative balance")
    }

    // MARK: - 押金：无记录

    func testDeposit_emptyRecords() {
        let summary = DepositSummary(records: [])
        XCTAssertEqual(summary.totalCollected, 0)
        XCTAssertEqual(summary.totalRefunded, 0)
        XCTAssertEqual(summary.balance, 0)
    }

    // MARK: - 超大金额

    func testDeposit_veryLargeAmount() {
        let records = [
            DepositRecord(id: "d1", reservationID: "r1", type: .collect, amount: 9_999_999, paymentMethod: .bankCard, timestamp: Date()),
        ]
        let summary = DepositSummary(records: records)
        XCTAssertEqual(summary.balance, 9_999_999)
    }

    // MARK: - 枚举完整性

    func testAllEnumCases_roomStatus() {
        XCTAssertEqual(RoomStatus.allCases.count, 5)
        for status in RoomStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty)
            XCTAssertFalse(status.icon.isEmpty)
            XCTAssertFalse(status.rawValue.isEmpty)
        }
    }

    func testAllEnumCases_paymentMethod() {
        XCTAssertEqual(PaymentMethod.allCases.count, 6)
        for method in PaymentMethod.allCases {
            XCTAssertFalse(method.rawValue.isEmpty)
            XCTAssertFalse(method.icon.isEmpty)
        }
    }

    func testAllEnumCases_otaPlatform() {
        XCTAssertEqual(OTAPlatform.allCases.count, 7)
        for platform in OTAPlatform.allCases {
            XCTAssertFalse(platform.icon.isEmpty)
        }
    }

    func testOTABooking_platformDisplayName_usesCustomOtherPlatform() {
        let booking = OTABooking(
            platform: .other,
            customPlatformName: "同程",
            guestName: "张三",
            roomType: .king,
            checkInDate: Date(),
            nights: 1,
            price: 288
        )

        XCTAssertEqual(booking.platformDisplayName, "同程")
    }

    func testOTABookingImageRecognizer_parsesKnownPlatformScreenshotText() {
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let result = OTABookingImageRecognizer.parseRecognizedTexts([
            "美团订单",
            "订单号 MT20260326001",
            "客人姓名 张三",
            "联系电话 13800138000",
            "房型 大床房",
            "入住日期 2026年3月26日",
            "退房日期 2026年3月27日",
            "总价 ¥268"
        ], referenceDate: referenceDate)

        XCTAssertEqual(result.platform, .meituan)
        XCTAssertEqual(result.platformOrderID, "MT20260326001")
        XCTAssertEqual(result.guestName, "张三")
        XCTAssertEqual(result.guestPhone, "13800138000")
        XCTAssertEqual(result.roomType, .king)
        XCTAssertEqual(result.nights, 1)
        XCTAssertEqual(result.nightlyPrice, 268)
    }

    func testOTABookingImageRecognizer_parsesOtherPlatformAndNightlyPrice() {
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let result = OTABookingImageRecognizer.parseRecognizedTexts([
            "同程旅行",
            "预订编号 TC-998877",
            "入住人 李四",
            "联系电话 13900139000",
            "双床房",
            "入住 2026-04-02",
            "离店 2026-04-05",
            "每晚价格 318"
        ], referenceDate: referenceDate)

        XCTAssertEqual(result.platform, .other)
        XCTAssertEqual(result.customPlatformName, "同程")
        XCTAssertEqual(result.platformOrderID, "TC-998877")
        XCTAssertEqual(result.guestName, "李四")
        XCTAssertEqual(result.roomType, .twin)
        XCTAssertEqual(result.nights, 3)
        XCTAssertEqual(result.nightlyPrice, 318)
    }
}
