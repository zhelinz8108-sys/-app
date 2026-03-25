import XCTest
@testable import HotelFrontDesk

/// Tests for LocalStorageService CRUD operations and query logic.
/// Uses the shared singleton — tests run serially on @MainActor.
@MainActor
final class LocalStorageServiceTests: XCTestCase {

    private var service: LocalStorageService!

    override func setUp() {
        super.setUp()
        service = LocalStorageService.shared
        // Clean up all data to start fresh
        service.resetAll()
    }

    // MARK: - Room CRUD

    func testSaveAndFetchRoom() {
        let room = makeRoom(id: "test-r1", roomNumber: "101", floor: 1)
        service.saveRoom(room)
        let rooms = service.fetchAllRooms()
        XCTAssertTrue(rooms.contains { $0.id == "test-r1" })
    }

    func testSaveRoom_updateExisting() {
        var room = makeRoom(id: "test-r2", roomNumber: "102", floor: 1)
        service.saveRoom(room)
        room.pricePerNight = 999
        service.saveRoom(room)
        let rooms = service.fetchAllRooms()
        let saved = rooms.first { $0.id == "test-r2" }
        XCTAssertEqual(saved?.pricePerNight, 999)
    }

    func testFetchAllRooms_sortedByFloorThenNumber() {
        service.saveRoom(makeRoom(id: "test-r3", roomNumber: "301", floor: 3))
        service.saveRoom(makeRoom(id: "test-r4", roomNumber: "101", floor: 1))
        service.saveRoom(makeRoom(id: "test-r5", roomNumber: "201", floor: 2))
        let rooms = service.fetchAllRooms().filter { $0.id.hasPrefix("test-") }
        XCTAssertEqual(rooms.map(\.floor), [1, 2, 3])
    }

    func testUpdateRoomStatus() {
        service.saveRoom(makeRoom(id: "test-r6", roomNumber: "106", floor: 1))
        service.updateRoomStatus(roomID: "test-r6", status: .occupied)
        let room = service.fetchAllRooms().first { $0.id == "test-r6" }
        XCTAssertEqual(room?.status, .occupied)
    }

    func testSaveRooms_batch() {
        let rooms = [
            makeRoom(id: "test-batch-1", roomNumber: "B1", floor: 1),
            makeRoom(id: "test-batch-2", roomNumber: "B2", floor: 1),
        ]
        service.saveRooms(rooms)
        let all = service.fetchAllRooms()
        XCTAssertTrue(all.contains { $0.id == "test-batch-1" })
        XCTAssertTrue(all.contains { $0.id == "test-batch-2" })
    }

    func testTotalRoomCount() {
        let before = service.totalRoomCount()
        service.saveRoom(makeRoom(id: "test-count-1", roomNumber: "C1", floor: 1))
        XCTAssertEqual(service.totalRoomCount(), before + 1)
    }

    // MARK: - Guest CRUD

    func testSaveAndFetchGuest() {
        let guest = Guest(id: "test-g1", name: "张三", idType: .idCard, idNumber: "110101199001011234", phone: "13800138000")
        service.saveGuest(guest)
        let fetched = service.fetchGuest(id: "test-g1")
        XCTAssertEqual(fetched?.name, "张三")
        XCTAssertEqual(fetched?.idType, .idCard)
    }

    func testFetchGuest_notFound() {
        let fetched = service.fetchGuest(id: "nonexistent-guest")
        XCTAssertNil(fetched)
    }

    func testSaveGuest_persistsEncryptedSensitiveFieldsToDisk() throws {
        let guest = Guest(
            id: "test-encrypted-guest",
            name: "赵敏",
            idType: .idCard,
            idNumber: "110101199001011236",
            phone: "13800138009"
        )

        service.saveGuest(guest)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let guestFile = docs.appendingPathComponent("HotelLocalData/guests.json")
        let content = try String(contentsOf: guestFile, encoding: .utf8)

        XCTAssertFalse(content.contains(guest.idNumber), "ID number should not be persisted in plaintext")
        XCTAssertFalse(content.contains(guest.phone), "Phone should not be persisted in plaintext")
        XCTAssertTrue(content.contains(EncryptionHelper.envelopePrefix), "Persisted guest data should use the versioned encrypted envelope")
    }

    // MARK: - Reservation CRUD

    func testSaveAndFetchActiveReservation() {
        let room = makeRoom(id: "test-res-room", roomNumber: "201", floor: 2)
        service.saveRoom(room)

        let guest = Guest(id: "test-res-guest", name: "李四", idType: .idCard, idNumber: "110101199001011234", phone: "13900139000")
        service.saveGuest(guest)

        let reservation = Reservation(
            id: "test-res-1",
            guestID: "test-res-guest",
            roomID: "test-res-room",
            checkInDate: Date(),
            expectedCheckOut: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            isActive: true,
            numberOfGuests: 1,
            dailyRate: 288
        )
        service.saveReservation(reservation)

        let active = service.fetchActiveReservation(forRoomID: "test-res-room")
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.id, "test-res-1")
        XCTAssertEqual(active?.guest?.name, "李四", "Should auto-fill guest")
    }

    func testCheckOut_marksInactiveAndSetsDate() {
        let reservation = Reservation(
            id: "test-checkout-1",
            guestID: "g1",
            roomID: "r1",
            checkInDate: Date(),
            expectedCheckOut: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            isActive: true,
            numberOfGuests: 1,
            dailyRate: 288
        )
        service.saveReservation(reservation)
        service.checkOut(reservationID: "test-checkout-1")

        let active = service.fetchActiveReservations().filter { $0.id == "test-checkout-1" }
        XCTAssertTrue(active.isEmpty, "Should no longer be active")
    }

    func testFetchReservationHistory_sortedByCheckInDesc() {
        let r1 = Reservation(
            id: "hist-1", guestID: "g1", roomID: "hist-room",
            checkInDate: date(2026, 1, 1), expectedCheckOut: date(2026, 1, 3),
            actualCheckOut: date(2026, 1, 3), isActive: false, numberOfGuests: 1, dailyRate: 100
        )
        let r2 = Reservation(
            id: "hist-2", guestID: "g1", roomID: "hist-room",
            checkInDate: date(2026, 2, 1), expectedCheckOut: date(2026, 2, 3),
            actualCheckOut: date(2026, 2, 3), isActive: false, numberOfGuests: 1, dailyRate: 100
        )
        service.saveReservation(r1)
        service.saveReservation(r2)

        let history = service.fetchReservationHistory(forRoomID: "hist-room")
        XCTAssertEqual(history.first?.id, "hist-2", "Most recent first")
    }

    // MARK: - Deposit CRUD

    func testSaveAndFetchDeposits() {
        let d1 = DepositRecord(id: "test-d1", reservationID: "res-1", type: .collect, amount: 500, paymentMethod: .cash, timestamp: Date())
        let d2 = DepositRecord(id: "test-d2", reservationID: "res-1", type: .refund, amount: 200, paymentMethod: .wechat, timestamp: Date())
        let d3 = DepositRecord(id: "test-d3", reservationID: "res-2", type: .collect, amount: 300, paymentMethod: .alipay, timestamp: Date())
        service.saveDepositRecord(d1)
        service.saveDepositRecord(d2)
        service.saveDepositRecord(d3)

        let deposits = service.fetchDeposits(forReservationID: "res-1")
        XCTAssertEqual(deposits.count, 2, "Should only return deposits for res-1")
    }

    func testSaveDepositRecord_sameIDUpdatesInsteadOfDuplicating() {
        let original = DepositRecord(
            id: "test-deposit-upsert",
            reservationID: "res-upsert",
            type: .collect,
            amount: 300,
            paymentMethod: .cash,
            timestamp: date(2026, 3, 1)
        )
        let updated = DepositRecord(
            id: "test-deposit-upsert",
            reservationID: "res-upsert",
            type: .collect,
            amount: 500,
            paymentMethod: .wechat,
            timestamp: date(2026, 3, 2)
        )

        service.saveDepositRecord(original)
        service.saveDepositRecord(updated)

        let deposits = service.fetchDeposits(forReservationID: "res-upsert")
        XCTAssertEqual(deposits.count, 1, "Mirror sync should update by ID instead of duplicating deposits")
        XCTAssertEqual(deposits.first?.amount, 500)
        XCTAssertEqual(deposits.first?.paymentMethod, .wechat)
    }

    // MARK: - Analytics Queries

    func testFetchReservationsForMonth() {
        // Checkout in March
        let march = Reservation(
            id: "analytics-march", guestID: "g1", roomID: "r1",
            checkInDate: date(2026, 3, 10), expectedCheckOut: date(2026, 3, 12),
            actualCheckOut: date(2026, 3, 12), isActive: false, numberOfGuests: 1, dailyRate: 288
        )
        // Checkout in February
        let feb = Reservation(
            id: "analytics-feb", guestID: "g1", roomID: "r1",
            checkInDate: date(2026, 2, 25), expectedCheckOut: date(2026, 2, 27),
            actualCheckOut: date(2026, 2, 27), isActive: false, numberOfGuests: 1, dailyRate: 288
        )
        // Active (should be excluded)
        let active = Reservation(
            id: "analytics-active", guestID: "g1", roomID: "r1",
            checkInDate: date(2026, 3, 15), expectedCheckOut: date(2026, 3, 17),
            isActive: true, numberOfGuests: 1, dailyRate: 288
        )
        service.saveReservation(march)
        service.saveReservation(feb)
        service.saveReservation(active)

        let marchResults = service.fetchReservationsForMonth(year: 2026, month: 3)
        let marchIDs = marchResults.map(\.id)
        XCTAssertTrue(marchIDs.contains("analytics-march"))
        XCTAssertFalse(marchIDs.contains("analytics-feb"), "February checkout should not appear")
        XCTAssertFalse(marchIDs.contains("analytics-active"), "Active reservations should be excluded")
    }

    func testFetchDailyOccupancy() {
        // Guest stays March 10-12 (occupies room on days 10 and 11)
        let res = Reservation(
            id: "occ-1", guestID: "g1", roomID: "r1",
            checkInDate: date(2026, 3, 10), expectedCheckOut: date(2026, 3, 12),
            actualCheckOut: date(2026, 3, 12), isActive: false, numberOfGuests: 1, dailyRate: 288
        )
        service.saveReservation(res)

        let data = service.fetchDailyOccupancy(year: 2026, month: 3, totalRooms: 10)
        XCTAssertEqual(data.count, 31, "Should have entry for every day in March")

        let day10 = data.first { $0.day == 10 }
        let day11 = data.first { $0.day == 11 }
        let day12 = data.first { $0.day == 12 }
        let day9 = data.first { $0.day == 9 }
        XCTAssertEqual(day10?.count, 1, "Day 10 should have 1 occupied room")
        XCTAssertEqual(day11?.count, 1, "Day 11 should have 1 occupied room")
        XCTAssertEqual(day12?.count, 0, "Day 12 (checkout day) should be 0")
        XCTAssertEqual(day9?.count, 0, "Day 9 (before checkin) should be 0")
    }

    func testFetchAllReservations_autoFillsGuestAndRoom() {
        let room = makeRoom(id: "test-fill-room", roomNumber: "801", floor: 8)
        let guest = Guest(id: "test-fill-guest", name: "王五", idType: .idCard, idNumber: "110101199001011234", phone: "13800138001")
        let reservation = Reservation(
            id: "test-fill-reservation",
            guestID: guest.id,
            roomID: room.id,
            checkInDate: date(2026, 3, 10),
            expectedCheckOut: date(2026, 3, 11),
            actualCheckOut: date(2026, 3, 11),
            isActive: false,
            numberOfGuests: 1,
            dailyRate: 288
        )

        service.saveRoom(room)
        service.saveGuest(guest)
        service.saveReservation(reservation)

        let fetched = service.fetchAllReservations().first { $0.id == reservation.id }
        XCTAssertEqual(fetched?.guest?.id, guest.id, "Full reservation queries should hydrate guest data")
        XCTAssertEqual(fetched?.room?.id, room.id, "Full reservation queries should hydrate room data")
    }

    func testFetchTodayExpectedCheckOuts_autoFillsGuestAndRoom() {
        let room = makeRoom(id: "test-today-room", roomNumber: "901", floor: 9)
        let guest = Guest(id: "test-today-guest", name: "赵六", idType: .idCard, idNumber: "110101199001011235", phone: "13800138002")
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let expectedCheckOut = Calendar.current.date(byAdding: .hour, value: 11, to: startOfDay)!
        let reservation = Reservation(
            id: "test-today-reservation",
            guestID: guest.id,
            roomID: room.id,
            checkInDate: Calendar.current.date(byAdding: .day, value: -1, to: startOfDay)!,
            expectedCheckOut: expectedCheckOut,
            isActive: true,
            numberOfGuests: 1,
            dailyRate: 388
        )

        service.saveRoom(room)
        service.saveGuest(guest)
        service.saveReservation(reservation)

        let fetched = service.fetchTodayExpectedCheckOuts().first { $0.id == reservation.id }
        XCTAssertEqual(fetched?.guest?.id, guest.id, "Dashboard checkout queries should hydrate guest data")
        XCTAssertEqual(fetched?.room?.id, room.id, "Dashboard checkout queries should hydrate room data")
    }

    // MARK: - Helpers

    private func makeRoom(id: String, roomNumber: String, floor: Int) -> Room {
        Room(id: id, roomNumber: roomNumber, floor: floor,
             roomType: .king, orientation: .south,
             status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
