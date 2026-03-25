import Foundation

/// 员工角色
enum StaffRole: String, Codable, CaseIterable, Identifiable {
    case manager = "管理员"
    case employee = "前台员工"

    var id: String { rawValue }
}

/// 员工模型
struct Staff: Identifiable, Codable {
    let id: String
    var name: String
    var username: String // 登录用户名
    var passwordHash: String
    var role: StaffRole
    var phone: String
    var isActive: Bool // 是否启用

    init(
        id: String = UUID().uuidString,
        name: String,
        username: String,
        password: String,
        role: StaffRole = .employee,
        phone: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.passwordHash = KeychainHelper.hashPassword(password)
        self.role = role
        self.phone = phone
        self.isActive = isActive
    }

    /// 从存储加载时使用（不重新哈希）
    init(id: String, name: String, username: String, existingHash: String, role: StaffRole, phone: String, isActive: Bool) {
        self.id = id
        self.name = name
        self.username = username
        self.passwordHash = existingHash
        self.role = role
        self.phone = phone
        self.isActive = isActive
    }

    func verifyPassword(_ input: String) -> Bool {
        KeychainHelper.verifyPassword(input, against: passwordHash)
    }
}
