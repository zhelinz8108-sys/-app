import XCTest
@testable import HotelFrontDesk

/// Tests for CheckInViewModel form validation logic.
@MainActor
final class CheckInValidationTests: XCTestCase {

    private var vm: CheckInViewModel!

    override func setUp() {
        super.setUp()
        vm = CheckInViewModel()
    }

    // MARK: - isFormValid

    func testFormValid_allFieldsFilled() {
        fillValidForm()
        XCTAssertTrue(vm.isFormValid)
    }

    func testFormInvalid_emptyName() {
        fillValidForm()
        vm.guestName = ""
        XCTAssertFalse(vm.isFormValid)
    }

    func testFormInvalid_whitespaceOnlyName() {
        fillValidForm()
        vm.guestName = "   "
        XCTAssertFalse(vm.isFormValid)
    }

    func testFormInvalid_emptyIDNumber() {
        fillValidForm()
        vm.idNumber = ""
        XCTAssertFalse(vm.isFormValid)
    }

    func testFormInvalid_emptyPhone() {
        fillValidForm()
        vm.phone = ""
        XCTAssertFalse(vm.isFormValid)
    }

    func testFormInvalid_noRoomSelected() {
        fillValidForm()
        vm.selectedRoom = nil
        XCTAssertFalse(vm.isFormValid)
    }

    func testFormInvalid_checkOutBeforeCheckIn() {
        fillValidForm()
        vm.checkInDate = Date()
        vm.expectedCheckOut = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
        XCTAssertFalse(vm.isFormValid)
    }

    func testFormInvalid_checkOutEqualsCheckIn() {
        fillValidForm()
        let now = Date()
        vm.checkInDate = now
        vm.expectedCheckOut = now
        XCTAssertFalse(vm.isFormValid, "Check-out must be strictly after check-in")
    }

    // MARK: - Price parsing

    func testRoomPriceValue_validNumber() {
        vm.roomPrice = "288"
        XCTAssertEqual(vm.roomPriceValue, 288)
    }

    func testRoomPriceValue_invalidString() {
        vm.roomPrice = "abc"
        XCTAssertEqual(vm.roomPriceValue, 0)
    }

    func testRoomPriceValue_empty() {
        vm.roomPrice = ""
        XCTAssertEqual(vm.roomPriceValue, 0)
    }

    func testDepositValue_validNumber() {
        vm.depositAmount = "500"
        XCTAssertEqual(vm.depositValue, 500)
    }

    func testDepositValue_decimal() {
        vm.depositAmount = "299.5"
        XCTAssertEqual(vm.depositValue, 299.5, accuracy: 0.01)
    }

    // MARK: - Reset

    func testReset_clearsAllFields() {
        fillValidForm()
        vm.reset()
        XCTAssertEqual(vm.guestName, "")
        XCTAssertEqual(vm.idNumber, "")
        XCTAssertEqual(vm.phone, "")
        XCTAssertNil(vm.selectedRoom)
        XCTAssertEqual(vm.roomPrice, "")
        XCTAssertEqual(vm.depositAmount, "")
        XCTAssertFalse(vm.isSubmitting)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.checkInSuccess)
    }

    // MARK: - Helpers

    private func fillValidForm() {
        vm.guestName = "张三"
        vm.idNumber = "110101199001011237"
        vm.phone = "13800138000"
        vm.selectedRoom = Room(
            id: "r1", roomNumber: "101", floor: 1,
            roomType: .king, orientation: .south,
            status: .vacant, pricePerNight: 288, weekendPrice: 358, monthlyCost: 1500
        )
        vm.checkInDate = Date()
        vm.expectedCheckOut = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        vm.roomPrice = "288"
        vm.depositAmount = "500"
    }
}
