import XCTest
@testable import HotelFrontDesk

final class ReservationTests: XCTestCase {

    // MARK: - nightsStayed

    func testNightsStayed_oneNight() {
        let checkIn = date(2026, 3, 10, hour: 14)
        let checkOut = date(2026, 3, 11, hour: 12)
        let res = makeReservation(checkIn: checkIn, actualCheckOut: checkOut)
        XCTAssertEqual(res.nightsStayed, 1)
    }

    func testNightsStayed_threeNights() {
        let checkIn = date(2026, 3, 10, hour: 14)
        let checkOut = date(2026, 3, 13, hour: 14)
        let res = makeReservation(checkIn: checkIn, actualCheckOut: checkOut)
        XCTAssertEqual(res.nightsStayed, 3)
    }

    func testNightsStayed_sameDay_returnsMinimumOne() {
        let checkIn = date(2026, 3, 10, hour: 14)
        let checkOut = date(2026, 3, 10, hour: 18)
        let res = makeReservation(checkIn: checkIn, actualCheckOut: checkOut)
        XCTAssertEqual(res.nightsStayed, 1, "Same-day checkout should count as 1 night minimum")
    }

    func testNightsStayed_noActualCheckOut_usesCurrentDate() {
        let checkIn = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let res = makeReservation(checkIn: checkIn, actualCheckOut: nil)
        XCTAssertEqual(res.nightsStayed, 2)
    }

    func testNightsStayed_longStay() {
        let checkIn = date(2026, 1, 1, hour: 14)
        let checkOut = date(2026, 2, 1, hour: 14)
        let res = makeReservation(checkIn: checkIn, actualCheckOut: checkOut)
        XCTAssertEqual(res.nightsStayed, 31)
    }

    // MARK: - totalRevenue

    func testTotalRevenue_basic() {
        let res = makeReservation(
            checkIn: date(2026, 3, 10, hour: 14),
            actualCheckOut: date(2026, 3, 13, hour: 14),
            dailyRate: 288
        )
        // 3 nights × ¥288 = ¥864
        XCTAssertEqual(res.totalRevenue, 864, accuracy: 0.01)
    }

    func testTotalRevenue_zeroRate() {
        let res = makeReservation(
            checkIn: date(2026, 3, 10, hour: 14),
            actualCheckOut: date(2026, 3, 12, hour: 12),
            dailyRate: 0
        )
        XCTAssertEqual(res.totalRevenue, 0)
    }

    func testTotalRevenue_singleNight() {
        let res = makeReservation(
            checkIn: date(2026, 3, 10, hour: 14),
            actualCheckOut: date(2026, 3, 11, hour: 12),
            dailyRate: 500
        )
        XCTAssertEqual(res.totalRevenue, 500, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makeReservation(
        checkIn: Date,
        expectedCheckOut: Date? = nil,
        actualCheckOut: Date? = nil,
        dailyRate: Double = 288,
        isActive: Bool = false
    ) -> Reservation {
        Reservation(
            id: UUID().uuidString,
            guestID: "guest-1",
            roomID: "room-1",
            checkInDate: checkIn,
            expectedCheckOut: expectedCheckOut ?? Calendar.current.date(byAdding: .day, value: 1, to: checkIn)!,
            actualCheckOut: actualCheckOut,
            isActive: isActive,
            numberOfGuests: 1,
            dailyRate: dailyRate
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
