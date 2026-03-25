import XCTest
@testable import HotelFrontDesk

@MainActor
final class StaffServiceTests: XCTestCase {

    private var service: StaffService!

    override func setUp() {
        super.setUp()
        service = StaffService.shared
        service.resetForTesting()
    }

    override func tearDown() {
        service.resetForTesting()
        super.tearDown()
    }

    func testLoginLockout_isScopedPerUsername() {
        service.resetForTesting(staff: [
            makeStaff(name: "Alice", username: "alice", password: "alice-pass", role: .manager),
            makeStaff(name: "Bob", username: "bob", password: "bob-pass")
        ])

        for _ in 0..<5 {
            XCTAssertFalse(service.login(username: "alice", password: "wrong-pass"))
        }

        XCTAssertTrue(service.isLockedOut(username: "alice"))
        XCTAssertFalse(service.isLockedOut(username: "bob"))
        XCTAssertTrue(service.login(username: "bob", password: "bob-pass"))
    }

    func testLoginLockout_persistsAcrossReload() {
        service.resetForTesting(staff: [
            makeStaff(name: "Alice", username: "alice", password: "alice-pass", role: .manager)
        ])

        for _ in 0..<5 {
            XCTAssertFalse(service.login(username: "alice", password: "wrong-pass"))
        }
        XCTAssertTrue(service.isLockedOut(username: "alice"))

        service.reloadForTesting()

        XCTAssertTrue(service.isLockedOut(username: "alice"), "Lockout should survive app restarts")
        XCTAssertFalse(service.login(username: "alice", password: "alice-pass"))
    }

    func testEnsureDefaultAdmin_doesNotResetMissingManagerHashToKnownPassword() {
        let corruptedManager = Staff(
            id: "corrupted-manager",
            name: "管理员",
            username: "admin",
            existingHash: "",
            role: .manager,
            phone: "",
            isActive: true
        )

        service.resetForTesting(staff: [corruptedManager])
        service.reloadForTesting()

        XCTAssertFalse(service.login(username: "admin", password: "8888"))
        XCTAssertEqual(service.fetchAll().first?.passwordHash, "", "Missing manager hashes should fail closed instead of resetting to a known password")
        XCTAssertNotNil(service.credentialIntegrityIssue)
        XCTAssertFalse(service.shouldShowBootstrapHint)
    }

    func testBootstrapHint_hidesAfterDefaultPasswordChanges() {
        service.resetForTesting(staff: [
            makeStaff(name: "管理员", username: "admin", password: "8888", role: .manager)
        ])

        guard let adminID = service.fetchAll().first?.id else {
            return XCTFail("Expected bootstrap admin account")
        }

        XCTAssertTrue(service.shouldShowBootstrapHint)

        service.changePassword(staffID: adminID, newPassword: "StrongPassword!23")

        XCTAssertFalse(service.shouldShowBootstrapHint, "Default credential hint should disappear after the bootstrap password changes")
    }

    func testMandatoryPasswordChange_requiredUntilBootstrapPasswordChanges() {
        service.resetForTesting(staff: [
            makeStaff(name: "管理员", username: "admin", password: "8888", role: .manager)
        ])

        XCTAssertTrue(service.login(username: "admin", password: "8888"))
        XCTAssertTrue(service.requiresMandatoryPasswordChange)

        guard let adminID = service.currentStaff?.id else {
            return XCTFail("Expected logged in admin")
        }

        service.changePassword(staffID: adminID, newPassword: "Hotel12345")

        XCTAssertFalse(service.requiresMandatoryPasswordChange)
    }

    func testPasswordPolicy_rejectsDefaultWeakPassword() {
        XCTAssertEqual(service.passwordPolicyError(for: "8888"), "密码至少需要 8 位")
        XCTAssertEqual(service.passwordPolicyError(for: "abcdefgh"), "密码需同时包含字母和数字")
        XCTAssertNil(service.passwordPolicyError(for: "Hotel12345"))
    }

    func testPersist_readsPasswordHashFromSynchronizableKeychainFallback() {
        let staff = makeStaff(name: "同步管理员", username: "sync-admin", password: "Hotel12345", role: .manager)
        service.resetForTesting(staff: [staff])

        _ = KeychainHelper.delete(key: "staff_pw_\(staff.id)")

        service.reloadForTesting()

        XCTAssertTrue(service.login(username: "sync-admin", password: "Hotel12345"))
    }

    private func makeStaff(name: String, username: String, password: String, role: StaffRole = .employee) -> Staff {
        Staff(
            name: name,
            username: username,
            password: password,
            role: role,
            phone: ""
        )
    }
}
