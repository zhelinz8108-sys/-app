import XCTest
@testable import HotelFrontDesk

/// 数据一致性验证 — 模拟生成数据后检查逻辑正确性
@MainActor
final class DataIntegrityTests: XCTestCase {

    private var service: LocalStorageService!

    override func setUp() {
        super.setUp()
        service = LocalStorageService.shared
        service.resetAll()

        // 用批量模式快速生成测试数据
        service.isBatchMode = true

        // 10 间房
        for i in 1...10 {
            service.saveRoom(Room(
                id: "integrity-r\(i)", roomNumber: "\(100 + i)", floor: 1,
                roomType: [RoomType.king, .twin, .suite][i % 3],
                orientation: .south, status: .vacant,
                pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
            ))
        }

        // 50 客人
        for i in 1...50 {
            service.saveGuest(Guest(
                id: "integrity-g\(i)", name: "测试客人\(i)",
                idType: .idCard, idNumber: "11010119900101\(String(format: "%04d", i))",
                phone: "138\(String(format: "%08d", i))"
            ))
        }

        // 模拟3个月入住（每间房平均10次）
        let cal = Calendar.current
        let today = Date()
        for roomIdx in 1...10 {
            var dayOffset = -90
            while dayOffset < -1 {
                if Int.random(in: 1...10) <= 3 { dayOffset += Int.random(in: 1...2); continue }
                let nights = Int.random(in: 1...3)
                let checkInDay = dayOffset
                let checkOutDay = min(dayOffset + nights, -1)
                if checkOutDay - checkInDay <= 0 { dayOffset += 1; continue }

                let checkIn = cal.date(byAdding: .day, value: checkInDay, to: today)!
                let checkOut = cal.date(byAdding: .day, value: checkOutDay, to: today)!
                dayOffset = checkOutDay

                let guestIdx = Int.random(in: 1...50)
                let resID = UUID().uuidString
                service.saveReservation(Reservation(
                    id: resID, guestID: "integrity-g\(guestIdx)", roomID: "integrity-r\(roomIdx)",
                    checkInDate: checkIn, expectedCheckOut: checkOut,
                    actualCheckOut: checkOut, isActive: false,
                    numberOfGuests: 1, dailyRate: 288
                ))
                service.saveDepositRecord(DepositRecord(
                    id: UUID().uuidString, reservationID: resID,
                    type: .collect, amount: 500, paymentMethod: .cash, timestamp: checkIn
                ))
                service.saveDepositRecord(DepositRecord(
                    id: UUID().uuidString, reservationID: resID,
                    type: .refund, amount: 500, paymentMethod: .cash, timestamp: checkOut
                ))
            }
        }

        // 5间当前入住
        for i in 1...5 {
            let resID = UUID().uuidString
            service.saveReservation(Reservation(
                id: resID, guestID: "integrity-g\(i)", roomID: "integrity-r\(i)",
                checkInDate: cal.date(byAdding: .day, value: -1, to: today)!,
                expectedCheckOut: cal.date(byAdding: .day, value: 2, to: today)!,
                isActive: true, numberOfGuests: 1, dailyRate: 288
            ))
            service.updateRoomStatus(roomID: "integrity-r\(i)", status: .occupied)
            service.saveDepositRecord(DepositRecord(
                id: UUID().uuidString, reservationID: resID,
                type: .collect, amount: 500, paymentMethod: .wechat, timestamp: today
            ))
        }

        service.flushAll()
    }

    override func tearDown() {
        service.resetAll()
        super.tearDown()
    }

    // MARK: - 1. 房态一致性

    func testRoomStatusMatchesReservations() {
        let rooms = service.fetchAllRooms()
        for room in rooms {
            let activeRes = service.fetchActiveReservation(forRoomID: room.id)
            if room.status == .occupied {
                XCTAssertNotNil(activeRes, "Room \(room.roomNumber) is occupied but has no active reservation")
            }
            if activeRes != nil && room.status == .vacant {
                XCTFail("Room \(room.roomNumber) has active reservation but status is vacant")
            }
        }
    }

    // MARK: - 2. 押金收支平衡

    func testDepositBalanceForCompletedReservations() {
        let allRes = service.fetchAllReservations().filter { !$0.isActive }
        for res in allRes {
            let deposits = service.fetchDeposits(forReservationID: res.id)
            let summary = DepositSummary(records: deposits)
            XCTAssertEqual(summary.balance, 0,
                "Completed reservation \(res.id) has unbalanced deposit: collected=\(summary.totalCollected) refunded=\(summary.totalRefunded)")
        }
    }

    func testDepositBalanceForActiveReservations() {
        let activeRes = service.fetchAllReservations().filter { $0.isActive }
        for res in activeRes {
            let deposits = service.fetchDeposits(forReservationID: res.id)
            let summary = DepositSummary(records: deposits)
            XCTAssertGreaterThanOrEqual(summary.balance, 0,
                "Active reservation \(res.id) has negative deposit balance")
        }
    }

    // MARK: - 3. 营收计算一致性

    func testMonthlyRevenueMatchesReservationTotals() {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let month = cal.component(.month, from: Date())
        let monthRes = service.fetchReservationsForMonth(year: year, month: month)
        let totalRevenue = monthRes.reduce(0) { $0 + $1.totalRevenue }

        // 每条记录的 totalRevenue 应该 = nightsStayed × dailyRate
        for res in monthRes {
            XCTAssertEqual(res.totalRevenue, Double(res.nightsStayed) * res.dailyRate, accuracy: 0.01,
                "Reservation \(res.id) revenue mismatch")
        }

        // 月度总收入应该非负
        XCTAssertGreaterThanOrEqual(totalRevenue, 0)
    }

    // MARK: - 4. 入住率范围检查

    func testOccupancyRateInRange() {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let month = cal.component(.month, from: Date())
        let rooms = service.fetchAllRooms()
        let data = service.fetchDailyOccupancy(year: year, month: month, totalRooms: rooms.count)

        for day in data {
            XCTAssertGreaterThanOrEqual(day.count, 0, "Day \(day.day) has negative occupancy")
            XCTAssertLessThanOrEqual(day.count, rooms.count,
                "Day \(day.day) occupancy \(day.count) exceeds total rooms \(rooms.count)")
        }
    }

    // MARK: - 5. 每间房不能同时有多个 active 预订

    func testNoDoubleBooking() {
        let rooms = service.fetchAllRooms()
        let allActive = service.fetchActiveReservations()

        var roomActiveCount: [String: Int] = [:]
        for res in allActive {
            roomActiveCount[res.roomID, default: 0] += 1
        }

        for (roomID, count) in roomActiveCount {
            let roomNum = rooms.first { $0.id == roomID }?.roomNumber ?? roomID
            XCTAssertEqual(count, 1, "Room \(roomNum) has \(count) active reservations — double booking!")
        }
    }

    // MARK: - 6. nightsStayed 永远 >= 1

    func testNightsStayedAlwaysPositive() {
        let allRes = service.fetchAllReservations()
        for res in allRes {
            XCTAssertGreaterThanOrEqual(res.nightsStayed, 1,
                "Reservation \(res.id) has \(res.nightsStayed) nights — should be >= 1")
        }
    }

    // MARK: - 7. 退房记录必须有 actualCheckOut

    func testCompletedReservationsHaveCheckoutDate() {
        let completed = service.fetchAllReservations().filter { !$0.isActive }
        for res in completed {
            XCTAssertNotNil(res.actualCheckOut,
                "Completed reservation \(res.id) missing actualCheckOut date")
        }
    }

    // MARK: - 8. 客人引用完整性

    func testGuestReferencesValid() {
        let allRes = service.fetchAllReservations()
        for res in allRes {
            let guest = service.fetchGuest(id: res.guestID)
            XCTAssertNotNil(guest, "Reservation \(res.id) references non-existent guest \(res.guestID)")
        }
    }

    // MARK: - 9. 房间引用完整性

    func testRoomReferencesValid() {
        let allRes = service.fetchActiveReservations()
        let roomIDs = Set(service.fetchAllRooms().map(\.id))
        for res in allRes {
            XCTAssertTrue(roomIDs.contains(res.roomID),
                "Reservation \(res.id) references non-existent room \(res.roomID)")
        }
    }

    // MARK: - 10. 月份查询不遗漏

    func testMonthQueryCoversAllCompletedReservations() {
        let allCompleted = service.fetchAllReservations().filter { !$0.isActive }
        let cal = Calendar.current

        var queriedIDs = Set<String>()
        // 查过去6个月
        for monthOffset in 0..<6 {
            guard let monthDate = cal.date(byAdding: .month, value: -monthOffset, to: Date()) else { continue }
            let y = cal.component(.year, from: monthDate)
            let m = cal.component(.month, from: monthDate)
            let monthRes = service.fetchReservationsForMonth(year: y, month: m)
            for res in monthRes { queriedIDs.insert(res.id) }
        }

        // 应该覆盖所有已完成的预订（过去3个月内的）
        let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: Date())!
        let recentCompleted = allCompleted.filter {
            ($0.actualCheckOut ?? $0.expectedCheckOut) >= threeMonthsAgo
        }
        for res in recentCompleted {
            XCTAssertTrue(queriedIDs.contains(res.id),
                "Reservation \(res.id) not found in any monthly query")
        }
    }
}
