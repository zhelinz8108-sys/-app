import SwiftUI

/// 管理员模式管理器
/// 员工 iPad 看不到「数据」页面，管理员输入密码后解锁
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let keychainKey = "managerPasswordHash"
    private static let migrationKey = "passwordMigratedToKeychain"

    /// 是否已解锁管理员模式（不再持久化到 UserDefaults，仅从登录状态派生）
    @Published var isManagerMode: Bool = false

    /// 管理员密码哈希（存 Keychain）
    var managerPasswordHash: String {
        get {
            KeychainHelper.read(key: Self.keychainKey)
                ?? KeychainHelper.read(key: Self.keychainKey, synchronizable: true)
                ?? ""
        }
        set {
            KeychainHelper.save(key: Self.keychainKey, value: newValue)
            KeychainHelper.save(key: Self.keychainKey, value: newValue, synchronizable: true)
        }
    }

    private init() {
        // isManagerMode 不再从 UserDefaults 读取，每次启动默认 false，需登录后由 StaffService 设置
        migrateFromUserDefaults()
    }

    /// 从 UserDefaults 明文迁移到 Keychain 哈希
    private func migrateFromUserDefaults() {
        let migrated = UserDefaults.standard.bool(forKey: Self.migrationKey)
        guard !migrated else { return }

        // 读取旧密码（UserDefaults 明文）
        if let oldPassword = UserDefaults.standard.string(forKey: "managerPassword") {
            let hash = KeychainHelper.hashPassword(oldPassword)
            KeychainHelper.save(key: Self.keychainKey, value: hash)
            // 删除 UserDefaults 中的明文密码
            UserDefaults.standard.removeObject(forKey: "managerPassword")
        }

        UserDefaults.standard.set(true, forKey: Self.migrationKey)
    }

    /// 验证密码
    func verifyPassword(_ input: String) -> Bool {
        KeychainHelper.verifyPassword(input, against: managerPasswordHash)
    }

    /// 修改密码
    func changePassword(to newPassword: String) {
        managerPasswordHash = KeychainHelper.hashPassword(newPassword)
    }

    /// 登出管理员模式
    func logout() {
        isManagerMode = false
    }
}
