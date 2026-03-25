import Foundation

private let roomLockTTL: TimeInterval = 300

/// 房间锁定服务 — 防止多人同时对同一间房办理入住
/// 注意：锁仅存在本地，不跨设备同步。多设备防超卖依赖 CheckInViewModel 的入住前状态检查。
@MainActor
final class RoomLockService: ObservableObject {
    static let shared = RoomLockService()

    /// 锁定有效期（秒）。超过此时间自动释放，防止死锁
    static let lockTTL: TimeInterval = roomLockTTL // 5分钟

    /// roomID → lock info
    @Published private(set) var locks: [String: RoomLock] = [:]

    private let fileManager = FileManager.default
    private let filePath: URL

    struct RoomLock: Codable {
        let roomID: String
        let staffID: String
        let staffName: String
        let lockedAt: Date

        var isExpired: Bool {
            Date().timeIntervalSince(lockedAt) > roomLockTTL
        }
    }

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        filePath = dir.appendingPathComponent("room_locks.json")
        loadLocks()
        cleanExpired()
    }

    // MARK: - 锁定操作

    /// 尝试锁定房间。成功返回 true，已被他人锁定返回 false
    @discardableResult
    func tryLock(roomID: String) -> Bool {
        cleanExpired()
        let staff = StaffService.shared.currentStaff

        // 已被当前用户锁定 → 成功（续期）
        if let existing = locks[roomID], !existing.isExpired {
            if existing.staffID == staff?.id {
                // 续期
                locks[roomID] = RoomLock(
                    roomID: roomID,
                    staffID: staff?.id ?? "",
                    staffName: staff?.name ?? "未知",
                    lockedAt: Date()
                )
                persist()
                return true
            }
            // 被他人锁定
            return false
        }

        // 未锁定 → 加锁
        locks[roomID] = RoomLock(
            roomID: roomID,
            staffID: staff?.id ?? "",
            staffName: staff?.name ?? "未知",
            lockedAt: Date()
        )
        persist()
        return true
    }

    /// 释放锁定
    func unlock(roomID: String) {
        let staff = StaffService.shared.currentStaff
        // 只能释放自己的锁
        if let existing = locks[roomID], existing.staffID == staff?.id {
            locks.removeValue(forKey: roomID)
            persist()
        }
    }

    /// 强制释放（管理员用或过期清理）
    func forceUnlock(roomID: String) {
        locks.removeValue(forKey: roomID)
        persist()
    }

    // MARK: - 查询

    /// 房间是否被锁定（排除当前用户自己的锁）
    func isLockedByOther(roomID: String) -> Bool {
        guard let lock = locks[roomID], !lock.isExpired else { return false }
        return lock.staffID != StaffService.shared.currentStaff?.id
    }

    /// 获取锁定信息
    func lockInfo(roomID: String) -> RoomLock? {
        guard let lock = locks[roomID], !lock.isExpired else { return nil }
        return lock
    }

    /// 房间是否被当前用户锁定
    func isLockedByMe(roomID: String) -> Bool {
        guard let lock = locks[roomID], !lock.isExpired else { return false }
        return lock.staffID == StaffService.shared.currentStaff?.id
    }

    // MARK: - 清理过期锁

    private func cleanExpired() {
        let before = locks.count
        locks = locks.filter { !$0.value.isExpired }
        if locks.count != before { persist() }
    }

    // MARK: - 持久化

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Array(locks.values)) else { return }
        try? data.write(to: filePath, options: .atomic)
    }

    private func loadLocks() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([RoomLock].self, from: data) else { return }
        locks = Dictionary(uniqueKeysWithValues: items.map { ($0.roomID, $0) })
    }
}
