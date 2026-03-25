import Foundation

/// 员工管理服务
@MainActor
final class StaffService: ObservableObject {
    static let shared = StaffService()
    private static let bootstrapUsername = "admin"
    private static let bootstrapPassword = "8888"

    /// 当前登录的员工
    @Published var currentStaff: Staff?
    @Published private(set) var credentialIntegrityIssue: String?

    private let fileManager = FileManager.default
    private let filePath: URL
    private let loginAttemptsPath: URL
    private var staffList: [Staff] = []
    private var knownPasswordEntryIDs: Set<String> = []

    private struct LoginAttemptState: Codable {
        var failedAttempts: Int
        var lockoutUntil: Date?
    }

    private var loginAttempts: [String: LoginAttemptState] = [:]

    var isLoggedIn: Bool { currentStaff != nil }
    var isManager: Bool { currentStaff?.role == .manager }
    var currentName: String { currentStaff?.name ?? "未登录" }
    var requiresMandatoryPasswordChange: Bool {
        guard let currentStaff, currentStaff.isActive else { return false }
        return usesDefaultPassword(currentStaff)
    }
    var mandatoryPasswordChangeMessage: String {
        guard let currentStaff else {
            return "请先修改默认密码后再继续使用系统。"
        }
        if currentStaff.username == Self.bootstrapUsername {
            return "检测到系统仍在使用首装默认管理员密码。正式营业前必须先修改。"
        }
        return "检测到当前账号仍在使用默认密码。为了保护前台数据，请先完成改密。"
    }
    var shouldShowBootstrapHint: Bool {
        guard credentialIntegrityIssue == nil,
              staffList.count == 1,
              let staff = staffList.first,
              staff.username == Self.bootstrapUsername,
              staff.role == .manager,
              staff.isActive else {
            return false
        }
        return usesDefaultPassword(staff)
    }

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        filePath = dir.appendingPathComponent("staff.json")
        loginAttemptsPath = dir.appendingPathComponent("staff_login_attempts.json")
        loadStaff()
        loadLoginAttempts()
        ensureDefaultAdmin()
    }

    // MARK: - 登录/登出

    private static let maxAttempts = 5
    private static let lockoutDuration: TimeInterval = 300 // 5分钟

    func isLockedOut(username: String) -> Bool {
        currentLoginAttemptState(for: normalizeUsername(username))?.lockoutUntil != nil
    }

    func lockoutRemainingSeconds(for username: String) -> Int {
        guard let until = currentLoginAttemptState(for: normalizeUsername(username))?.lockoutUntil else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSinceNow)))
    }

    func login(username: String, password: String) -> Bool {
        let normalizedUsername = normalizeUsername(username)
        guard !isLockedOut(username: normalizedUsername) else { return false }

        guard let staff = staffList.first(where: {
            normalizeUsername($0.username) == normalizedUsername && $0.isActive
        }) else {
            recordFailedAttempt(for: normalizedUsername)
            return false
        }

        guard staff.verifyPassword(password) else {
            recordFailedAttempt(for: normalizedUsername)
            return false
        }

        clearFailedAttempts(for: normalizedUsername)
        currentStaff = staff
        AppSettings.shared.isManagerMode = (staff.role == .manager)
        return true
    }

    private func recordFailedAttempt(for username: String) {
        guard !username.isEmpty else { return }
        var state = currentLoginAttemptState(for: username) ?? LoginAttemptState(failedAttempts: 0, lockoutUntil: nil)
        state.failedAttempts += 1
        if state.failedAttempts >= Self.maxAttempts {
            state.lockoutUntil = Date().addingTimeInterval(Self.lockoutDuration)
        }
        loginAttempts[username] = state
        persistLoginAttempts()
    }

    private func clearFailedAttempts(for username: String) {
        guard !username.isEmpty else { return }
        loginAttempts.removeValue(forKey: username)
        persistLoginAttempts()
    }

    func logout() {
        currentStaff = nil
        AppSettings.shared.isManagerMode = false
    }

    // MARK: - 员工 CRUD

    func fetchAll() -> [Staff] {
        staffList.sorted { a, b in
            if a.role != b.role { return a.role == .manager }
            return a.name < b.name
        }
    }

    func fetchActive() -> [Staff] {
        fetchAll().filter { $0.isActive }
    }

    func addStaff(_ staff: Staff) {
        staffList.append(staff)
        persist()
    }

    func updateStaff(_ staff: Staff) {
        if let idx = staffList.firstIndex(where: { $0.id == staff.id }) {
            let oldUsername = staffList[idx].username
            staffList[idx] = staff
            clearFailedAttempts(for: normalizeUsername(oldUsername))
            clearFailedAttempts(for: normalizeUsername(staff.username))
            // 如果修改的是当前登录用户，更新 currentStaff
            if currentStaff?.id == staff.id {
                currentStaff = staff
                AppSettings.shared.isManagerMode = (staff.role == .manager)
            }
            persist()
        }
    }

    func deleteStaff(id: String) {
        // 不能删除自己
        guard id != currentStaff?.id else { return }
        if let staff = staffList.first(where: { $0.id == id }) {
            clearFailedAttempts(for: normalizeUsername(staff.username))
        }
        staffList.removeAll { $0.id == id }
        persist()
    }

    func toggleActive(id: String) {
        guard id != currentStaff?.id else { return }
        if let idx = staffList.firstIndex(where: { $0.id == id }) {
            staffList[idx].isActive.toggle()
            persist()
        }
    }

    /// 修改密码
    func changePassword(staffID: String, newPassword: String) {
        if let idx = staffList.firstIndex(where: { $0.id == staffID }) {
            staffList[idx].passwordHash = KeychainHelper.hashPassword(newPassword)
            clearFailedAttempts(for: normalizeUsername(staffList[idx].username))
            if currentStaff?.id == staffID {
                currentStaff = staffList[idx]
            }
            persist()
        }
    }

    /// 检查用户名是否已存在
    func isUsernameTaken(_ username: String, excludingID: String? = nil) -> Bool {
        let normalizedUsername = normalizeUsername(username)
        return staffList.contains { normalizeUsername($0.username) == normalizedUsername && $0.id != excludingID }
    }

    func passwordPolicyError(for password: String) -> String? {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            return "密码至少需要 8 位"
        }
        guard trimmed != Self.bootstrapPassword else {
            return "不能继续使用默认密码 8888"
        }

        let hasLetter = trimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let hasDigit = trimmed.range(of: "[0-9]", options: .regularExpression) != nil
        guard hasLetter && hasDigit else {
            return "密码需同时包含字母和数字"
        }
        return nil
    }

    /// 员工总数
    var count: Int { staffList.count }

    // MARK: - 持久化

    /// Codable wrapper that excludes passwordHash from JSON
    private struct CodableStaff: Codable {
        let id: String
        var name: String
        var username: String
        var role: StaffRole
        var phone: String
        var isActive: Bool
    }

    private func persist() {
        BackupService.shared.markDirty()
        // Save staff data without password hashes
        let codableList = staffList.map { s in
            CodableStaff(id: s.id, name: s.name, username: s.username,
                         role: s.role, phone: s.phone, isActive: s.isActive)
        }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(codableList) else { return }
        try? data.write(to: filePath, options: .atomic)

        let currentIDs = Set(staffList.map(\.id))
        for removedID in knownPasswordEntryIDs.subtracting(currentIDs) {
            KeychainHelper.delete(key: "staff_pw_\(removedID)")
            KeychainHelper.delete(key: "staff_pw_\(removedID)", synchronizable: true)
        }

        // Store password hashes in Keychain keyed by staff ID
        for staff in staffList {
            KeychainHelper.save(key: "staff_pw_\(staff.id)", value: staff.passwordHash)
            KeychainHelper.save(key: "staff_pw_\(staff.id)", value: staff.passwordHash, synchronizable: true)
        }
        knownPasswordEntryIDs = currentIDs
        refreshCredentialIntegrityIssue()
    }

    private func loadStaff() {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: filePath) else {
            refreshCredentialIntegrityIssue()
            return
        }

        // Try loading new format (without passwordHash)
        if let items = try? decoder.decode([CodableStaff].self, from: data) {
            staffList = items.map { c in
                let hash = readStoredPasswordHash(for: c.id)
                return Staff(id: c.id, name: c.name, username: c.username,
                             existingHash: hash, role: c.role, phone: c.phone, isActive: c.isActive)
            }
            knownPasswordEntryIDs = Set(staffList.map(\.id))
            refreshCredentialIntegrityIssue()
            return
        }

        // Fallback: try loading legacy format (with passwordHash)
        if let items = try? decoder.decode([Staff].self, from: data) {
            staffList = items
            // Migrate: save hashes to Keychain and re-persist without hashes
            persist()
            return
        }

        refreshCredentialIntegrityIssue()
    }

    private func persistLoginAttempts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(loginAttempts) else { return }
        try? data.write(to: loginAttemptsPath, options: .atomic)
    }

    private func loadLoginAttempts() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: loginAttemptsPath),
              let items = try? decoder.decode([String: LoginAttemptState].self, from: data) else {
            loginAttempts = [:]
            return
        }
        loginAttempts = items
        cleanupExpiredLoginAttempts()
    }

    private func cleanupExpiredLoginAttempts() {
        let now = Date()
        loginAttempts = loginAttempts.filter { _, state in
            guard let until = state.lockoutUntil else { return true }
            return until > now
        }
        persistLoginAttempts()
    }

    private func currentLoginAttemptState(for username: String) -> LoginAttemptState? {
        guard !username.isEmpty else { return nil }
        guard var state = loginAttempts[username] else { return nil }
        if let until = state.lockoutUntil, until <= Date() {
            loginAttempts.removeValue(forKey: username)
            persistLoginAttempts()
            return nil
        }
        if state.failedAttempts < Self.maxAttempts {
            state.lockoutUntil = nil
        }
        return state
    }

    private func normalizeUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func usesDefaultPassword(_ staff: Staff) -> Bool {
        staff.verifyPassword(Self.bootstrapPassword)
    }

    private func readStoredPasswordHash(for staffID: String) -> String {
        KeychainHelper.read(key: "staff_pw_\(staffID)")
            ?? KeychainHelper.read(key: "staff_pw_\(staffID)", synchronizable: true)
            ?? ""
    }

    private func refreshCredentialIntegrityIssue() {
        let affectedManagers = staffList.filter { $0.role == .manager && $0.passwordHash.isEmpty }
        if !affectedManagers.isEmpty {
            credentialIntegrityIssue = "检测到管理员凭据丢失。系统不会自动恢复默认密码，请通过备份恢复后再登录。"
            return
        }

        let affectedStaff = staffList.filter { $0.passwordHash.isEmpty }
        if !affectedStaff.isEmpty {
            credentialIntegrityIssue = "检测到员工凭据丢失。缺失凭据的账号已无法登录，请通过备份恢复后再重试。"
            return
        }

        credentialIntegrityIssue = nil
    }

    /// 确保至少有一个管理员账号，且密码哈希可用
    private func ensureDefaultAdmin() {
        let hasManager = staffList.contains { $0.role == .manager }
        if !hasManager {
            let admin = Staff(
                name: "管理员",
                username: Self.bootstrapUsername,
                password: Self.bootstrapPassword,
                role: .manager,
                phone: ""
            )
            staffList.append(admin)
            persist()
            return
        }

        refreshCredentialIntegrityIssue()
    }

#if DEBUG
    func resetForTesting(staff newStaffList: [Staff] = []) {
        for id in knownPasswordEntryIDs {
            KeychainHelper.delete(key: "staff_pw_\(id)")
            KeychainHelper.delete(key: "staff_pw_\(id)", synchronizable: true)
        }
        currentStaff = nil
        staffList = newStaffList
        knownPasswordEntryIDs = []
        loginAttempts = [:]
        credentialIntegrityIssue = nil
        try? fileManager.removeItem(at: filePath)
        try? fileManager.removeItem(at: loginAttemptsPath)
        if newStaffList.isEmpty {
            refreshCredentialIntegrityIssue()
            return
        }
        persist()
    }

    func reloadForTesting() {
        currentStaff = nil
        staffList = []
        knownPasswordEntryIDs = []
        loginAttempts = [:]
        credentialIntegrityIssue = nil
        loadStaff()
        loadLoginAttempts()
        ensureDefaultAdmin()
    }
#endif
}
