import XCTest
@testable import HotelFrontDesk

/// Tests for analytics calculation logic.
/// Since AnalyticsViewModel is @MainActor and depends on CloudKitService,
/// we test the calculation logic by setting published properties directly.
@MainActor
final class AnalyticsCalculationTests: XCTestCase {

    private var vm: AnalyticsViewModel!

    override func setUp() {
        super.setUp()
        vm = AnalyticsViewModel()
        vm.selectedYear = 2026
        vm.selectedMonth = 3
    }

    // MARK: - Monthly Revenue

    func testMonthlyRevenue_basic() {
        vm.monthlyReservations = [
            makeReservation(nights: 2, dailyRate: 288), // ¥576
            makeReservation(nights: 3, dailyRate: 388), // ¥1164
        ]
        XCTAssertEqual(vm.monthlyRevenue, 576 + 1164, accuracy: 0.01)
    }

    func testMonthlyRevenue_empty() {
        vm.monthlyReservations = []
        XCTAssertEqual(vm.monthlyRevenue, 0)
    }

    // MARK: - Revenue Change

    func testRevenueChange_increase() {
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 200)] // ¥200
        vm.previousMonthReservations = [makeReservation(nights: 1, dailyRate: 100)] // ¥100
        // (200 - 100) / 100 * 100 = 100%
        XCTAssertEqual(vm.revenueChange!, 100, accuracy: 0.01)
    }

    func testRevenueChange_decrease() {
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 100)] // ¥100
        vm.previousMonthReservations = [makeReservation(nights: 1, dailyRate: 200)] // ¥200
        // (100 - 200) / 200 * 100 = -50%
        XCTAssertEqual(vm.revenueChange!, -50, accuracy: 0.01)
    }

    func testRevenueChange_noPreviousMonth_returnsNil() {
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 200)]
        vm.previousMonthReservations = []
        XCTAssertNil(vm.revenueChange, "No previous data should return nil, not crash")
    }

    // MARK: - ADR (Average Daily Rate)

    func testADR_basic() {
        vm.monthlyReservations = [
            makeReservation(nights: 2, dailyRate: 300), // ¥600, 2 nights
            makeReservation(nights: 3, dailyRate: 200), // ¥600, 3 nights
        ]
        // Total revenue: ¥1200, Total nights: 5, ADR = 240
        XCTAssertEqual(vm.averageDailyRate, 240, accuracy: 0.01)
    }

    func testADR_noReservations_returnsZero() {
        vm.monthlyReservations = []
        XCTAssertEqual(vm.averageDailyRate, 0)
    }

    func testADR_change() {
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 300)]
        vm.previousMonthReservations = [makeReservation(nights: 1, dailyRate: 200)]
        // ADR change: (300-200)/200*100 = 50%
        XCTAssertEqual(vm.adrChange!, 50, accuracy: 0.01)
    }

    func testADR_change_noPreviousMonth_returnsNil() {
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 300)]
        vm.previousMonthReservations = []
        XCTAssertNil(vm.adrChange)
    }

    // MARK: - Total Nights

    func testTotalNights() {
        vm.monthlyReservations = [
            makeReservation(nights: 2, dailyRate: 100),
            makeReservation(nights: 5, dailyRate: 100),
        ]
        XCTAssertEqual(vm.totalNights, 7)
    }

    // MARK: - Occupancy Rate

    func testOccupancyRate_basic() {
        vm.allRooms = makeRooms(count: 10)
        // March 2026 has 31 days. Total room-nights: 10 × 31 = 310
        // If 5 rooms occupied every day: 5 × 31 = 155
        vm.dailyOccupancyData = (1...31).map { (day: $0, count: 5) }
        let expected = 155.0 / 310.0 * 100 // 50%
        XCTAssertEqual(vm.occupancyRate, expected, accuracy: 0.01)
    }

    func testOccupancyRate_noRooms_returnsZero() {
        vm.allRooms = []
        vm.dailyOccupancyData = [(day: 1, count: 5)]
        XCTAssertEqual(vm.occupancyRate, 0, "Should not crash with 0 rooms")
    }

    func testOccupancyRate_fullOccupancy() {
        vm.allRooms = makeRooms(count: 10)
        vm.dailyOccupancyData = (1...31).map { (day: $0, count: 10) }
        XCTAssertEqual(vm.occupancyRate, 100, accuracy: 0.01)
    }

    func testOccupancyRate_excludesMaintenanceRoomsFromDenominator() {
        var rooms = makeRooms(count: 10)
        rooms[8].status = .maintenance
        rooms[9].status = .maintenance
        vm.allRooms = rooms
        vm.dailyOccupancyData = (1...31).map { (day: $0, count: 4) }
        XCTAssertEqual(vm.occupancyRate, 50, accuracy: 0.01)
    }

    func testOccupancyRate_empty() {
        vm.allRooms = makeRooms(count: 10)
        vm.dailyOccupancyData = (1...31).map { (day: $0, count: 0) }
        XCTAssertEqual(vm.occupancyRate, 0, accuracy: 0.01)
    }

    // MARK: - Occupancy Change

    func testOccupancyChange_returnsPercentagePointDifference() {
        vm.allRooms = makeRooms(count: 10)
        vm.selectedYear = 2026
        vm.selectedMonth = 3
        // Current month: 50% (5 out of 10 rooms each day)
        vm.dailyOccupancyData = (1...31).map { (day: $0, count: 5) }
        // Previous month (Feb): 30% (3 out of 10 rooms each day)
        vm.prevDailyOccupancyData = (1...28).map { (day: $0, count: 3) }
        // occupancyChange = 50 - ~30 = ~20 pp
        XCTAssertNotNil(vm.occupancyChange)
        XCTAssertGreaterThan(vm.occupancyChange!, 0, "Should show increase")
    }

    func testOccupancyChange_noPrevious_returnsNil() {
        vm.allRooms = makeRooms(count: 10)
        vm.dailyOccupancyData = (1...31).map { (day: $0, count: 5) }
        vm.previousMonthReservations = []
        XCTAssertNil(vm.occupancyChange)
    }

    // MARK: - Daily Revenue Data

    func testDailyRevenueData_aggregatesByDay() {
        let march10 = date(2026, 3, 10, hour: 12)
        let march15 = date(2026, 3, 15, hour: 12)
        vm.monthlyReservations = [
            makeReservation(nights: 1, dailyRate: 200, checkOutDay: march10),
            makeReservation(nights: 1, dailyRate: 300, checkOutDay: march10),
            makeReservation(nights: 1, dailyRate: 500, checkOutDay: march15),
        ]
        let data = vm.dailyRevenueData
        XCTAssertEqual(data.count, 31, "Should have entry for every day of month")
        XCTAssertEqual(data[9].revenue, 500, accuracy: 0.01, "Day 10 should have ¥200+¥300")
        XCTAssertEqual(data[14].revenue, 500, accuracy: 0.01, "Day 15 should have ¥500")
        XCTAssertEqual(data[0].revenue, 0, "Day 1 should have 0")
    }

    // MARK: - Daily Occupancy Rates

    func testDailyOccupancyRates_capsAt100() {
        vm.allRooms = makeRooms(count: 5)
        // Report more occupied than total rooms (data inconsistency)
        vm.dailyOccupancyData = [(day: 1, count: 10)]
        let rates = vm.dailyOccupancyRates
        XCTAssertEqual(rates.first?.rate, 100, "Should cap at 100%")
    }

    func testDailyOccupancyRates_noRooms_returnsEmpty() {
        vm.allRooms = []
        vm.dailyOccupancyData = [(day: 1, count: 5)]
        XCTAssertTrue(vm.dailyOccupancyRates.isEmpty)
    }

    // MARK: - Room Type Breakdown

    func testRoomTypeBreakdown_groupsByType() {
        let kingRoom = makeRoom(id: "r1", type: .king)
        let twinRoom = makeRoom(id: "r2", type: .twin)
        vm.allRooms = [kingRoom, twinRoom]
        vm.monthlyReservations = [
            makeReservation(nights: 1, dailyRate: 300, roomID: "r1"),
            makeReservation(nights: 1, dailyRate: 200, roomID: "r1"),
            makeReservation(nights: 1, dailyRate: 250, roomID: "r2"),
        ]
        let breakdown = vm.roomTypeBreakdown
        XCTAssertEqual(breakdown.count, 2)
        let king = breakdown.first { $0.type == "大床房" }
        let twin = breakdown.first { $0.type == "双床房" }
        XCTAssertEqual(king?.revenue ?? 0, 500, accuracy: 0.01)
        XCTAssertEqual(king?.count, 2)
        XCTAssertEqual(twin?.revenue ?? 0, 250, accuracy: 0.01)
        XCTAssertEqual(twin?.count, 1)
    }

    // MARK: - Room Ranking

    func testTopRooms_sortedByRevenue_limited10() {
        var rooms: [Room] = []
        var reservations: [Reservation] = []
        for i in 1...15 {
            let room = makeRoom(id: "r\(i)", type: .king)
            rooms.append(room)
            reservations.append(makeReservation(nights: 1, dailyRate: Double(i * 100), roomID: "r\(i)"))
        }
        vm.allRooms = rooms
        vm.monthlyReservations = reservations
        let top = vm.topRooms
        XCTAssertEqual(top.count, 10, "Should limit to 10")
        XCTAssertEqual(top.first?.revenue ?? 0, 1500, accuracy: 0.01, "Highest revenue first")
        XCTAssertEqual(top.last?.revenue ?? 0, 600, accuracy: 0.01, "10th highest")
    }

    // MARK: - Guest Ranking

    func testTopGuests_sortedByCount() {
        let guest1 = Guest(id: "g1", name: "张三", idType: .idCard, idNumber: "123", phone: "13800000001")
        let guest2 = Guest(id: "g2", name: "李四", idType: .idCard, idNumber: "456", phone: "13800000002")

        var res1 = makeReservation(nights: 1, dailyRate: 100, guestID: "g1")
        res1.guest = guest1
        var res2 = makeReservation(nights: 1, dailyRate: 100, guestID: "g1")
        res2.guest = guest1
        var res3 = makeReservation(nights: 1, dailyRate: 200, guestID: "g2")
        res3.guest = guest2

        vm.monthlyReservations = [res1, res2, res3]
        let top = vm.topGuests
        XCTAssertEqual(top.first?.name, "张三", "Guest with most visits first")
        XCTAssertEqual(top.first?.count, 2)
        XCTAssertEqual(top.last?.name, "李四")
    }

    func testTopGuests_masksPhoneNumbers() {
        let guest = Guest(id: "g1", name: "张三", idType: .idCard, idNumber: "123", phone: "13800000001")
        var res = makeReservation(nights: 1, dailyRate: 100, guestID: "g1")
        res.guest = guest

        vm.monthlyReservations = [res]

        XCTAssertEqual(vm.topGuests.first?.phone, "138****0001")
    }

    // MARK: - Cost & Profit

    func testMonthlyCost_sumsAllRoomCosts() {
        vm.allRooms = [
            makeRoom(id: "r1", type: .king),  // 1500
            makeRoom(id: "r2", type: .king),  // 1500
        ]
        XCTAssertEqual(vm.monthlyCost, 3000, accuracy: 0.01)
    }

    func testMonthlyProfit_revenueMinusCost() {
        vm.allRooms = makeRooms(count: 2) // 2 × 1500 = 3000 cost
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 5000)] // 5000 revenue
        XCTAssertEqual(vm.monthlyProfit, 2000, accuracy: 0.01)
    }

    func testMonthlyProfit_negative() {
        vm.allRooms = makeRooms(count: 10) // 10 × 1500 = 15000 cost
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 1000)] // 1000 revenue
        XCTAssertEqual(vm.monthlyProfit, -14000, accuracy: 0.01)
    }

    func testProfitMargin() {
        vm.allRooms = makeRooms(count: 1) // 1500 cost
        vm.monthlyReservations = [makeReservation(nights: 1, dailyRate: 3000)] // 3000 revenue
        // profit = 1500, margin = 1500/3000 * 100 = 50%
        XCTAssertEqual(vm.profitMargin, 50, accuracy: 0.01)
    }

    func testProfitMargin_noRevenue_returnsZero() {
        vm.allRooms = makeRooms(count: 5)
        vm.monthlyReservations = []
        XCTAssertEqual(vm.profitMargin, 0)
    }

    // MARK: - Month Navigation

    func testMonthTitle() {
        vm.selectedYear = 2026
        vm.selectedMonth = 3
        XCTAssertEqual(vm.monthTitle, "2026年3月")
    }

    func testDaysInSelectedMonth_march() {
        vm.selectedYear = 2026
        vm.selectedMonth = 3
        XCTAssertEqual(vm.daysInSelectedMonth, 31)
    }

    func testDaysInSelectedMonth_february_nonLeap() {
        vm.selectedYear = 2026
        vm.selectedMonth = 2
        XCTAssertEqual(vm.daysInSelectedMonth, 28)
    }

    func testDaysInSelectedMonth_february_leap() {
        vm.selectedYear = 2028
        vm.selectedMonth = 2
        XCTAssertEqual(vm.daysInSelectedMonth, 29)
    }

    func testGoToNextMonth_december_wrapsToJanuary() {
        vm.selectedYear = 2026
        vm.selectedMonth = 12
        vm.goToNextMonth()
        XCTAssertEqual(vm.selectedYear, 2027)
        XCTAssertEqual(vm.selectedMonth, 1)
    }

    func testGoToPreviousMonth_january_wrapsToDecember() {
        vm.selectedYear = 2026
        vm.selectedMonth = 1
        vm.goToPreviousMonth()
        XCTAssertEqual(vm.selectedYear, 2025)
        XCTAssertEqual(vm.selectedMonth, 12)
    }

    // MARK: - Helpers

    private func makeReservation(
        nights: Int,
        dailyRate: Double,
        roomID: String = "room-1",
        guestID: String = "guest-1",
        checkOutDay: Date? = nil
    ) -> Reservation {
        let checkOut = checkOutDay ?? date(2026, 3, 15, hour: 12)
        let checkIn = Calendar.current.date(byAdding: .day, value: -nights, to: checkOut)!
        return Reservation(
            id: UUID().uuidString,
            guestID: guestID,
            roomID: roomID,
            checkInDate: checkIn,
            expectedCheckOut: checkOut,
            actualCheckOut: checkOut,
            isActive: false,
            numberOfGuests: 1,
            dailyRate: dailyRate
        )
    }

    private func makeRooms(count: Int) -> [Room] {
        (1...count).map { i in
            Room(id: "r\(i)", roomNumber: "\(100 + i)", floor: 1,
                 roomType: .king, orientation: .south,
                 status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500)
        }
    }

    private func makeRoom(id: String, type: RoomType) -> Room {
        Room(id: id, roomNumber: id, floor: 1,
             roomType: type, orientation: .south,
             status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
