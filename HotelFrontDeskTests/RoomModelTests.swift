import XCTest
@testable import HotelFrontDesk

final class RoomModelTests: XCTestCase {

    // MARK: - RoomStatus

    func testRoomStatus_allCases() {
        XCTAssertEqual(RoomStatus.allCases.count, 5)
        XCTAssertTrue(RoomStatus.allCases.contains(.vacant))
        XCTAssertTrue(RoomStatus.allCases.contains(.reserved))
        XCTAssertTrue(RoomStatus.allCases.contains(.occupied))
        XCTAssertTrue(RoomStatus.allCases.contains(.cleaning))
        XCTAssertTrue(RoomStatus.allCases.contains(.maintenance))
    }

    func testRoomStatus_displayNames() {
        // displayName is now localized — just verify not empty
        for status in RoomStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, "\(status.rawValue) should have a display name")
        }
    }

    func testRoomStatus_rawValues() {
        XCTAssertEqual(RoomStatus.vacant.rawValue, "vacant")
        XCTAssertEqual(RoomStatus.reserved.rawValue, "reserved")
        XCTAssertEqual(RoomStatus.occupied.rawValue, "occupied")
        XCTAssertEqual(RoomStatus.cleaning.rawValue, "cleaning")
        XCTAssertEqual(RoomStatus.maintenance.rawValue, "maintenance")
    }

    // MARK: - RoomType

    func testRoomType_allCases() {
        XCTAssertEqual(RoomType.allCases.count, 3)
    }

    func testRoomType_rawValues() {
        XCTAssertEqual(RoomType.king.rawValue, "大床房")
        XCTAssertEqual(RoomType.twin.rawValue, "双床房")
        XCTAssertEqual(RoomType.suite.rawValue, "套房")
    }

    // MARK: - RoomOrientation

    func testRoomOrientation_allCases() {
        XCTAssertEqual(RoomOrientation.allCases.count, 8)
    }

    // MARK: - IDType

    func testIDType_allCases() {
        XCTAssertEqual(IDType.allCases.count, 3)
        XCTAssertEqual(IDType.idCard.rawValue, "身份证")
        XCTAssertEqual(IDType.passport.rawValue, "护照")
        XCTAssertEqual(IDType.other.rawValue, "其他")
    }

    // MARK: - DepositType

    func testDepositType_rawValues() {
        XCTAssertEqual(DepositType.collect.rawValue, "收取")
        XCTAssertEqual(DepositType.refund.rawValue, "退还")
    }

    // MARK: - Room Hashable

    func testRoom_hashable() {
        let room1 = makeRoom(id: "r1", roomNumber: "101")
        let room2 = makeRoom(id: "r1", roomNumber: "101")
        let room3 = makeRoom(id: "r2", roomNumber: "102")

        XCTAssertEqual(room1, room2)
        XCTAssertNotEqual(room1, room3)

        var set = Set<Room>()
        set.insert(room1)
        set.insert(room2)
        XCTAssertEqual(set.count, 1, "Same room ID should not duplicate in Set")
    }

    // MARK: - Helpers

    private func makeRoom(id: String = "r1", roomNumber: String = "101") -> Room {
        Room(
            id: id, roomNumber: roomNumber, floor: 1,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        )
    }
}
