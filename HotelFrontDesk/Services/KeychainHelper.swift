import Foundation
import Security
import CryptoKit
import CommonCrypto

/// Keychain 读写封装
enum KeychainHelper {
    private static let service = "com.hotel.frontdesk"

    @discardableResult
    static func save(key: String, value: String, synchronizable: Bool = false) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(key: key, synchronizable: synchronizable)
        // 先删除旧值
        SecItemDelete(query as CFDictionary)
        // 写入新值
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func read(key: String, synchronizable: Bool = false) -> String? {
        var query = baseQuery(key: key, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String, synchronizable: Bool = false) -> Bool {
        let query = baseQuery(key: key, synchronizable: synchronizable)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(key: String, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        }
        return query
    }

    /// 使用 PBKDF2 + 随机 salt 生成密码哈希，返回 "salt:hash" 格式
    static func hashPassword(_ password: String) -> String {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let hash = pbkdf2(password: password, salt: salt)
        return salt.map { String(format: "%02x", $0) }.joined()
            + ":" + hash.map { String(format: "%02x", $0) }.joined()
    }

    /// 验证密码是否匹配 "salt:hash" 格式的已存储哈希
    static func verifyPassword(_ password: String, against stored: String) -> Bool {
        let parts = stored.split(separator: ":")
        guard parts.count == 2,
              let salt = Data(hexString: String(parts[0])),
              let expectedHash = Data(hexString: String(parts[1])) else {
            // 兼容旧的纯 SHA256 哈希（无 salt）
            let data = Data(password.utf8)
            let hash = SHA256.hash(data: data)
            let legacyHash = hash.compactMap { String(format: "%02x", $0) }.joined()
            return legacyHash == stored
        }
        let computed = pbkdf2(password: password, salt: salt)
        return computed == expectedHash
    }

    private static func pbkdf2(password: String, salt: Data, iterations: Int = 100_000, keyLength: Int = 32) -> Data {
        var derivedKey = Data(count: keyLength)
        let passwordData = Data(password.utf8)
        _ = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        return derivedKey
    }
}

private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
