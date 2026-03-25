import XCTest
@testable import HotelFrontDesk

/// 第5组：完整业务流程集成测试 — 模拟真实操作场景
@MainActor
final class WorkflowIntegrationTests: XCTestCase {

    private var service: LocalStorageService!

    override func setUp() {
        super.setUp()
        service = LocalStorageService.shared
        service.resetAll()
        OTABookingService.shared.bookings = []
    }

    override func tearDown() {
        OTABookingService.shared.bookings = []
        service.resetAll()
        super.tearDown()
    }

    func testOperationLogExport_generatesCSV() throws {
        let logService = OperationLogService.shared
        logService.clearAll()
        defer { logService.clearAll() }

        logService.log(
            type: .checkIn,
            summary: "101房 张三入住",
            detail: "客人: 张三 | 房价: ¥288",
            roomNumber: "101"
        )

        let exportURL = try logService.exportLogs(format: .csv)
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let content = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("101房 张三入住"))
        XCTAssertTrue(content.contains("入住"))
        XCTAssertTrue(content.contains("101"))
    }

    func testBackupExport_includesStaffMetadataAndRecoveryReadme() throws {
        let staffService = StaffService.shared
        staffService.resetForTesting(staff: [
            Staff(name: "管理员", username: "admin", password: "Hotel12345", role: .manager)
        ])
        defer { staffService.resetForTesting() }

        let exportURL = try BackupService.shared.exportBackup()
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let staffFile = exportURL.appendingPathComponent("staff.json")
        let readmeFile = exportURL.appendingPathComponent("README_恢复说明.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: staffFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeFile.path))
    }

    func testDataPackageExport_includesRevenueAndSourceSummary() async throws {
        let room = Room(
            id: "ai-room-101",
            roomNumber: "101",
            floor: 1,
            roomType: .king,
            orientation: .south,
            status: .vacant,
            pricePerNight: 220,
            weekendPrice: 260,
            monthlyCost: 1500
        )
        service.saveRoom(room)

        let guest = Guest(
            id: "ai-guest-zhangsan",
            name: "张三",
            idType: .idCard,
            idNumber: "110101199001011234",
            phone: "13800138000"
        )
        service.saveGuest(guest)

        let reservation = Reservation(
            id: "ai-res-001",
            guestID: guest.id,
            roomID: room.id,
            checkInDate: date(2026, 3, 1),
            expectedCheckOut: date(2026, 3, 3),
            actualCheckOut: date(2026, 3, 3),
            isActive: false,
            numberOfGuests: 1,
            dailyRate: 200
        )
        service.saveReservation(reservation)

        service.saveDepositRecord(
            DepositRecord(
                id: "ai-deposit-collect",
                reservationID: reservation.id,
                type: .collect,
                amount: 300,
                paymentMethod: .wechat,
                timestamp: date(2026, 3, 1)
            )
        )
        service.saveDepositRecord(
            DepositRecord(
                id: "ai-deposit-refund",
                reservationID: reservation.id,
                type: .refund,
                amount: 100,
                paymentMethod: .wechat,
                timestamp: date(2026, 3, 3)
            )
        )

        OTABookingService.shared.bookings = [
            OTABooking(
                id: "ota-ai-001",
                platform: .meituan,
                platformOrderID: "MT-20260301-001",
                guestName: "张三",
                guestPhone: "13800138000",
                roomType: .king,
                checkInDate: date(2026, 3, 1),
                nights: 2,
                price: 180,
                assignedRoomID: room.id,
                assignedRoomNumber: room.roomNumber,
                status: .checkedIn,
                createdBy: "测试前台"
            )
        ]

        let exportURL = try await BackupService.shared.exportDataPackage()
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let bundleURL = exportURL.appendingPathComponent("hotel_data_bundle.json")
        let reservationsCSV = exportURL.appendingPathComponent("reservations_flat.csv")
        let sourceCSV = exportURL.appendingPathComponent("source_revenue_summary.csv")

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reservationsCSV.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceCSV.path))

        let bundleData = try Data(contentsOf: bundleURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bundleData) as? [String: Any])
        let summary = try XCTUnwrap(json["summary"] as? [String: Any])
        XCTAssertEqual(summary["total_rooms"] as? Int, 1)
        XCTAssertEqual(summary["total_reservations"] as? Int, 1)
        XCTAssertEqual(summary["actual_revenue"] as? Double, 400)
        XCTAssertEqual(summary["deposit_balance"] as? Double, 200)

        let reservations = try XCTUnwrap(json["reservations"] as? [[String: Any]])
        let firstReservation = try XCTUnwrap(reservations.first)
        XCTAssertEqual(firstReservation["source_display_name"] as? String, "美团")
        XCTAssertEqual(firstReservation["actual_revenue"] as? Double, 400)
        XCTAssertEqual(firstReservation["projected_revenue"] as? Double, 400)
        XCTAssertEqual(firstReservation["deposit_balance"] as? Double, 200)
        XCTAssertEqual(firstReservation["guest_phone_masked"] as? String, "138****8000")

        let sourceSummaries = try XCTUnwrap(json["source_revenue_summary"] as? [[String: Any]])
        let meituanSummary = try XCTUnwrap(sourceSummaries.first(where: { ($0["source_display_name"] as? String) == "美团" }))
        XCTAssertEqual(meituanSummary["reservation_count"] as? Int, 1)
        XCTAssertEqual(meituanSummary["actual_revenue"] as? Double, 400)
        XCTAssertEqual(meituanSummary["ota_quoted_revenue"] as? Double, 360)
    }

    // MARK: - 场景1：完整入住→退房流程

    func testFullCheckInCheckOutFlow() {
        // 1. 添加房间
        let room = Room(
            id: "flow-room", roomNumber: "101", floor: 1,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 300, weekendPrice: 380, monthlyCost: 1500
        )
        service.saveRoom(room)

        // 2. 添加客人
        let guest = Guest(id: "flow-guest", name: "测试客人", idType: .idCard, idNumber: "110101199001011237", phone: "13800138000")
        service.saveGuest(guest)

        // 3. 创建入住
        let checkIn = Date()
        let checkOut = Calendar.current.date(byAdding: .day, value: 2, to: checkIn)!
        let reservation = Reservation(
            id: "flow-res", guestID: "flow-guest", roomID: "flow-room",
            checkInDate: checkIn, expectedCheckOut: checkOut,
            isActive: true, numberOfGuests: 1, dailyRate: 300
        )
        service.saveReservation(reservation)

        // 4. 收押金
        let deposit = DepositRecord(
            id: "flow-dep", reservationID: "flow-res", type: .collect,
            amount: 500, paymentMethod: .wechat, timestamp: checkIn
        )
        service.saveDepositRecord(deposit)

        // 5. 更新房态
        service.updateRoomStatus(roomID: "flow-room", status: .occupied)

        // 验证状态
        let activeRes = service.fetchActiveReservation(forRoomID: "flow-room")
        XCTAssertNotNil(activeRes)
        XCTAssertEqual(activeRes?.guestID, "flow-guest")

        let fetchedRoom = service.fetchAllRooms().first { $0.id == "flow-room" }
        XCTAssertEqual(fetchedRoom?.status, .occupied)

        let deposits = service.fetchDeposits(forReservationID: "flow-res")
        XCTAssertEqual(deposits.count, 1)
        XCTAssertEqual(DepositSummary(records: deposits).balance, 500)

        // 6. 退押金
        let refund = DepositRecord(
            id: "flow-refund", reservationID: "flow-res", type: .refund,
            amount: 500, paymentMethod: .wechat, timestamp: Date()
        )
        service.saveDepositRecord(refund)

        let afterRefund = service.fetchDeposits(forReservationID: "flow-res")
        XCTAssertEqual(DepositSummary(records: afterRefund).balance, 0)

        // 7. 退房
        service.checkOut(reservationID: "flow-res")
        service.updateRoomStatus(roomID: "flow-room", status: .cleaning)

        let checkedOut = service.fetchActiveReservation(forRoomID: "flow-room")
        XCTAssertNil(checkedOut, "Room should have no active reservation after checkout")

        let roomAfter = service.fetchAllRooms().first { $0.id == "flow-room" }
        XCTAssertEqual(roomAfter?.status, .cleaning)

        // 8. 历史记录
        let history = service.fetchReservationHistory(forRoomID: "flow-room")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, "flow-res")
    }

    // MARK: - 场景2：OTA 预订→锁房→入住

    func testOTABookingToReservedToCheckIn() {
        let room = Room(
            id: "ota-room", roomNumber: "202", floor: 2,
            roomType: .twin, orientation: .north,
            status: .vacant, pricePerNight: 250, weekendPrice: 320, monthlyCost: 1200
        )
        service.saveRoom(room)

        // 1. 收到 OTA 预订 → 房间设为已预订
        service.updateRoomStatus(roomID: "ota-room", status: .reserved)
        let reserved = service.fetchAllRooms().first { $0.id == "ota-room" }
        XCTAssertEqual(reserved?.status, .reserved)

        // 2. 客人到店 → 办理入住
        let guest = Guest(id: "ota-guest", name: "OTA客人", idType: .passport, idNumber: "E1234567", phone: "13900139000")
        service.saveGuest(guest)

        let res = Reservation(
            id: "ota-res", guestID: "ota-guest", roomID: "ota-room",
            checkInDate: Date(), expectedCheckOut: Calendar.current.date(byAdding: .day, value: 3, to: Date())!,
            isActive: true, numberOfGuests: 2, dailyRate: 250
        )
        service.saveReservation(res)
        service.updateRoomStatus(roomID: "ota-room", status: .occupied)

        let occupied = service.fetchAllRooms().first { $0.id == "ota-room" }
        XCTAssertEqual(occupied?.status, .occupied)
    }

    // MARK: - 场景3：多房间同时在住

    func testMultipleRoomsOccupied() {
        var rooms: [Room] = []
        for i in 1...5 {
            let room = Room(
                id: "multi-\(i)", roomNumber: "\(300 + i)", floor: 3,
                roomType: .king, orientation: .south,
                status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
            )
            service.saveRoom(room)
            rooms.append(room)

            let guest = Guest(id: "mg-\(i)", name: "客人\(i)", idType: .idCard, idNumber: "110101199001011237", phone: "138001380\(i)0")
            service.saveGuest(guest)

            let res = Reservation(
                id: "mres-\(i)", guestID: "mg-\(i)", roomID: "multi-\(i)",
                checkInDate: Date(), expectedCheckOut: Calendar.current.date(byAdding: .day, value: i, to: Date())!,
                isActive: true, numberOfGuests: 1, dailyRate: 288
            )
            service.saveReservation(res)
            service.updateRoomStatus(roomID: "multi-\(i)", status: .occupied)
        }

        let activeReservations = service.fetchActiveReservations()
        XCTAssertEqual(activeReservations.count, 5)

        let occupiedRooms = service.fetchAllRooms().filter { $0.status == .occupied }
        XCTAssertEqual(occupiedRooms.count, 5)
    }

    // MARK: - 场景4：房态完整流转

    func testRoomStatusFullCycle() {
        let room = Room(
            id: "cycle-room", roomNumber: "401", floor: 4,
            roomType: .suite, orientation: .south,
            status: .vacant, pricePerNight: 588, weekendPrice: 688, monthlyCost: 2500
        )
        service.saveRoom(room)

        // 空房 → 已预订
        service.updateRoomStatus(roomID: "cycle-room", status: .reserved)
        XCTAssertEqual(service.fetchAllRooms().first?.status, .reserved)

        // 已预订 → 已住
        service.updateRoomStatus(roomID: "cycle-room", status: .occupied)
        XCTAssertEqual(service.fetchAllRooms().first?.status, .occupied)

        // 已住 → 脏房
        service.updateRoomStatus(roomID: "cycle-room", status: .cleaning)
        XCTAssertEqual(service.fetchAllRooms().first?.status, .cleaning)

        // 脏房 → 空房
        service.updateRoomStatus(roomID: "cycle-room", status: .vacant)
        XCTAssertEqual(service.fetchAllRooms().first?.status, .vacant)

        // 空房 → 维修
        service.updateRoomStatus(roomID: "cycle-room", status: .maintenance)
        XCTAssertEqual(service.fetchAllRooms().first?.status, .maintenance)

        // 维修 → 空房
        service.updateRoomStatus(roomID: "cycle-room", status: .vacant)
        XCTAssertEqual(service.fetchAllRooms().first?.status, .vacant)
    }

    // MARK: - 场景5：多种支付方式混合押金

    func testMixedPaymentDeposits() {
        service.saveDepositRecord(DepositRecord(
            id: "mix-1", reservationID: "res-1", type: .collect,
            amount: 300, paymentMethod: .cash, timestamp: Date()
        ))
        service.saveDepositRecord(DepositRecord(
            id: "mix-2", reservationID: "res-1", type: .collect,
            amount: 200, paymentMethod: .wechat, timestamp: Date()
        ))
        service.saveDepositRecord(DepositRecord(
            id: "mix-3", reservationID: "res-1", type: .refund,
            amount: 100, paymentMethod: .alipay, timestamp: Date()
        ))

        let deposits = service.fetchDeposits(forReservationID: "res-1")
        let summary = DepositSummary(records: deposits)
        XCTAssertEqual(summary.totalCollected, 500)
        XCTAssertEqual(summary.totalRefunded, 100)
        XCTAssertEqual(summary.balance, 400)

        // 验证支付方式记录
        XCTAssertEqual(deposits[0].paymentMethod, .cash)
        XCTAssertEqual(deposits[1].paymentMethod, .wechat)
        XCTAssertEqual(deposits[2].paymentMethod, .alipay)
    }

    // MARK: - 场景6：闰年2月入住率

    func testLeapYearFebruaryOccupancy() {
        service.saveRoom(Room(
            id: "leap-room", roomNumber: "501", floor: 5,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        ))
        // 2028年2月有29天（闰年）
        service.saveReservation(Reservation(
            id: "leap-res", guestID: "g1", roomID: "leap-room",
            checkInDate: date(2028, 2, 1), expectedCheckOut: date(2028, 3, 1),
            actualCheckOut: date(2028, 3, 1), isActive: false,
            numberOfGuests: 1, dailyRate: 288
        ))

        let data = service.fetchDailyOccupancy(year: 2028, month: 2, totalRooms: 1)
        XCTAssertEqual(data.count, 29, "Leap year February should have 29 days")
        XCTAssertTrue(data.allSatisfy { $0.count == 1 }, "Room should be occupied every day of Feb 2028")
    }

    // MARK: - Helper

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
