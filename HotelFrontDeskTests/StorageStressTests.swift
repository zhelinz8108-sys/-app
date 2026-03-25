import XCTest
@testable import HotelFrontDesk

/// 第4组：存储压力测试 — 大量数据读写、并发、数据一致性
@MainActor
final class StorageStressTests: XCTestCase {

    private var service: LocalStorageService!

    override func setUp() {
        super.setUp()
        service = LocalStorageService.shared
        service.resetAll()
    }

    override func tearDown() {
        service.resetAll()
        super.tearDown()
    }

    // MARK: - 批量写入

    func testBulkRoomWrite_100rooms() {
        for i in 1...100 {
            let room = Room(
                id: "stress-r\(i)", roomNumber: "\(i)", floor: (i - 1) / 10 + 1,
                roomType: .king, orientation: .south,
                status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
            )
            service.saveRoom(room)
        }
        XCTAssertEqual(service.fetchAllRooms().count, 100)
    }

    func testBulkReservationWrite_500reservations() {
        // 先创建一个房间
        service.saveRoom(Room(
            id: "bulk-room", roomNumber: "999", floor: 1,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        ))

        let cal = Calendar.current
        let today = Date()
        for i in 0..<500 {
            let checkIn = cal.date(byAdding: .day, value: -(i + 1), to: today)!
            let checkOut = cal.date(byAdding: .day, value: -i, to: today)!
            let res = Reservation(
                id: "stress-res-\(i)", guestID: "g1", roomID: "bulk-room",
                checkInDate: checkIn, expectedCheckOut: checkOut,
                actualCheckOut: checkOut, isActive: false,
                numberOfGuests: 1, dailyRate: 288
            )
            service.saveReservation(res)
        }
        XCTAssertEqual(service.fetchAllReservations().count, 500)
    }

    // MARK: - 批量模式性能

    func testBatchMode_skipsIntermediateWrites() {
        service.isBatchMode = true
        for i in 1...50 {
            service.saveRoom(Room(
                id: "batch-\(i)", roomNumber: "\(i)", floor: 1,
                roomType: .twin, orientation: .north,
                status: .vacant, pricePerNight: 200, weekendPrice: 250, monthlyCost: 1000
            ))
        }
        // Data is in memory but not persisted yet
        XCTAssertEqual(service.fetchAllRooms().count, 50)

        service.flushAll()
        XCTAssertEqual(service.fetchAllRooms().count, 50, "After flush, data should still be there")
    }

    // MARK: - 月份查询边界

    func testFetchReservationsForMonth_december() {
        let res = Reservation(
            id: "dec-res", guestID: "g1", roomID: "r1",
            checkInDate: date(2025, 12, 28), expectedCheckOut: date(2025, 12, 31),
            actualCheckOut: date(2025, 12, 31), isActive: false,
            numberOfGuests: 1, dailyRate: 300
        )
        service.saveReservation(res)
        let results = service.fetchReservationsForMonth(year: 2025, month: 12)
        XCTAssertTrue(results.contains { $0.id == "dec-res" })
    }

    func testFetchReservationsForMonth_january() {
        let res = Reservation(
            id: "jan-res", guestID: "g1", roomID: "r1",
            checkInDate: date(2026, 1, 1), expectedCheckOut: date(2026, 1, 3),
            actualCheckOut: date(2026, 1, 3), isActive: false,
            numberOfGuests: 1, dailyRate: 300
        )
        service.saveReservation(res)
        let results = service.fetchReservationsForMonth(year: 2026, month: 1)
        XCTAssertTrue(results.contains { $0.id == "jan-res" })
    }

    // MARK: - 日入住率：跨月预订

    func testDailyOccupancy_crossMonthReservation() {
        service.saveRoom(Room(
            id: "occ-room", roomNumber: "101", floor: 1,
            roomType: .king, orientation: .south,
            status: .occupied, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        ))
        // 入住 1/30 到 2/2（跨月）
        service.saveReservation(Reservation(
            id: "cross-month", guestID: "g1", roomID: "occ-room",
            checkInDate: date(2026, 1, 30), expectedCheckOut: date(2026, 2, 2),
            actualCheckOut: date(2026, 2, 2), isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))

        // 1月应该有1/30和1/31有入住
        let jan = service.fetchDailyOccupancy(year: 2026, month: 1, totalRooms: 1)
        let jan30 = jan.first { $0.day == 30 }
        let jan31 = jan.first { $0.day == 31 }
        XCTAssertEqual(jan30?.count, 1)
        XCTAssertEqual(jan31?.count, 1)

        // 2月应该有2/1有入住，2/2是退房日不算
        let feb = service.fetchDailyOccupancy(year: 2026, month: 2, totalRooms: 1)
        let feb1 = feb.first { $0.day == 1 }
        let feb2 = feb.first { $0.day == 2 }
        XCTAssertEqual(feb1?.count, 1)
        XCTAssertEqual(feb2?.count, 0, "Checkout day should not count as occupied")
    }

    // MARK: - 去重：同一房间多条记录

    func testDailyOccupancy_deduplicatesByRoom() {
        service.saveRoom(Room(
            id: "dup-room", roomNumber: "201", floor: 2,
            roomType: .king, orientation: .south,
            status: .occupied, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        ))
        // 同一房间两条重叠记录（数据异常情况）
        service.saveReservation(Reservation(
            id: "dup1", guestID: "g1", roomID: "dup-room",
            checkInDate: date(2026, 3, 1), expectedCheckOut: date(2026, 3, 5),
            actualCheckOut: date(2026, 3, 5), isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))
        service.saveReservation(Reservation(
            id: "dup2", guestID: "g2", roomID: "dup-room",
            checkInDate: date(2026, 3, 2), expectedCheckOut: date(2026, 3, 4),
            actualCheckOut: date(2026, 3, 4), isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))

        let data = service.fetchDailyOccupancy(year: 2026, month: 3, totalRooms: 1)
        let day3 = data.first { $0.day == 3 }
        XCTAssertEqual(day3?.count, 1, "Same room should only count once even with overlapping reservations")
    }

    func testDailyOccupancy_countsCheckInDayUsingCalendarDayBoundaries() {
        service.saveRoom(Room(
            id: "time-room", roomNumber: "301", floor: 3,
            roomType: .king, orientation: .south,
            status: .occupied, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        ))

        let checkIn = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 15))!
        let checkOut = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 11))!
        service.saveReservation(Reservation(
            id: "time-boundary", guestID: "g1", roomID: "time-room",
            checkInDate: checkIn, expectedCheckOut: checkOut,
            actualCheckOut: checkOut, isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))

        let data = service.fetchDailyOccupancy(year: 2026, month: 3, totalRooms: 1)
        XCTAssertEqual(data.first { $0.day == 1 }?.count, 1, "Check-in day should count even if check-in time is after midnight")
        XCTAssertEqual(data.first { $0.day == 2 }?.count, 0, "Checkout day should not count toward occupancy")
    }

    // MARK: - 删除

    func testDeleteRoom_byID() {
        service.saveRoom(Room(
            id: "del-1", roomNumber: "D1", floor: 1,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 200, weekendPrice: 250, monthlyCost: 1000
        ))
        service.saveRoom(Room(
            id: "del-2", roomNumber: "D2", floor: 1,
            roomType: .twin, orientation: .north,
            status: .vacant, pricePerNight: 180, weekendPrice: 220, monthlyCost: 900
        ))
        XCTAssertEqual(service.fetchAllRooms().count, 2)

        service.deleteRoom(id: "del-1")
        let remaining = service.fetchAllRooms()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "del-2", "Only the targeted room should be deleted")
    }

    func testDeleteGuest() {
        service.saveGuest(Guest(id: "del-g1", name: "张三", idType: .idCard, idNumber: "123", phone: "138"))
        XCTAssertNotNil(service.fetchGuest(id: "del-g1"))
        service.deleteGuest(id: "del-g1")
        XCTAssertNil(service.fetchGuest(id: "del-g1"))
    }

    func testDeleteGuest_cascadesReservationsAndDeposits() {
        service.saveGuest(Guest(id: "cascade-g1", name: "张三", idType: .idCard, idNumber: "123", phone: "13800138000"))
        service.saveReservation(Reservation(
            id: "cascade-res", guestID: "cascade-g1", roomID: "r1",
            checkInDate: date(2026, 3, 1), expectedCheckOut: date(2026, 3, 2),
            actualCheckOut: date(2026, 3, 2), isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))
        service.saveDepositRecord(DepositRecord(
            id: "cascade-deposit", reservationID: "cascade-res",
            type: .collect, amount: 300, paymentMethod: .cash,
            timestamp: date(2026, 3, 1)
        ))

        service.deleteGuest(id: "cascade-g1")

        XCTAssertNil(service.fetchGuest(id: "cascade-g1"))
        XCTAssertFalse(service.fetchAllReservations().contains { $0.id == "cascade-res" })
        XCTAssertTrue(service.fetchDeposits(forReservationID: "cascade-res").isEmpty)
    }

    func testDeleteReservation_cascadesDeposits() {
        service.saveReservation(Reservation(
            id: "delete-res", guestID: "g1", roomID: "r1",
            checkInDate: date(2026, 3, 1), expectedCheckOut: date(2026, 3, 2),
            actualCheckOut: date(2026, 3, 2), isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))
        service.saveDepositRecord(DepositRecord(
            id: "delete-res-deposit", reservationID: "delete-res",
            type: .collect, amount: 200, paymentMethod: .cash,
            timestamp: date(2026, 3, 1)
        ))

        service.deleteReservation(id: "delete-res")

        XCTAssertFalse(service.fetchAllReservations().contains { $0.id == "delete-res" })
        XCTAssertTrue(service.fetchDeposits(forReservationID: "delete-res").isEmpty)
    }

    // MARK: - Helper

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
