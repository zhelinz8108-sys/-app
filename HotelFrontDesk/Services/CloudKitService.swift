import CloudKit
import Foundation

// MARK: - CloudKit 数据服务（CloudKit 不可用时自动降级为本地存储）
@MainActor
final class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let retryInterval: TimeInterval = 60 // 每 60 秒重试

    private enum SyncStateKey {
        static let pendingLocalSync = "CloudKitService.pendingLocalSync"
    }

    private lazy var db = CloudKitConfig.database
    private let local = LocalStorageService.shared
    private let userDefaults = UserDefaults.standard

    /// 是否使用本地存储模式（默认 true，CloudKit 确认可用后才切换为 false）
    @Published private(set) var isLocalMode = true
    @Published private(set) var dataProtectionIssue: String?

    /// 重试定时器
    private var retryTask: Task<Void, Never>?

    private var hasPendingLocalSync: Bool {
        get { userDefaults.bool(forKey: SyncStateKey.pendingLocalSync) }
        set { userDefaults.set(newValue, forKey: SyncStateKey.pendingLocalSync) }
    }

    private init() {
        guard !Self.isRunningTests else {
            print("🧪 检测到测试环境，CloudKit 已禁用并强制使用本地存储")
            return
        }
        Task { await checkCloudKit() }
    }

    /// 检测 CloudKit 是否可用
    private func checkCloudKit() async {
        do {
            let status = try await CKContainer(identifier: CloudKitConfig.containerID).accountStatus()
            guard status == .available else {
                print("📱 iCloud 账号不可用(status=\(status))，使用本地存储")
                startRetryTimer()
                return
            }

            // 试一次查询确认容器可用
            let query = CKQuery(recordType: Room.recordType, predicate: NSPredicate(value: true))
            _ = try await db.records(matching: query, resultsLimit: 1)

            let wasLocalMode = isLocalMode
            isLocalMode = false
            dataProtectionIssue = nil
            stopRetryTimer()
            print("☁️ CloudKit 可用，已切换到云端模式")

            guard wasLocalMode else { return }

            if hasPendingLocalSync {
                let didSync = await syncLocalDataToCloud()
                guard didSync else {
                    isLocalMode = true
                    startRetryTimer()
                    print("⚠️ 待同步本地数据上传失败，继续使用本地模式")
                    return
                }
            }

            await refreshLocalMirrorFromCloud()
        } catch {
            isLocalMode = true
            print("📱 CloudKit 不可用，保持本地存储: \(error.localizedDescription)")
            startRetryTimer()
        }
    }

    // MARK: - 重试机制

    /// 启动定时重试（仅在本地模式时运行）
    private func startRetryTimer() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.retryInterval))
                guard !Task.isCancelled else { break }
                await self?.checkCloudKit()
                if self?.isLocalMode == false {
                    break
                }
            }
        }
    }

    /// 停止重试
    private func stopRetryTimer() {
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: - 本地数据同步与镜像

    private func markPendingLocalSync() {
        hasPendingLocalSync = true
    }

    private func clearPendingLocalSync() {
        hasPendingLocalSync = false
    }

    /// 将本地存储中的数据批量同步到 CloudKit
    @discardableResult
    private func syncLocalDataToCloud() async -> Bool {
        print("🔄 开始同步本地数据到 CloudKit...")
        do {
            let rooms = local.fetchAllRooms()
            let guests = local.fetchAllGuests()
            let reservations = local.fetchAllReservations()
            let deposits = local.fetchAllDeposits()

            let guestRecords = try guests.map { try $0.toRecord() }

            try await saveRecordsInBatches(rooms.map { $0.toRecord() })
            try await saveRecordsInBatches(guestRecords)
            try await saveRecordsInBatches(reservations.map { $0.toRecord() })
            try await saveRecordsInBatches(deposits.map { $0.toRecord() })

            clearPendingLocalSync()
            print("✅ 本地数据同步完成：\(rooms.count) 房间, \(guests.count) 客人, \(reservations.count) 预订, \(deposits.count) 押金")
            return true
        } catch {
            recordDataProtectionIssueIfNeeded(error)
            markPendingLocalSync()
            print("⚠️ 本地数据同步失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 从 CloudKit 拉取全量数据，下沉到本地镜像，供离线回退与备份使用
    private func refreshLocalMirrorFromCloud() async {
        print("🔄 开始刷新本地镜像...")
        do {
            async let rooms = fetchAllRoomModels()
            async let guests = fetchAllGuestModels()
            async let reservations = fetchAllReservationModels()
            async let deposits = fetchAllDepositModels()

            local.replaceAllData(
                rooms: try await rooms,
                guests: try await guests,
                reservations: try await reservations,
                deposits: try await deposits
            )
            dataProtectionIssue = nil
            print("✅ 本地镜像已刷新")
        } catch {
            recordDataProtectionIssueIfNeeded(error)
            print("⚠️ 本地镜像刷新失败: \(error.localizedDescription)")
        }
    }

    private func mirrorReservationsToLocal(_ reservations: [Reservation], replaceExisting: Bool = false) {
        guard !reservations.isEmpty else { return }
        local.mirrorRooms(reservations.compactMap(\.room))
        local.mirrorGuests(reservations.compactMap(\.guest))
        if replaceExisting {
            local.replaceReservations(reservations)
        } else {
            local.mirrorReservations(reservations)
        }
    }

    private func mirrorReservationToLocal(_ reservation: Reservation) {
        if let room = reservation.room {
            local.mirrorRoom(room)
        }
        if let guest = reservation.guest {
            local.mirrorGuest(guest)
        }
        local.mirrorReservation(reservation)
    }

    // MARK: - Room 操作

    func fetchAllRooms() async throws -> [Room] {
        if isLocalMode { return local.fetchAllRooms() }
        do {
            let rooms = try await fetchAllRoomModels()
            local.replaceRooms(rooms)
            return rooms
        } catch {
            fallbackToLocal(error)
            return local.fetchAllRooms()
        }
    }

    func fetchAllGuests() async throws -> [Guest] {
        if isLocalMode { return local.fetchAllGuests() }
        do {
            let guests = try await fetchAllGuestModels()
            local.replaceGuests(guests)
            return guests
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchAllGuests()
        }
    }

    func saveRoom(_ room: Room) async throws {
        if isLocalMode {
            local.saveRoom(room)
            markPendingLocalSync()
            return
        }
        do {
            let savedRecord = try await db.save(room.toRecord())
            local.mirrorRoom(Room(from: savedRecord))
        } catch {
            fallbackToLocal(error)
            local.saveRoom(room)
            markPendingLocalSync()
        }
    }

    func saveRooms(_ rooms: [Room]) async throws {
        if isLocalMode {
            local.saveRooms(rooms)
            markPendingLocalSync()
            return
        }
        do {
            try await saveRecordsInBatches(rooms.map { $0.toRecord() })
            local.mirrorRooms(rooms)
        } catch {
            fallbackToLocal(error)
            local.saveRooms(rooms)
            markPendingLocalSync()
        }
    }

    func updateRoomStatus(roomID: String, status: RoomStatus) async throws {
        if isLocalMode {
            local.updateRoomStatus(roomID: roomID, status: status)
            markPendingLocalSync()
            return
        }
        do {
            let recordID = CKRecord.ID(recordName: roomID)
            guard let record = try await fetchRecordIfExists(recordID) else {
                local.mirrorDeleteRoom(id: roomID)
                return
            }
            record["status"] = status.rawValue as CKRecordValue
            let savedRecord = try await db.save(record)
            local.mirrorRoom(Room(from: savedRecord))
        } catch {
            fallbackToLocal(error)
            local.updateRoomStatus(roomID: roomID, status: status)
            markPendingLocalSync()
        }
    }

    func deleteRoom(id: String) async throws {
        if isLocalMode {
            local.deleteRoom(id: id)
            markPendingLocalSync()
            return
        }
        do {
            try await db.deleteRecord(withID: CKRecord.ID(recordName: id))
            local.mirrorDeleteRoom(id: id)
        } catch {
            fallbackToLocal(error)
            local.deleteRoom(id: id)
            markPendingLocalSync()
        }
    }

    // MARK: - Guest 操作

    func saveGuest(_ guest: Guest) async throws {
        _ = try guest.toRecord()
        if isLocalMode {
            local.saveGuest(guest)
            markPendingLocalSync()
            return
        }
        do {
            let savedRecord = try await db.save(try guest.toRecord())
            dataProtectionIssue = nil
            local.mirrorGuest(try Guest(from: savedRecord))
        } catch {
            guard fallbackToLocal(error) else { throw error }
            local.saveGuest(guest)
            markPendingLocalSync()
        }
    }

    func deleteGuest(id: String) async throws {
        if isLocalMode {
            local.deleteGuest(id: id)
            markPendingLocalSync()
            return
        }
        do {
            try await db.deleteRecord(withID: CKRecord.ID(recordName: id))
            local.mirrorDeleteGuest(id: id)
        } catch {
            fallbackToLocal(error)
            local.deleteGuest(id: id)
            markPendingLocalSync()
        }
    }

    func fetchGuest(id: String) async throws -> Guest? {
        if isLocalMode { return local.fetchGuest(id: id) }
        do {
            let recordID = CKRecord.ID(recordName: id)
            guard let record = try await fetchRecordIfExists(recordID) else {
                local.mirrorDeleteGuest(id: id)
                return nil
            }
            let guest = try Guest(from: record)
            dataProtectionIssue = nil
            local.mirrorGuest(guest)
            return guest
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchGuest(id: id)
        }
    }

    // MARK: - Reservation 操作

    func saveReservation(_ reservation: Reservation) async throws {
        if isLocalMode {
            local.saveReservation(reservation)
            markPendingLocalSync()
            return
        }
        do {
            let savedRecord = try await db.save(reservation.toRecord())
            local.mirrorReservation(Reservation(from: savedRecord))
        } catch {
            fallbackToLocal(error)
            local.saveReservation(reservation)
            markPendingLocalSync()
        }
    }

    func deleteReservation(id: String) async throws {
        if isLocalMode {
            local.deleteReservation(id: id)
            markPendingLocalSync()
            return
        }
        do {
            try await db.deleteRecord(withID: CKRecord.ID(recordName: id))
            local.mirrorDeleteReservation(id: id)
        } catch {
            fallbackToLocal(error)
            local.deleteReservation(id: id)
            markPendingLocalSync()
        }
    }

    func deleteDeposit(id: String) async throws {
        if isLocalMode {
            local.deleteDeposit(id: id)
            markPendingLocalSync()
            return
        }
        do {
            try await db.deleteRecord(withID: CKRecord.ID(recordName: id))
            local.mirrorDeleteDeposit(id: id)
        } catch {
            fallbackToLocal(error)
            local.deleteDeposit(id: id)
            markPendingLocalSync()
        }
    }

    func fetchActiveReservations() async throws -> [Reservation] {
        if isLocalMode { return local.fetchActiveReservations() }
        do {
            let predicate = NSPredicate(format: "isActive == 1")
            let reservations = try await fetchHydratedReservations(
                predicate: predicate,
                sortDescriptors: [NSSortDescriptor(key: "checkInDate", ascending: false)]
            )
            mirrorReservationsToLocal(reservations)
            return reservations
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchActiveReservations()
        }
    }

    func fetchActiveReservation(forRoomID roomID: String) async throws -> Reservation? {
        if isLocalMode { return local.fetchActiveReservation(forRoomID: roomID) }
        do {
            let roomRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: roomID), action: .none)
            let predicate = NSPredicate(format: "roomRef == %@ AND isActive == 1", roomRef)
            let reservations = try await fetchHydratedReservations(predicate: predicate, limit: 1)
            let reservation = reservations.first
            if let reservation {
                mirrorReservationToLocal(reservation)
            }
            return reservation
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchActiveReservation(forRoomID: roomID)
        }
    }

    func checkOut(reservationID: String) async throws {
        if isLocalMode {
            local.checkOut(reservationID: reservationID)
            markPendingLocalSync()
            return
        }
        do {
            let recordID = CKRecord.ID(recordName: reservationID)
            guard let record = try await fetchRecordIfExists(recordID) else {
                local.mirrorDeleteReservation(id: reservationID)
                return
            }
            let checkoutTime = Date()
            record["isActive"] = 0 as CKRecordValue
            record["actualCheckOut"] = checkoutTime as CKRecordValue
            let savedRecord = try await db.save(record)
            local.mirrorReservation(Reservation(from: savedRecord))
        } catch {
            fallbackToLocal(error)
            local.checkOut(reservationID: reservationID)
            markPendingLocalSync()
        }
    }

    func fetchReservationHistory(forRoomID roomID: String, limit: Int = 50) async throws -> [Reservation] {
        if isLocalMode { return local.fetchReservationHistory(forRoomID: roomID, limit: limit) }
        do {
            let roomRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: roomID), action: .none)
            let predicate = NSPredicate(format: "roomRef == %@ AND isActive == 0", roomRef)
            let reservations = try await fetchHydratedReservations(
                predicate: predicate,
                sortDescriptors: [NSSortDescriptor(key: "checkInDate", ascending: false)],
                limit: limit
            )
            mirrorReservationsToLocal(reservations)
            return reservations
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchReservationHistory(forRoomID: roomID, limit: limit)
        }
    }

    // MARK: - DepositRecord 操作

    func saveDepositRecord(_ deposit: DepositRecord) async throws {
        if isLocalMode {
            local.saveDepositRecord(deposit)
            markPendingLocalSync()
            return
        }
        do {
            let savedRecord = try await db.save(deposit.toRecord())
            local.mirrorDeposit(DepositRecord(from: savedRecord))
        } catch {
            fallbackToLocal(error)
            local.saveDepositRecord(deposit)
            markPendingLocalSync()
        }
    }

    func fetchDeposits(forReservationID reservationID: String) async throws -> [DepositRecord] {
        if isLocalMode { return local.fetchDeposits(forReservationID: reservationID) }
        do {
            let resRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: reservationID), action: .none)
            let predicate = NSPredicate(format: "reservationRef == %@", resRef)
            let records = try await fetchRecords(
                recordType: DepositRecord.recordType,
                predicate: predicate,
                sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)]
            )
            let deposits = records.map(DepositRecord.init(from:))
            local.mirrorDeposits(deposits)
            return deposits
        } catch {
            fallbackToLocal(error)
            return local.fetchDeposits(forReservationID: reservationID)
        }
    }

    // MARK: - 组合查询

    func fetchTodayCheckInCount() async throws -> Int {
        if isLocalMode { return local.fetchTodayCheckInCount() }
        do {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                return local.fetchTodayCheckInCount()
            }
            let predicate = NSPredicate(format: "checkInDate >= %@ AND checkInDate < %@", startOfDay as NSDate, endOfDay as NSDate)
            let records = try await fetchRecords(recordType: Reservation.recordType, predicate: predicate)
            return records.count
        } catch {
            fallbackToLocal(error)
            return local.fetchTodayCheckInCount()
        }
    }

    func fetchTodayExpectedCheckOuts() async throws -> [Reservation] {
        if isLocalMode { return local.fetchTodayExpectedCheckOuts() }
        do {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                return local.fetchTodayExpectedCheckOuts()
            }
            let predicate = NSPredicate(format: "expectedCheckOut >= %@ AND expectedCheckOut < %@ AND isActive == 1", startOfDay as NSDate, endOfDay as NSDate)
            let reservations = try await fetchHydratedReservations(
                predicate: predicate,
                sortDescriptors: [NSSortDescriptor(key: "expectedCheckOut", ascending: true)]
            )
            mirrorReservationsToLocal(reservations)
            return reservations
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchTodayExpectedCheckOuts()
        }
    }

    // MARK: - 分析查询

    func fetchAllReservations() async throws -> [Reservation] {
        if isLocalMode { return local.fetchAllReservations() }
        do {
            let reservations = try await fetchHydratedReservations(
                predicate: NSPredicate(value: true),
                sortDescriptors: [NSSortDescriptor(key: "checkInDate", ascending: false)]
            )
            mirrorReservationsToLocal(reservations, replaceExisting: true)
            return reservations
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchAllReservations()
        }
    }

    func fetchAllDeposits() async throws -> [DepositRecord] {
        if isLocalMode { return local.fetchAllDeposits() }
        do {
            let deposits = try await fetchAllDepositModels()
            local.replaceDeposits(deposits)
            return deposits
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchAllDeposits()
        }
    }

    func fetchReservationsForMonth(year: Int, month: Int) async throws -> [Reservation] {
        if isLocalMode { return local.fetchReservationsForMonth(year: year, month: month) }
        guard let range = monthDateRange(year: year, month: month) else {
            return []
        }
        do {
            let monthPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isActive == 0"),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "actualCheckOut >= %@ AND actualCheckOut < %@", range.start as NSDate, range.end as NSDate),
                    NSPredicate(format: "expectedCheckOut >= %@ AND expectedCheckOut < %@", range.start as NSDate, range.end as NSDate),
                ])
            ])
            let reservations = try await fetchHydratedReservations(
                predicate: monthPredicate,
                sortDescriptors: [NSSortDescriptor(key: "actualCheckOut", ascending: false)]
            )
            let filtered = filterReservationsForMonth(reservations, year: year, month: month)
            mirrorReservationsToLocal(filtered)
            return filtered
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchReservationsForMonth(year: year, month: month)
        }
    }

    func fetchDailyOccupancy(year: Int, month: Int, totalRooms: Int) async throws -> [(day: Int, count: Int)] {
        if isLocalMode { return local.fetchDailyOccupancy(year: year, month: month, totalRooms: totalRooms) }
        guard let range = monthDateRange(year: year, month: month) else {
            return []
        }
        do {
            let overlapPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "checkInDate < %@", range.end as NSDate),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "actualCheckOut > %@", range.start as NSDate),
                    NSPredicate(format: "expectedCheckOut > %@", range.start as NSDate),
                ])
            ])
            let reservations = try await fetchHydratedReservations(predicate: overlapPredicate)
            mirrorReservationsToLocal(reservations)
            return calculateDailyOccupancy(from: reservations, year: year, month: month, totalRooms: totalRooms)
        } catch {
            guard fallbackToLocal(error) else { throw error }
            return local.fetchDailyOccupancy(year: year, month: month, totalRooms: totalRooms)
        }
    }

    func totalRoomCount() async throws -> Int {
        if isLocalMode { return local.totalRoomCount() }
        do {
            let rooms = try await fetchAllRoomModels()
            local.replaceRooms(rooms)
            return rooms.count
        } catch {
            fallbackToLocal(error)
            return local.totalRoomCount()
        }
    }

    // MARK: - 批量删除（重置用）

    func deleteAllRooms() async throws {
        if isLocalMode {
            local.deleteAllRooms()
            markPendingLocalSync()
            return
        }
        do {
            let records = try await fetchRecords(recordType: Room.recordType, predicate: NSPredicate(value: true))
            let ids = records.map(\.recordID)
            try await deleteRecordsInBatches(ids)
            local.replaceRooms([])
        } catch {
            fallbackToLocal(error)
            local.deleteAllRooms()
            markPendingLocalSync()
        }
    }

    // MARK: - CloudKit 查询辅助

    private func fetchAllRoomModels() async throws -> [Room] {
        let records = try await fetchRecords(
            recordType: Room.recordType,
            predicate: NSPredicate(value: true),
            sortDescriptors: [
                NSSortDescriptor(key: "floor", ascending: true),
                NSSortDescriptor(key: "roomNumber", ascending: true)
            ]
        )
        return records.map(Room.init(from:))
    }

    private func fetchAllGuestModels() async throws -> [Guest] {
        let records = try await fetchRecords(recordType: Guest.recordType, predicate: NSPredicate(value: true))
        let guests = try records.map { try Guest(from: $0) }
        dataProtectionIssue = nil
        return guests
    }

    private func fetchAllReservationModels() async throws -> [Reservation] {
        let records = try await fetchRecords(
            recordType: Reservation.recordType,
            predicate: NSPredicate(value: true),
            sortDescriptors: [NSSortDescriptor(key: "checkInDate", ascending: false)]
        )
        return records.map(Reservation.init(from:))
    }

    private func fetchAllDepositModels() async throws -> [DepositRecord] {
        let records = try await fetchRecords(
            recordType: DepositRecord.recordType,
            predicate: NSPredicate(value: true),
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)]
        )
        return records.map(DepositRecord.init(from:))
    }

    private func fetchHydratedReservations(
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil
    ) async throws -> [Reservation] {
        let records = try await fetchRecords(
            recordType: Reservation.recordType,
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit
        )
        return try await hydrateReservations(records.map(Reservation.init(from:)))
    }

    private func hydrateReservations(_ reservations: [Reservation]) async throws -> [Reservation] {
        guard !reservations.isEmpty else { return [] }

        let guestIDs = Array(Set(reservations.map(\.guestID))).map { CKRecord.ID(recordName: $0) }
        let roomIDs = Array(Set(reservations.map(\.roomID))).map { CKRecord.ID(recordName: $0) }

        async let guestRecordsTask = fetchRecordMap(ids: guestIDs)
        async let roomRecordsTask = fetchRecordMap(ids: roomIDs)

        let guestRecords = try await guestRecordsTask
        let roomRecords = try await roomRecordsTask

        let guestsByID = try guestRecords.values.reduce(into: [String: Guest]()) { partialResult, record in
            partialResult[record.recordID.recordName] = try Guest(from: record)
        }
        dataProtectionIssue = nil
        let roomsByID = roomRecords.values.reduce(into: [String: Room]()) { partialResult, record in
            partialResult[record.recordID.recordName] = Room(from: record)
        }

        return reservations.map { reservation in
            var hydrated = reservation
            hydrated.guest = guestsByID[reservation.guestID]
            hydrated.room = roomsByID[reservation.roomID]
            return hydrated
        }
    }

    private func fetchRecordIfExists(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        let results = try await db.records(for: [recordID], desiredKeys: nil)
        guard let result = results[recordID] else { return nil }
        switch result {
        case .success(let record):
            return record
        case .failure(let error):
            if isUnknownItemError(error) {
                return nil
            }
            throw error
        }
    }

    private func fetchRecordMap(ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        guard !ids.isEmpty else { return [:] }

        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        let batchSize = 200

        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let end = min(start + batchSize, ids.count)
            let batch = Array(ids[start..<end])
            let results = try await db.records(for: batch, desiredKeys: nil)

            for (recordID, result) in results {
                switch result {
                case .success(let record):
                    recordsByID[recordID] = record
                case .failure(let error):
                    if !isUnknownItemError(error) {
                        print("⚠️ 批量读取关联记录失败[\(recordID.recordName)]: \(error.localizedDescription)")
                    }
                }
            }
        }

        return recordsByID
    }

    private func fetchRecords(
        recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil
    ) async throws -> [CKRecord] {
        guard limit != 0 else { return [] }

        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = sortDescriptors

        var allRecords: [CKRecord] = []
        let firstBatchSize = batchSize(for: limit)
        let firstResponse = try await db.records(matching: query, resultsLimit: firstBatchSize)
        appendSuccessfulRecords(from: firstResponse.matchResults, to: &allRecords)

        var remaining = remainingBudget(limit: limit, currentCount: allRecords.count)
        var cursor = firstResponse.queryCursor

        while let nextCursor = cursor, shouldContinueFetching(remaining: remaining) {
            let response = try await db.records(
                continuingMatchFrom: nextCursor,
                desiredKeys: nil,
                resultsLimit: batchSize(for: remaining)
            )
            appendSuccessfulRecords(from: response.matchResults, to: &allRecords)
            remaining = remainingBudget(limit: limit, currentCount: allRecords.count)
            cursor = response.queryCursor
        }

        if let limit {
            return Array(allRecords.prefix(limit))
        }
        return allRecords
    }

    private func saveRecordsInBatches(_ records: [CKRecord], batchSize: Int = 200) async throws {
        guard !records.isEmpty else { return }

        for start in stride(from: 0, to: records.count, by: batchSize) {
            let end = min(start + batchSize, records.count)
            let batch = Array(records[start..<end])
            _ = try await db.modifyRecords(saving: batch, deleting: [], savePolicy: .changedKeys)
        }
    }

    private func deleteRecordsInBatches(_ ids: [CKRecord.ID], batchSize: Int = 200) async throws {
        guard !ids.isEmpty else { return }

        for start in stride(from: 0, to: ids.count, by: batchSize) {
            let end = min(start + batchSize, ids.count)
            let batch = Array(ids[start..<end])
            _ = try await db.modifyRecords(saving: [], deleting: batch)
        }
    }

    private func appendSuccessfulRecords(
        from results: [(CKRecord.ID, Result<CKRecord, Error>)],
        to records: inout [CKRecord]
    ) {
        for (recordID, result) in results {
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                if !isUnknownItemError(error) {
                    print("⚠️ 读取 CloudKit 记录失败[\(recordID.recordName)]: \(error.localizedDescription)")
                }
            }
        }
    }

    private func batchSize(for remaining: Int?) -> Int {
        let target = remaining ?? 200
        return max(1, min(target, 200))
    }

    private func remainingBudget(limit: Int?, currentCount: Int) -> Int? {
        guard let limit else { return nil }
        return max(limit - currentCount, 0)
    }

    private func shouldContinueFetching(remaining: Int?) -> Bool {
        guard let remaining else { return true }
        return remaining > 0
    }

    private func isUnknownItemError(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    // MARK: - 分析辅助

    private func monthDateRange(year: Int, month: Int) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    private func filterReservationsForMonth(_ reservations: [Reservation], year: Int, month: Int) -> [Reservation] {
        let calendar = Calendar.current
        return reservations.filter { reservation in
            guard !reservation.isActive else { return false }
            let checkOut = reservation.actualCheckOut ?? reservation.expectedCheckOut
            return calendar.component(.year, from: checkOut) == year
                && calendar.component(.month, from: checkOut) == month
        }
    }

    private func calculateDailyOccupancy(
        from reservations: [Reservation],
        year: Int,
        month: Int,
        totalRooms: Int
    ) -> [(day: Int, count: Int)] {
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth),
              let lastOfMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) else {
            return []
        }

        let relevantReservations = reservations.filter { reservation in
            let checkOut = reservation.actualCheckOut ?? reservation.expectedCheckOut
            return checkOut > firstOfMonth && reservation.checkInDate < lastOfMonth
        }

        var result: [(day: Int, count: Int)] = []
        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let occupiedRoomIDs = Set(relevantReservations.filter { reservation in
                let stayStart = calendar.startOfDay(for: reservation.checkInDate)
                let checkOut = reservation.actualCheckOut ?? reservation.expectedCheckOut
                var stayEnd = calendar.startOfDay(for: checkOut)
                if stayEnd <= stayStart {
                    stayEnd = calendar.date(byAdding: .day, value: 1, to: stayStart) ?? stayStart
                }
                return stayStart <= dayStart && dayStart < stayEnd
            }.map(\.roomID))
            result.append((day: day, count: min(occupiedRoomIDs.count, totalRooms)))
        }
        return result
    }

    // MARK: - 降级处理

    @discardableResult
    private func fallbackToLocal(_ error: Error) -> Bool {
        if error is EncryptionHelper.EncryptionError {
            recordDataProtectionIssueIfNeeded(error)
            print("⚠️ CloudKit 数据保护校验失败，保持当前模式: \(error.localizedDescription)")
            return false
        }
        if !isLocalMode {
            isLocalMode = true
            startRetryTimer()
            print("⚠️ CloudKit 操作失败，已切换到本地存储: \(error.localizedDescription)")
        }
        return true
    }

    private func recordDataProtectionIssueIfNeeded(_ error: Error) {
        guard error is EncryptionHelper.EncryptionError else { return }
        dataProtectionIssue = error.localizedDescription
    }
}
