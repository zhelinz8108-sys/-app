import XCTest
@testable import HotelFrontDesk

/// 第2组：动态定价严格测试 — 周末/平日/特殊日期/跨月/闰年
@MainActor
final class PricingTests: XCTestCase {

    private var pricing: PricingService!
    private var room: Room!

    override func setUp() {
        super.setUp()
        pricing = PricingService.shared
        // 清除特殊日期
        for item in pricing.fetchAll() {
            pricing.deleteSpecialDate(id: item.id)
        }
        room = Room(
            id: "test-room", roomNumber: "101", floor: 1,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 300,
            weekendPrice: 400, monthlyCost: 1500
        )
    }

    // MARK: - 平日价

    func testWeekdayPrice() {
        // 找一个周二（一定是平日）
        let tuesday = nextWeekday(from: Date(), weekday: 3) // 3 = Tuesday
        let price = pricing.priceForNight(room: room, date: tuesday)
        XCTAssertEqual(price, 300, "Tuesday should use weekday price")
    }

    // MARK: - 周末价

    func testWeekendPrice_friday() {
        let friday = nextWeekday(from: Date(), weekday: 6) // 6 = Friday
        let price = pricing.priceForNight(room: room, date: friday)
        XCTAssertEqual(price, 400, "Friday should use weekend price")
    }

    func testWeekendPrice_saturday() {
        let saturday = nextWeekday(from: Date(), weekday: 7) // 7 = Saturday
        let price = pricing.priceForNight(room: room, date: saturday)
        XCTAssertEqual(price, 400, "Saturday should use weekend price")
    }

    func testSundayIsWeekday() {
        let sunday = nextWeekday(from: Date(), weekday: 1) // 1 = Sunday
        let price = pricing.priceForNight(room: room, date: sunday)
        XCTAssertEqual(price, 300, "Sunday should use weekday price")
    }

    // MARK: - 特殊日期覆盖

    func testSpecialDateOverridesWeekend() {
        let friday = nextWeekday(from: Date(), weekday: 6)
        pricing.addSpecialDate(SpecialDatePrice(
            name: "测试特价",
            startDate: friday,
            endDate: friday,
            priceByRoomType: [RoomType.king.rawValue: 199]
        ))
        let price = pricing.priceForNight(room: room, date: friday)
        XCTAssertEqual(price, 199, "Special date should override weekend price")

        // 清理
        for item in pricing.fetchAll() { pricing.deleteSpecialDate(id: item.id) }
    }

    // MARK: - 多晚价格明细

    func testPriceBreakdown_mixedWeekdayWeekend() {
        // 从周四到周日 = 3晚（周四平日、周五周末、周六周末）
        let thursday = nextWeekday(from: Date(), weekday: 5) // 5 = Thursday
        let sunday = Calendar.current.date(byAdding: .day, value: 3, to: thursday)!

        let breakdown = pricing.priceBreakdown(room: room, checkIn: thursday, checkOut: sunday)
        XCTAssertEqual(breakdown.count, 3)

        let weekdayNights = breakdown.filter { $0.priceType == .weekday }.count
        let weekendNights = breakdown.filter { $0.priceType == .weekend }.count
        XCTAssertEqual(weekdayNights, 1, "Thursday is weekday")
        XCTAssertEqual(weekendNights, 2, "Friday + Saturday are weekend")

        let total = pricing.totalPrice(room: room, checkIn: thursday, checkOut: sunday)
        XCTAssertEqual(total, 300 + 400 + 400, accuracy: 0.01) // 1100
    }

    // MARK: - 同日退房

    func testPriceBreakdown_sameDayCheckout_minimum1Night() {
        let today = Date()
        let breakdown = pricing.priceBreakdown(room: room, checkIn: today, checkOut: today)
        XCTAssertEqual(breakdown.count, 1, "Same-day should have at least 1 night")
        XCTAssertGreaterThan(breakdown.first?.price ?? 0, 0)
    }

    // MARK: - 无周末价设置

    func testWeekendPrice_zeroFallsBackToWeekday() {
        let noWeekendRoom = Room(
            id: "r2", roomNumber: "102", floor: 1,
            roomType: .twin, orientation: .south,
            status: .vacant, pricePerNight: 250,
            weekendPrice: 0, monthlyCost: 1000
        )
        let friday = nextWeekday(from: Date(), weekday: 6)
        let price = pricing.priceForNight(room: noWeekendRoom, date: friday)
        XCTAssertEqual(price, 250, "Zero weekend price should fallback to weekday price")
    }

    // MARK: - 平均每晚

    func testAverageNightlyRate() {
        let thursday = nextWeekday(from: Date(), weekday: 5)
        let sunday = Calendar.current.date(byAdding: .day, value: 3, to: thursday)!
        let avg = pricing.averageNightlyRate(room: room, checkIn: thursday, checkOut: sunday)
        let expected = (300.0 + 400 + 400) / 3.0
        XCTAssertEqual(avg, expected, accuracy: 0.01)
    }

    // MARK: - Helper

    private func nextWeekday(from date: Date, weekday: Int) -> Date {
        let cal = Calendar.current
        var current = cal.startOfDay(for: date)
        for _ in 0..<7 {
            if cal.component(.weekday, from: current) == weekday { return current }
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return current
    }
}
