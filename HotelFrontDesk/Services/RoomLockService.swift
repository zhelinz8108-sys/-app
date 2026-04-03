import UIKit
import CloudKit
import Foundation

private let roomLockTTL: TimeInterval = 300

/// 房间锁定服务 — 防止多人同时对同一间房办理入住
/// 通过 CloudKit 跨设备同步锁状态。CloudKit 不可用时降级为本地锁（带警告标记）。
@MainActor
final class RoomLockService: ObservableObject {
    static let shared = RoomLockService()

    /// 锁定有效期（秒）。超过此时间自动释放，防止死锁
    static let lockTTL: TimeInterval = roomLockTTL // 5分钟

    /// CloudKit 记录类型
    static let recordType = "RoomLock"

    /// roomID → lock info
    @Published private(set) var locks: [String: RoomLock] = [:]

    /// 是否处于仅本地锁模式（CloudKit 不可用时为 true）
    @Published private(set) var isLocalOnly = false

    private let fileManager = FileManager.default
    private let filePath: URL
    private lazy var db = CloudKitConfig.database
    private let deviceID: String

    struct RoomLock: Codable {
        let roomID: String
        let deviceID: String
        let staffID: String
        let staffName: String
        let lockedAt: Date
        let expiresAt: Date
        /// CloudKit recordName，用于删除
        var cloudRecordName: String?

        var isExpired: Bool {
            Date() > expiresAt
        }

        // 兼容旧格式（缺少 deviceID/expiresAt/cloudRecordName 字段）
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            roomID = try container.decode(String.self, forKey: .roomID)
            deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
            staffID = try container.decode(String.self, forKey: .staffID)
            staffName = try container.decode(String.self, forKey: .staffName)
            lockedAt = try container.decode(Date.self, forKey: .lockedAt)
            expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
                ?? lockedAt.addingTimeInterval(roomLockTTL)
            cloudRecordName = try container.decodeIfPresent(String.self, forKey: .cloudRecordName)
        }

        init(roomID: String, deviceID: String, staffID: String, staffName: String,
             lockedAt: Date, expiresAt: Date, cloudRecordName: String? = nil) {
            self.roomID = roomID
            self.deviceID = deviceID
            self.staffID = staffID
            self.staffName = staffName
            self.lockedAt = lockedAt
            self.expiresAt = expiresAt
            self.cloudRecordName = cloudRecordName
        }
    }

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: dir, excludeFromBackup: true)
        filePath = dir.appendingPathComponent("room_locks.json")

        // 用 identifierForVendor 区分不同 iPad
        deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        loadLocks()
        cleanExpired()
    }

    // MARK: - 锁定操作

    /// 尝试锁定房间。先检查 CloudKit 远端是否已被锁定，再加锁。
    /// 成功返回 true，已被他人锁定返回 false。
    @discardableResult
    func tryLock(roomID: String) async -> Bool {
        cleanExpired()
        let staff = StaffService.shared.currentStaff
        let now = Date()
        let expiry = now.addingTimeInterval(roomLockTTL)

        // 本地已被当前用户锁定 → 续期
        if let existing = locks[roomID], !existing.isExpired,
           existing.staffID == staff?.id, existing.deviceID == deviceID {
            let renewed = RoomLock(
                roomID: roomID,
                deviceID: deviceID,
                staffID: staff?.id ?? "",
                staffName: staff?.name ?? "未知",
                lockedAt: now,
                expiresAt: expiry,
                cloudRecordName: existing.cloudRecordName
            )
            locks[roomID] = renewed
            persist()
            // 续期也更新 CloudKit（fire-and-forget）
            let record = renewed.toRecord()
            Task { try? await db.save(record) }
            return true
        }

        // ── 检查 CloudKit 远端锁 ──
        do {
            let remoteLock = try await fetchRemoteLock(roomID: roomID)
            if let remote = remoteLock, !remote.isExpired {
                // 远端被同一用户在同一设备锁定 → 续期
                if remote.staffID == staff?.id && remote.deviceID == deviceID {
                    // fall through to acquire
                } else {
                    // 远端被他人锁定 → 合并到本地并返回失败
                    locks[roomID] = remote
                    persist()
                    return false
                }
            }

            // ── 加锁：先写 CloudKit 再写本地 ──
            let newLock = RoomLock(
                roomID: roomID,
                deviceID: deviceID,
                staffID: staff?.id ?? "",
                staffName: staff?.name ?? "未知",
                lockedAt: now,
                expiresAt: expiry
            )
            let record = newLock.toRecord()
            let saved = try await db.save(record)

            var lockWithCloud = newLock
            lockWithCloud.cloudRecordName = saved.recordID.recordName
            locks[roomID] = lockWithCloud
            isLocalOnly = false
            persist()
            return true

        } catch {
            // CloudKit 不可用 → 降级为本地锁
            print("⚠️ CloudKit 锁服务不可用，降级为本地锁: \(error.localizedDescription)")

            // 本地已被他人锁定
            if let existing = locks[roomID], !existing.isExpired,
               existing.staffID != staff?.id {
                return false
            }

            let localLock = RoomLock(
                roomID: roomID,
                deviceID: deviceID,
                staffID: staff?.id ?? "",
                staffName: staff?.name ?? "未知",
                lockedAt: now,
                expiresAt: expiry
            )
            locks[roomID] = localLock
            isLocalOnly = true
            persist()
            return true
        }
    }

    /// 释放锁定
    func unlock(roomID: String) {
        let staff = StaffService.shared.currentStaff
        // 只能释放自己的锁
        guard let existing = locks[roomID], existing.staffID == staff?.id else { return }
        let recordName = existing.cloudRecordName
        locks.removeValue(forKey: roomID)
        persist()

        // 删除 CloudKit 记录（fire-and-forget）
        if let name = recordName {
            Task { [db] in
                try? await db.deleteRecord(withID: CKRecord.ID(recordName: name))
            }
        }
    }

    /// 强制释放（管理员用或过期清理）
    func forceUnlock(roomID: String) {
        let recordName = locks[roomID]?.cloudRecordName
        locks.removeValue(forKey: roomID)
        persist()

        // 删除 CloudKit 记录（fire-and-forget）
        if let name = recordName {
            Task { [db] in
                try? await db.deleteRecord(withID: CKRecord.ID(recordName: name))
            }
        }
    }

    /// 强制释放所有超过 TTL 的过期锁（包括远端）
    func cleanStaleLocks() async {
        // 清理本地过期锁
        let expiredLocal = locks.filter { $0.value.isExpired }
        for (roomID, lock) in expiredLocal {
            locks.removeValue(forKey: roomID)
            if let name = lock.cloudRecordName {
                Task { [db] in
                    try? await db.deleteRecord(withID: CKRecord.ID(recordName: name))
                }
            }
        }

        // 查询 CloudKit 中所有过期锁并删除
        do {
            let now = Date()
            let predicate = NSPredicate(format: "expiresAt < %@", now as NSDate)
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)
            let response = try await db.records(matching: query, resultsLimit: 200)
            var idsToDelete: [CKRecord.ID] = []
            for (_, result) in response.matchResults {
                if case .success(let record) = result {
                    idsToDelete.append(record.recordID)
                }
            }
            if !idsToDelete.isEmpty {
                _ = try? await db.modifyRecords(saving: [], deleting: idsToDelete)
                print("🧹 已清理 \(idsToDelete.count) 条远端过期锁")
            }
        } catch {
            print("⚠️ 清理远端过期锁失败: \(error.localizedDescription)")
        }

        if !expiredLocal.isEmpty { persist() }
    }

    // MARK: - 查询

    /// 房间是否被锁定（排除当前用户自己的锁）
    func isLockedByOther(roomID: String) -> Bool {
        guard let lock = locks[roomID], !lock.isExpired else { return false }
        let staff = StaffService.shared.currentStaff
        return !(lock.staffID == staff?.id && lock.deviceID == deviceID)
    }

    /// 获取锁定信息
    func lockInfo(roomID: String) -> RoomLock? {
        guard let lock = locks[roomID], !lock.isExpired else { return nil }
        return lock
    }

    /// 房间是否被当前用户锁定
    func isLockedByMe(roomID: String) -> Bool {
        guard let lock = locks[roomID], !lock.isExpired else { return false }
        let staff = StaffService.shared.currentStaff
        return lock.staffID == staff?.id && lock.deviceID == deviceID
    }

    // MARK: - 远端刷新

    /// 从 CloudKit 拉取所有有效锁，合并到本地
    func refreshFromCloud() async {
        do {
            let now = Date()
            let predicate = NSPredicate(format: "expiresAt > %@", now as NSDate)
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)
            let response = try await db.records(matching: query, resultsLimit: 200)

            var remoteLocks: [String: RoomLock] = [:]
            for (_, result) in response.matchResults {
                if case .success(let record) = result {
                    let lock = RoomLock(from: record)
                    if !lock.isExpired {
                        remoteLocks[lock.roomID] = lock
                    }
                }
            }

            // 合并策略：远端锁覆盖本地（远端是权威来源）
            // 保留本地自己的锁（如果远端没有更新的他人锁）
            let staff = StaffService.shared.currentStaff
            for (roomID, remoteLock) in remoteLocks {
                if let localLock = locks[roomID],
                   localLock.staffID == staff?.id,
                   localLock.deviceID == deviceID,
                   remoteLock.staffID == staff?.id,
                   remoteLock.deviceID == deviceID {
                    // 都是自己的锁，保留本地版本（可能更新）
                    continue
                }
                locks[roomID] = remoteLock
            }

            // 移除本地有但远端已不存在的他人锁
            for (roomID, localLock) in locks {
                if localLock.staffID != staff?.id || localLock.deviceID != deviceID {
                    if remoteLocks[roomID] == nil {
                        locks.removeValue(forKey: roomID)
                    }
                }
            }

            isLocalOnly = false
            persist()
        } catch {
            print("⚠️ 刷新远端锁失败: \(error.localizedDescription)")
        }
    }

    // MARK: - CloudKit 查询辅助

    /// 查询指定房间的远端锁
    private func fetchRemoteLock(roomID: String) async throws -> RoomLock? {
        let now = Date()
        let predicate = NSPredicate(
            format: "roomID == %@ AND expiresAt > %@",
            roomID, now as NSDate
        )
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        let response = try await db.records(matching: query, resultsLimit: 1)

        for (_, result) in response.matchResults {
            if case .success(let record) = result {
                let lock = RoomLock(from: record)
                if !lock.isExpired { return lock }
            }
        }
        return nil
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
        try? SecureStorageHelper.write(data, to: filePath, excludeFromBackup: true)
    }

    private func loadLocks() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([RoomLock].self, from: data) else { return }
        locks = Dictionary(uniqueKeysWithValues: items.map { ($0.roomID, $0) })
    }
}

// MARK: - RoomLock CloudKit Conversion

extension RoomLockService.RoomLock {
    /// 从 CloudKit 记录初始化
    init(from record: CKRecord) {
        self.init(
            roomID: record["roomID"] as? String ?? "",
            deviceID: record["deviceID"] as? String ?? "",
            staffID: record["staffID"] as? String ?? "",
            staffName: record["lockedBy"] as? String ?? "未知",
            lockedAt: record["lockedAt"] as? Date ?? Date(),
            expiresAt: record["expiresAt"] as? Date ?? Date(),
            cloudRecordName: record.recordID.recordName
        )
    }

    /// 转为 CloudKit 记录
    func toRecord() -> CKRecord {
        let recordName = cloudRecordName ?? "RoomLock_\(roomID)_\(UUID().uuidString)"
        let record = CKRecord(
            recordType: RoomLockService.recordType,
            recordID: CKRecord.ID(recordName: recordName)
        )
        record["roomID"] = roomID as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue
        record["staffID"] = staffID as CKRecordValue
        record["lockedBy"] = staffName as CKRecordValue
        record["lockedAt"] = lockedAt as CKRecordValue
        record["expiresAt"] = expiresAt as CKRecordValue
        return record
    }
}
