import Foundation
import CryptoKit

/// AES-GCM 加密/解密工具 — 用于保护客人身份证号等敏感数据
enum EncryptionHelper {
    enum EncryptionError: LocalizedError, Equatable {
        case keyUnavailable
        case keyCorrupted
        case keyPersistenceFailed
        case encryptionFailed
        case invalidCiphertext
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .keyUnavailable:
                return "加密密钥不可用，请在原设备或可信备份中恢复后再试。"
            case .keyCorrupted:
                return "检测到损坏的加密密钥，请从可信备份恢复后再试。"
            case .keyPersistenceFailed:
                return "无法安全保存加密密钥，请检查设备钥匙串设置后重试。"
            case .encryptionFailed:
                return "敏感信息加密失败，请稍后重试。"
            case .invalidCiphertext:
                return "检测到损坏的敏感数据，请从备份恢复后再试。"
            case .decryptionFailed:
                return "敏感数据无法解密，请确认当前设备已恢复原有加密密钥。"
            }
        }
    }

    private enum StoredKeyState {
        case missing
        case invalid
        case value(SymmetricKey)
    }

    private enum StorageFormat {
        case plaintext
        case encrypted(String)
    }

    private static let keyLock = NSLock()
    private static var _cachedKey: SymmetricKey?
    private static var cachedKey: SymmetricKey? {
        get { keyLock.lock(); defer { keyLock.unlock() }; return _cachedKey }
        set { keyLock.lock(); defer { keyLock.unlock() }; _cachedKey = newValue }
    }
    private static let keyTag = "hotel.encryption.key"
    private static let keyInitializedTag = "hotel.encryption.key.initialized"
    private static let minimumCiphertextBytes = 29
    static let envelopePrefix = "enc:v1:"

    private static var hasProvisionedKey: Bool {
        get { UserDefaults.standard.bool(forKey: keyInitializedTag) }
        set { UserDefaults.standard.set(newValue, forKey: keyInitializedTag) }
    }

    /// 读取加密密钥（优先使用可同步 Keychain，必要时兼容旧的本地 Keychain）
    private static func encryptionKey(createIfMissing: Bool) throws -> SymmetricKey {
        if let cachedKey {
            return cachedKey
        }

        do {
            return try loadExistingKey()
        } catch EncryptionError.keyUnavailable {
            guard createIfMissing, !hasProvisionedKey else {
                throw EncryptionError.keyUnavailable
            }
        }

        let newKey = SymmetricKey(size: .bits256)
        let encodedKey = keyData(for: newKey).base64EncodedString()
        let savedLocally = KeychainHelper.save(key: keyTag, value: encodedKey)
        let savedSynchronizable = KeychainHelper.save(key: keyTag, value: encodedKey, synchronizable: true)

        guard savedLocally || savedSynchronizable else {
            throw EncryptionError.keyPersistenceFailed
        }

        cachedKey = newKey
        hasProvisionedKey = true
        return newKey
    }

    private static func loadExistingKey() throws -> SymmetricKey {
        let synchronizableState = readStoredKeyState(synchronizable: true)
        if case .value(let key) = synchronizableState {
            cachedKey = key
            hasProvisionedKey = true
            return key
        }

        let localState = readStoredKeyState(synchronizable: false)
        if case .value(let key) = localState {
            cachedKey = key
            hasProvisionedKey = true
            _ = KeychainHelper.save(
                key: keyTag,
                value: keyData(for: key).base64EncodedString(),
                synchronizable: true
            )
            return key
        }

        if case .invalid = synchronizableState {
            throw EncryptionError.keyCorrupted
        }
        if case .invalid = localState {
            throw EncryptionError.keyCorrupted
        }

        throw EncryptionError.keyUnavailable
    }

    private static func readStoredKeyState(synchronizable: Bool) -> StoredKeyState {
        guard let stored = KeychainHelper.read(key: keyTag, synchronizable: synchronizable) else {
            return .missing
        }
        guard let keyData = Data(base64Encoded: stored), keyData.count == 32 else {
            return .invalid
        }
        return .value(SymmetricKey(data: keyData))
    }

    private static func keyData(for key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private static func storageFormat(for text: String) throws -> StorageFormat {
        if text.hasPrefix(envelopePrefix) {
            let payload = String(text.dropFirst(envelopePrefix.count))
            guard isPlausibleCiphertext(payload) else {
                throw EncryptionError.invalidCiphertext
            }
            return .encrypted(payload)
        }

        if isPlausibleCiphertext(text) {
            return .encrypted(text)
        }

        return .plaintext
    }

    private static func isPlausibleCiphertext(_ text: String) -> Bool {
        guard let data = Data(base64Encoded: text) else { return false }
        return data.count >= minimumCiphertextBytes
    }

    /// 加密字符串，返回带版本前缀的密文
    static func encrypt(_ plaintext: String) throws -> String {
        guard !plaintext.isEmpty else { return "" }

        let data = Data(plaintext.utf8)
        do {
            let sealedBox = try AES.GCM.seal(data, using: try encryptionKey(createIfMissing: true))
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed
            }
            return envelopePrefix + combined.base64EncodedString()
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }

    /// 解密存储值，兼容旧版无前缀密文与更早期明文数据
    static func decrypt(_ ciphertext: String) throws -> String {
        guard !ciphertext.isEmpty else { return "" }

        switch try storageFormat(for: ciphertext) {
        case .plaintext:
            return ciphertext
        case .encrypted(let payload):
            guard let data = Data(base64Encoded: payload) else {
                throw EncryptionError.invalidCiphertext
            }
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: data)
                let decryptedData = try AES.GCM.open(sealedBox, using: try encryptionKey(createIfMissing: false))
                guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
                    throw EncryptionError.invalidCiphertext
                }
                return plaintext
            } catch let error as EncryptionError {
                throw error
            } catch {
                throw EncryptionError.decryptionFailed
            }
        }
    }

    /// 判断字符串是否为受保护格式
    static func isEncrypted(_ text: String) -> Bool {
        text.hasPrefix(envelopePrefix) || isPlausibleCiphertext(text)
    }

#if DEBUG
    static func resetForTesting(removeStoredKey: Bool = true, clearProvisionedState: Bool = true) {
        cachedKey = nil
        if removeStoredKey {
            _ = KeychainHelper.delete(key: keyTag)
            _ = KeychainHelper.delete(key: keyTag, synchronizable: true)
        }
        if clearProvisionedState {
            UserDefaults.standard.removeObject(forKey: keyInitializedTag)
        }
    }
#endif
}
