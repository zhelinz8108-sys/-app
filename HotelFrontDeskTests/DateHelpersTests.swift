import XCTest
@testable import HotelFrontDesk

final class DateHelpersTests: XCTestCase {

    func testIsToday() {
        XCTAssertTrue(Date().isToday)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(yesterday.isToday)
    }

    func testTomorrow() {
        let tomorrow = Date.tomorrow
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        XCTAssertEqual(
            Calendar.current.startOfDay(for: tomorrow),
            Calendar.current.startOfDay(for: expected)
        )
    }

    func testDaysUntil() {
        let today = Calendar.current.startOfDay(for: Date())
        let threeDaysLater = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        XCTAssertEqual(today.daysUntil(threeDaysLater), 3)
    }

    func testDaysUntil_sameDay() {
        let today = Date()
        XCTAssertEqual(today.daysUntil(today), 0)
    }

    func testChineseDate_format() {
        // Create a known date
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let formatted = date.chineseDate
        XCTAssertTrue(formatted.contains("2026"), "Should contain year")
        XCTAssertTrue(formatted.contains("3"), "Should contain month")
        XCTAssertTrue(formatted.contains("20"), "Should contain day")
    }

    func testShortDate_format() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let formatted = date.shortDate
        XCTAssertTrue(formatted.contains("3"), "Should contain month")
        XCTAssertTrue(formatted.contains("5"), "Should contain day")
    }
}
