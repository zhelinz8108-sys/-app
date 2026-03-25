import XCTest
import CryptoKit
@testable import HotelFrontDesk

/// 第3组：安全测试 — 加密、密码、数据脱敏
final class SecurityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EncryptionHelper.resetForTesting()
    }

    override func tearDown() {
        EncryptionHelper.resetForTesting()
        super.tearDown()
    }

    // MARK: - AES 加密/解密

    func testEncryptDecrypt_roundtrip() throws {
        let original = "110101199001011237"
        let encrypted = try EncryptionHelper.encrypt(original)
        let decrypted = try EncryptionHelper.decrypt(encrypted)
        XCTAssertEqual(decrypted, original)
        XCTAssertNotEqual(encrypted, original, "Encrypted should differ from original")
    }

    func testEncrypt_emptyString() throws {
        let encrypted = try EncryptionHelper.encrypt("")
        XCTAssertEqual(encrypted, "")
    }

    func testDecrypt_emptyString() throws {
        let decrypted = try EncryptionHelper.decrypt("")
        XCTAssertEqual(decrypted, "")
    }

    func testDecrypt_plaintext_returnsAsIs() throws {
        // 未加密的明文（旧数据兼容）
        let plaintext = "13800138000"
        let result = try EncryptionHelper.decrypt(plaintext)
        XCTAssertEqual(result, plaintext, "Unencrypted text should return as-is")
    }

    func testEncrypt_differentInputs_differentOutputs() throws {
        let a = try EncryptionHelper.encrypt("password1")
        let b = try EncryptionHelper.encrypt("password2")
        XCTAssertNotEqual(a, b)
    }

    func testEncrypt_sameInput_differentOutputs() throws {
        // AES-GCM uses random nonce, so same input → different ciphertext
        let a = try EncryptionHelper.encrypt("same_input")
        let b = try EncryptionHelper.encrypt("same_input")
        XCTAssertNotEqual(a, b, "Same input should produce different ciphertext (random nonce)")
        // But both should decrypt to the same value
        XCTAssertEqual(try EncryptionHelper.decrypt(a), "same_input")
        XCTAssertEqual(try EncryptionHelper.decrypt(b), "same_input")
    }

    func testEncrypt_chineseCharacters() throws {
        let name = "张三丰"
        let encrypted = try EncryptionHelper.encrypt(name)
        XCTAssertEqual(try EncryptionHelper.decrypt(encrypted), name)
    }

    func testEncrypt_longString() throws {
        let long = String(repeating: "A", count: 10000)
        let encrypted = try EncryptionHelper.encrypt(long)
        XCTAssertEqual(try EncryptionHelper.decrypt(encrypted), long)
    }

    func testEncrypt_usesVersionedEnvelope() throws {
        let encrypted = try EncryptionHelper.encrypt("13800138000")
        XCTAssertTrue(encrypted.hasPrefix(EncryptionHelper.envelopePrefix))
    }

    func testDecrypt_legacyCiphertextStillWorks() throws {
        let encrypted = try EncryptionHelper.encrypt("legacy-data")
        let legacyCiphertext = String(encrypted.dropFirst(EncryptionHelper.envelopePrefix.count))
        XCTAssertEqual(try EncryptionHelper.decrypt(legacyCiphertext), "legacy-data")
    }

    func testDecrypt_tamperedCiphertextThrows() throws {
        let encrypted = try EncryptionHelper.encrypt("secret")
        let tampered = encrypted + "!"

        XCTAssertThrowsError(try EncryptionHelper.decrypt(tampered)) { error in
            XCTAssertEqual(error as? EncryptionHelper.EncryptionError, .invalidCiphertext)
        }
    }

    func testDecrypt_missingProvisionedKeyThrows() throws {
        let encrypted = try EncryptionHelper.encrypt("13800138000")

        EncryptionHelper.resetForTesting(removeStoredKey: true, clearProvisionedState: false)

        XCTAssertThrowsError(try EncryptionHelper.decrypt(encrypted)) { error in
            XCTAssertEqual(error as? EncryptionHelper.EncryptionError, .keyUnavailable)
        }
    }

    // MARK: - 密码哈希 (PBKDF2)

    func testPasswordHash_notPlaintext() {
        let hash = KeychainHelper.hashPassword("8888")
        XCTAssertNotEqual(hash, "8888")
        XCTAssertTrue(hash.contains(":"), "Should be salt:hash format")
    }

    func testPasswordHash_sameInput_differentHash() {
        let a = KeychainHelper.hashPassword("test123")
        let b = KeychainHelper.hashPassword("test123")
        XCTAssertNotEqual(a, b, "Different salts should produce different hashes")
    }

    func testPasswordVerify_correctPassword() {
        let hash = KeychainHelper.hashPassword("mypassword")
        XCTAssertTrue(KeychainHelper.verifyPassword("mypassword", against: hash))
    }

    func testPasswordVerify_wrongPassword() {
        let hash = KeychainHelper.hashPassword("correct")
        XCTAssertFalse(KeychainHelper.verifyPassword("wrong", against: hash))
    }

    func testPasswordVerify_legacySHA256Fallback() {
        // Simulate old SHA256 hash (no salt)
        let data = Data("oldpassword".utf8)
        let legacyHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(KeychainHelper.verifyPassword("oldpassword", against: legacyHash),
                       "Should support legacy SHA256 hashes for migration")
    }

    // MARK: - 数据脱敏

    func testMaskedPhone_11digits() {
        XCTAssertEqual(Validators.maskedPhone("13800138000"), "138****8000")
    }

    func testMaskedPhone_shortInput() {
        XCTAssertEqual(Validators.maskedPhone("123"), "123") // 不够11位，原样返回
    }

    func testMaskedIDCard_18digits() {
        XCTAssertEqual(Validators.maskedIDCard("110101199001011237"), "1101**********1237")
    }

    func testMaskedIDCard_shortInput() {
        XCTAssertEqual(Validators.maskedIDCard("12345"), "12345")
    }

    func testMaskedSensitive_generic() {
        XCTAssertEqual(Validators.maskedSensitive("AB1234567"), "AB*****67")
    }

    // MARK: - 验证器

    func testValidPhone_valid() {
        XCTAssertTrue(Validators.isValidPhone("13800138000"))
        XCTAssertTrue(Validators.isValidPhone("19912345678"))
    }

    func testValidPhone_invalid() {
        XCTAssertFalse(Validators.isValidPhone("12345"))
        XCTAssertFalse(Validators.isValidPhone("23800138000")) // 不以1开头
        XCTAssertFalse(Validators.isValidPhone("1380013800"))  // 10位
        XCTAssertFalse(Validators.isValidPhone("138001380001")) // 12位
        XCTAssertFalse(Validators.isValidPhone(""))
    }

    func testValidIDCard_valid() {
        XCTAssertTrue(Validators.isValidIDCard("110101199001011237"))
    }

    func testValidIDCard_invalid() {
        XCTAssertFalse(Validators.isValidIDCard("110101199001011234")) // 校验位错
        XCTAssertFalse(Validators.isValidIDCard("12345"))
        XCTAssertFalse(Validators.isValidIDCard(""))
    }

    // MARK: - 管理员密码

    func testAppSettingsVerifyPassword_usesStoredHash() {
        let settings = AppSettings.shared
        let originalHash = settings.managerPasswordHash
        defer { settings.managerPasswordHash = originalHash }

        settings.changePassword(to: "4321")
        XCTAssertTrue(settings.verifyPassword("4321"))
        XCTAssertFalse(settings.verifyPassword("wrong"))
    }
}
