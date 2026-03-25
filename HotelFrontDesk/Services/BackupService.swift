import UIKit

/// 数据备份服务 — 自动备份到 iCloud Drive + 手动导出/导入
@MainActor
final class BackupService: ObservableObject {
    static let shared = BackupService()
    private static let lastRestoreTimeKey = "lastICloudRestoreTime"

    @Published var lastBackupTime: Date?
    @Published var lastRestoreTime: Date?
    @Published var isBackingUp = false
    @Published var backupError: String?

    /// Mark data as changed so the next auto-backup cycle will actually run
    private(set) var isDirty = false
    func markDirty() { isDirty = true }

    /// 自动备份间隔（秒）
    private static let autoBackupInterval: TimeInterval = 600 // 10分钟

    private let fileManager = FileManager.default
    private var autoBackupTask: Task<Void, Never>?

    /// 本地数据目录
    private var localDataDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("HotelLocalData")
    }

    /// iCloud Drive 备份目录
    private var iCloudBackupDir: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/HotelBackup")
    }

    private init() {
        loadLastBackupTime()
        loadLastRestoreTime()
        startAutoBackup()
    }

    private var persistentBackupFiles: [String] {
        [
            "rooms.json", "guests.json", "reservations.json", "deposits.json",
            "operation_logs.json", "special_dates.json",
            "ota_bookings.json", "extend_requests.json",
            "staff.json"
        ]
    }

    // MARK: - 自动备份

    func startAutoBackup() {
        autoBackupTask?.cancel()
        autoBackupTask = Task {
            while !Task.isCancelled {
                if isDirty {
                    await performBackup()
                    isDirty = false
                }
                try? await Task.sleep(for: .seconds(Self.autoBackupInterval))
            }
        }
    }

    // MARK: - 执行备份到 iCloud Drive

    func performBackup() async {
        guard let iCloudDir = iCloudBackupDir else {
            // iCloud 不可用，跳过
            return
        }

        isBackingUp = true
        backupError = nil

        do {
            // 确保 iCloud 备份目录存在
            try fileManager.createDirectory(at: iCloudDir, withIntermediateDirectories: true)

            var copiedFiles: [String] = []
            for fileName in persistentBackupFiles {
                let source = localDataDir.appendingPathComponent(fileName)
                let dest = iCloudDir.appendingPathComponent(fileName)

                guard fileManager.fileExists(atPath: source.path) else {
                    if fileManager.fileExists(atPath: dest.path) {
                        try fileManager.removeItem(at: dest)
                    }
                    continue
                }

                // Atomic: copy to temp first, then replace
                let tempDest = iCloudDir.appendingPathComponent(fileName + ".tmp")
                if fileManager.fileExists(atPath: tempDest.path) {
                    try fileManager.removeItem(at: tempDest)
                }
                try fileManager.copyItem(at: source, to: tempDest)
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.moveItem(at: tempDest, to: dest)
                copiedFiles.append(fileName)
            }

            // 同时备份小票照片目录
            let receiptsSource = localDataDir.appendingPathComponent("receipts")
            let receiptsDest = iCloudDir.appendingPathComponent("receipts")
            var receiptsIncluded = false
            if fileManager.fileExists(atPath: receiptsSource.path) {
                if fileManager.fileExists(atPath: receiptsDest.path) {
                    try fileManager.removeItem(at: receiptsDest)
                }
                try fileManager.copyItem(at: receiptsSource, to: receiptsDest)
                receiptsIncluded = true
            } else if fileManager.fileExists(atPath: receiptsDest.path) {
                try fileManager.removeItem(at: receiptsDest)
            }

            // 写入备份元信息
            let meta = BackupMeta(
                timestamp: Date(),
                deviceName: UIDevice.current.name,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                fileCount: copiedFiles.count + (receiptsIncluded ? 1 : 0),
                includedFiles: copiedFiles,
                receiptsIncluded: receiptsIncluded
            )
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: iCloudDir.appendingPathComponent("backup_meta.json"))

            lastBackupTime = Date()
            saveLastBackupTime()
            print("✅ iCloud 备份完成: \(Date())")
        } catch {
            backupError = error.localizedDescription
            print("❌ iCloud 备份失败: \(error)")
        }

        isBackingUp = false
    }

    // MARK: - 从 iCloud Drive 恢复

    func restoreFromICloud() async -> Bool {
        backupError = nil
        guard let iCloudDir = iCloudBackupDir else {
            backupError = "iCloud Drive 不可用"
            return false
        }

        let metaURL = iCloudDir.appendingPathComponent("backup_meta.json")
        guard fileManager.fileExists(atPath: metaURL.path) else {
            backupError = "iCloud 中没有找到备份数据"
            return false
        }

        // Backup local data to temp directory before restoring, for rollback on failure
        let tempBackupDir = fileManager.temporaryDirectory.appendingPathComponent("restore_backup_\(UUID().uuidString)")
        do {
            // 确保本地目录存在
            try fileManager.createDirectory(at: localDataDir, withIntermediateDirectories: true)

            // Backup current local files to temp
            try fileManager.createDirectory(at: tempBackupDir, withIntermediateDirectories: true)
            for fileName in persistentBackupFiles {
                let local = localDataDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: local.path) {
                    try fileManager.copyItem(at: local, to: tempBackupDir.appendingPathComponent(fileName))
                }
            }

            for fileName in persistentBackupFiles {
                let source = iCloudDir.appendingPathComponent(fileName)
                let dest = localDataDir.appendingPathComponent(fileName)

                guard fileManager.fileExists(atPath: source.path) else {
                    if fileManager.fileExists(atPath: dest.path) {
                        try fileManager.removeItem(at: dest)
                    }
                    continue
                }

                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.copyItem(at: source, to: dest)
            }

            // 恢复小票照片
            let receiptsSource = iCloudDir.appendingPathComponent("receipts")
            let receiptsDest = localDataDir.appendingPathComponent("receipts")
            if fileManager.fileExists(atPath: receiptsSource.path) {
                if fileManager.fileExists(atPath: receiptsDest.path) {
                    try fileManager.removeItem(at: receiptsDest)
                }
                try fileManager.copyItem(at: receiptsSource, to: receiptsDest)
            } else if fileManager.fileExists(atPath: receiptsDest.path) {
                try fileManager.removeItem(at: receiptsDest)
            }

            // Clean up temp backup on success
            try? fileManager.removeItem(at: tempBackupDir)

            lastRestoreTime = Date()
            saveLastRestoreTime()
            print("✅ 从 iCloud 恢复完成")
            return true
        } catch {
            // Rollback: restore local files from temp backup
            if fileManager.fileExists(atPath: tempBackupDir.path) {
                if let backupFiles = try? fileManager.contentsOfDirectory(atPath: tempBackupDir.path) {
                    for fileName in backupFiles {
                        let dest = localDataDir.appendingPathComponent(fileName)
                        let backup = tempBackupDir.appendingPathComponent(fileName)
                        try? fileManager.removeItem(at: dest)
                        try? fileManager.moveItem(at: backup, to: dest)
                    }
                }
                try? fileManager.removeItem(at: tempBackupDir)
            }
            backupError = "恢复失败: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 手动导出（生成 zip/json 通过分享菜单）

    func exportBackup() throws -> URL {
        let tempDir = fileManager.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("HotelBackup_\(formatDate(Date()))")
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        var copiedFiles: [String] = []
        for fileName in persistentBackupFiles {
            let source = localDataDir.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: exportDir.appendingPathComponent(fileName))
            copiedFiles.append(fileName)
        }

        let receiptsSource = localDataDir.appendingPathComponent("receipts")
        let receiptsDest = exportDir.appendingPathComponent("receipts")
        let receiptsIncluded = fileManager.fileExists(atPath: receiptsSource.path)
        if receiptsIncluded {
            try fileManager.copyItem(at: receiptsSource, to: receiptsDest)
        }

        let readme = """
        酒店前台数据恢复说明

        1. 请在目标设备登录与原设备相同的 Apple ID。
        2. 在系统设置中开启 iCloud Drive 与“密码与钥匙串”。
        3. 安装应用后，以管理员身份进入“设置 > 备份与恢复”。
        4. 如需从 iCloud 恢复，请先确认最近备份时间，再执行恢复。
        5. 如果提示凭据或加密密钥异常，请优先检查 Apple ID、iCloud Drive 和钥匙串是否同步完成。
        """
        try readme.write(to: exportDir.appendingPathComponent("README_恢复说明.txt"), atomically: true, encoding: .utf8)

        // 写元信息
        let meta = BackupMeta(
            timestamp: Date(),
            deviceName: UIDevice.current.name,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            fileCount: copiedFiles.count + 1 + (receiptsIncluded ? 1 : 0),
            includedFiles: copiedFiles,
            receiptsIncluded: receiptsIncluded
        )
        try JSONEncoder().encode(meta).write(to: exportDir.appendingPathComponent("backup_meta.json"))

        return exportDir
    }

    func exportDataPackage() async throws -> URL {
        let rooms = try await CloudKitService.shared.fetchAllRooms()
        let guests = try await CloudKitService.shared.fetchAllGuests()
        let reservations = try await CloudKitService.shared.fetchAllReservations()
        let deposits = try await CloudKitService.shared.fetchAllDeposits()
        let otaBookings = OTABookingService.shared.bookings.sorted { $0.checkInDate > $1.checkInDate }

        let exportDir = fileManager.temporaryDirectory.appendingPathComponent("HotelDataExport_\(formatDate(Date()))")
        if fileManager.fileExists(atPath: exportDir.path) {
            try fileManager.removeItem(at: exportDir)
        }
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let bundle = buildAIAnalysisBundle(
            rooms: rooms,
            guests: guests,
            reservations: reservations,
            deposits: deposits,
            otaBookings: otaBookings
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle).write(
            to: exportDir.appendingPathComponent("hotel_data_bundle.json"),
            options: .atomic
        )

        try writeDataPackageReadme(to: exportDir)
        try writeCSVFiles(for: bundle, to: exportDir)

        return exportDir
    }

    // MARK: - 查询 iCloud 备份信息

    var iCloudAvailable: Bool {
        iCloudBackupDir != nil
    }

    func fetchICloudBackupMeta() -> BackupMeta? {
        guard let dir = iCloudBackupDir else { return nil }
        let metaURL = dir.appendingPathComponent("backup_meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(BackupMeta.self, from: data) else { return nil }
        return meta
    }

    func backupHealthItems() -> [BackupHealthItem] {
        let recentThreshold: TimeInterval = 24 * 60 * 60
        var items: [BackupHealthItem] = [
            BackupHealthItem(
                title: "iCloud Drive",
                detail: iCloudAvailable ? "已连接，可执行自动备份和云端恢复" : "未连接，正式上线前请先登录 iCloud 并开启 Drive",
                state: iCloudAvailable ? .good : .error
            )
        ]

        if let lastBackupTime {
            let isRecent = abs(lastBackupTime.timeIntervalSinceNow) <= recentThreshold
            items.append(
                BackupHealthItem(
                    title: "最近备份",
                    detail: "\(formatDisplayDate(lastBackupTime))\(isRecent ? "，状态正常" : "，已超过24小时，建议立即补备份")",
                    state: isRecent ? .good : .warning
                )
            )
        } else {
            items.append(
                BackupHealthItem(
                    title: "最近备份",
                    detail: "还没有完成过有效备份，正式上线前建议至少手动备份一次",
                    state: .warning
                )
            )
        }

        items.append(
            BackupHealthItem(
                title: "员工账号与密钥",
                detail: "备份已包含 staff.json；员工密码哈希和敏感数据密钥依赖同一 Apple ID 下的 iCloud 钥匙串同步恢复",
                state: .info
            )
        )

        items.append(
            BackupHealthItem(
                title: "恢复前提",
                detail: "新设备恢复前，请确认使用同一 Apple ID，并开启 iCloud Drive 与“密码与钥匙串”",
                state: .info
            )
        )

        if let lastRestoreTime {
            items.append(
                BackupHealthItem(
                    title: "上次恢复",
                    detail: formatDisplayDate(lastRestoreTime),
                    state: .info
                )
            )
        }

        return items
    }

    // MARK: - AI 分析导出

    private func buildAIAnalysisBundle(
        rooms: [Room],
        guests: [Guest],
        reservations: [Reservation],
        deposits: [DepositRecord],
        otaBookings: [OTABooking]
    ) -> AIAnalysisBundle {
        let now = Date()
        let guestMap = Dictionary(uniqueKeysWithValues: guests.map { ($0.id, $0) })
        let roomMap = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        let depositsByReservation = Dictionary(grouping: deposits, by: \.reservationID)
        let sourceMatches = matchReservationSources(reservations: reservations, otaBookings: otaBookings)

        let reservationRecords = reservations
            .sorted { $0.checkInDate > $1.checkInDate }
            .map { reservation -> AIReservationRecord in
                let guest = reservation.guest ?? guestMap[reservation.guestID]
                let room = reservation.room ?? roomMap[reservation.roomID]
                let depositRecords = depositsByReservation[reservation.id] ?? []
                let depositSummary = DepositSummary(records: depositRecords)
                let actualNights = realizedNights(for: reservation, referenceDate: now)
                let projectedNights = plannedNights(for: reservation)
                let match = sourceMatches[reservation.id] ?? defaultSourceMatch()

                return AIReservationRecord(
                    reservationId: reservation.id,
                    status: reservationStatus(for: reservation, referenceDate: now),
                    sourceDisplayName: match.sourceDisplayName,
                    sourceCategory: match.sourceCategory,
                    sourceMatchScore: match.matchScore,
                    sourceMatchEvidence: match.matchEvidence,
                    matchedOtaBookingId: match.bookingID,
                    platformOrderId: match.platformOrderID,
                    guestId: guest?.id ?? reservation.guestID,
                    guestName: guest?.name ?? reservation.guest?.name ?? "未知客人",
                    guestPhoneMasked: maskPhone(guest?.phone ?? reservation.guest?.phone ?? ""),
                    guestIdType: guest?.idType.rawValue ?? reservation.guest?.idType.rawValue ?? "",
                    guestIdNumberMasked: maskIdentityNumber(guest?.idNumber ?? reservation.guest?.idNumber ?? ""),
                    roomId: room?.id ?? reservation.roomID,
                    roomNumber: room?.roomNumber ?? reservation.room?.roomNumber ?? "",
                    roomType: room?.roomType.rawValue ?? reservation.room?.roomType.rawValue ?? "",
                    checkInAt: reservation.checkInDate,
                    expectedCheckOutAt: reservation.expectedCheckOut,
                    actualCheckOutAt: reservation.actualCheckOut,
                    numberOfGuests: reservation.numberOfGuests,
                    dailyRate: reservation.dailyRate,
                    actualNights: actualNights,
                    projectedNights: projectedNights,
                    actualRevenue: Double(actualNights) * reservation.dailyRate,
                    projectedRevenue: Double(projectedNights) * reservation.dailyRate,
                    depositCollected: depositSummary.totalCollected,
                    depositRefunded: depositSummary.totalRefunded,
                    depositBalance: depositSummary.balance
                )
            }

        let allGuests = mergedGuests(primary: guests, reservations: reservations)
        let guestRecords = allGuests
            .map { guest -> AIGuestRecord in
                let guestReservations = reservationRecords.filter { $0.guestId == guest.id }
                return AIGuestRecord(
                    guestId: guest.id,
                    name: guest.name,
                    idType: guest.idType.rawValue,
                    idNumberMasked: maskIdentityNumber(guest.idNumber),
                    phoneMasked: maskPhone(guest.phone),
                    notes: guest.notes,
                    reservationCount: guestReservations.count,
                    activeReservationCount: guestReservations.filter { $0.status != "已退房" }.count,
                    actualNights: guestReservations.reduce(0) { $0 + $1.actualNights },
                    projectedNights: guestReservations.reduce(0) { $0 + $1.projectedNights },
                    actualRevenue: guestReservations.reduce(0) { $0 + $1.actualRevenue },
                    projectedRevenue: guestReservations.reduce(0) { $0 + $1.projectedRevenue },
                    lastCheckInAt: guestReservations.map(\.checkInAt).max(),
                    lastCheckOutAt: guestReservations.compactMap(\.actualCheckOutAt).max(),
                    sources: Array(Set(guestReservations.map(\.sourceDisplayName))).sorted()
                )
            }
            .sorted {
                if $0.actualRevenue == $1.actualRevenue {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.actualRevenue > $1.actualRevenue
            }

        let roomRecords = rooms.map { room -> AIRoomRecord in
            let roomReservations = reservationRecords.filter { $0.roomId == room.id }
            return AIRoomRecord(
                roomId: room.id,
                roomNumber: room.roomNumber,
                floor: room.floor,
                roomType: room.roomType.rawValue,
                orientation: room.orientation.rawValue,
                currentStatus: room.status.rawValue,
                currentStatusLabel: room.status.displayName,
                weekdayPrice: room.pricePerNight,
                weekendPrice: room.weekendPrice,
                monthlyCost: room.monthlyCost,
                notes: room.notes,
                reservationCount: roomReservations.count,
                activeReservationCount: roomReservations.filter { $0.status != "已退房" }.count,
                actualNights: roomReservations.reduce(0) { $0 + $1.actualNights },
                projectedNights: roomReservations.reduce(0) { $0 + $1.projectedNights },
                actualRevenue: roomReservations.reduce(0) { $0 + $1.actualRevenue },
                projectedRevenue: roomReservations.reduce(0) { $0 + $1.projectedRevenue },
                lastCheckInAt: roomReservations.map(\.checkInAt).max(),
                lastCheckOutAt: roomReservations.compactMap(\.actualCheckOutAt).max()
            )
        }

        let otaRecords = otaBookings.map { booking in
            AIOTABookingRecord(
                bookingId: booking.id,
                platform: booking.platform.rawValue,
                platformDisplayName: booking.platformDisplayName,
                platformOrderId: booking.platformOrderID,
                status: booking.status.rawValue,
                guestName: booking.guestName,
                guestPhoneMasked: maskPhone(booking.guestPhone),
                roomType: booking.roomType.rawValue,
                assignedRoomId: booking.assignedRoomID,
                assignedRoomNumber: booking.assignedRoomNumber,
                checkInAt: booking.checkInDate,
                checkOutAt: booking.checkOutDate,
                nights: booking.nights,
                nightlyPrice: booking.price,
                totalPrice: booking.totalPrice,
                notes: booking.notes,
                createdAt: booking.createdAt,
                createdBy: booking.createdBy
            )
        }

        let sourceSummaries = buildSourceSummaries(reservations: reservationRecords, otaBookings: otaRecords)
        let depositSummary = DepositSummary(records: deposits)
        let actualRevenueTotal = reservationRecords.reduce(0) { $0 + $1.actualRevenue }
        let projectedRevenueTotal = reservationRecords.reduce(0) { $0 + $1.projectedRevenue }
        let actualNightsTotal = reservationRecords.reduce(0) { $0 + $1.actualNights }
        let projectedNightsTotal = reservationRecords.reduce(0) { $0 + $1.projectedNights }
        let otaQuotedRevenueTotal = otaRecords
            .filter { $0.status != BookingStatus.cancelled.rawValue && $0.status != BookingStatus.noShow.rawValue }
            .reduce(0) { $0 + $1.totalPrice }
        let roomStatusBreakdown = Dictionary(grouping: rooms, by: \.status.displayName)
            .mapValues(\.count)

        return AIAnalysisBundle(
            metadata: AIExportMetadata(
                exportedAt: now,
                exportMode: CloudKitService.shared.isLocalMode ? "local" : "cloud",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                counts: AIExportCounts(
                    rooms: roomRecords.count,
                    guests: guestRecords.count,
                    reservations: reservationRecords.count,
                    deposits: deposits.count,
                    otaBookings: otaRecords.count,
                    sources: sourceSummaries.count
                )
            ),
            summary: AIExportSummary(
                totalRooms: roomRecords.count,
                totalGuests: guestRecords.count,
                totalReservations: reservationRecords.count,
                activeReservations: reservationRecords.filter { $0.status != "已退房" }.count,
                completedReservations: reservationRecords.filter { $0.status == "已退房" }.count,
                actualNights: actualNightsTotal,
                projectedNights: projectedNightsTotal,
                actualRevenue: actualRevenueTotal,
                projectedRevenue: projectedRevenueTotal,
                averageDailyRate: projectedNightsTotal == 0 ? 0 : projectedRevenueTotal / Double(projectedNightsTotal),
                otaQuotedRevenue: otaQuotedRevenueTotal,
                depositCollected: depositSummary.totalCollected,
                depositRefunded: depositSummary.totalRefunded,
                depositBalance: depositSummary.balance,
                roomStatusBreakdown: roomStatusBreakdown
            ),
            rooms: roomRecords.sorted {
                if $0.floor == $1.floor {
                    return $0.roomNumber.localizedStandardCompare($1.roomNumber) == .orderedAscending
                }
                return $0.floor < $1.floor
            },
            guests: guestRecords,
            reservations: reservationRecords,
            deposits: deposits
                .sorted { $0.timestamp > $1.timestamp }
                .map {
                    AIDepositRecord(
                        depositId: $0.id,
                        reservationId: $0.reservationID,
                        type: $0.type.rawValue,
                        amount: $0.amount,
                        paymentMethod: $0.paymentMethod.rawValue,
                        timestamp: $0.timestamp,
                        operatorName: $0.operatorName,
                        notes: $0.notes
                    )
                },
            otaBookings: otaRecords,
            sourceRevenueSummary: sourceSummaries
        )
    }

    private func mergedGuests(primary: [Guest], reservations: [Reservation]) -> [Guest] {
        var result = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for reservation in reservations {
            if let guest = reservation.guest {
                result[guest.id] = guest
            }
        }
        return Array(result.values)
    }

    private func buildSourceSummaries(
        reservations: [AIReservationRecord],
        otaBookings: [AIOTABookingRecord]
    ) -> [AISourceRevenueSummary] {
        var summaries: [String: AISourceRevenueAccumulator] = [:]

        for reservation in reservations {
            var summary = summaries[reservation.sourceDisplayName] ?? AISourceRevenueAccumulator(
                sourceDisplayName: reservation.sourceDisplayName,
                sourceCategory: reservation.sourceCategory
            )
            summary.reservationCount += 1
            if reservation.status == "已退房" {
                summary.completedReservationCount += 1
            } else {
                summary.activeReservationCount += 1
            }
            summary.actualNights += reservation.actualNights
            summary.projectedNights += reservation.projectedNights
            summary.actualRevenue += reservation.actualRevenue
            summary.projectedRevenue += reservation.projectedRevenue
            summaries[reservation.sourceDisplayName] = summary
        }

        for booking in otaBookings {
            var summary = summaries[booking.platformDisplayName] ?? AISourceRevenueAccumulator(
                sourceDisplayName: booking.platformDisplayName,
                sourceCategory: booking.platform == OTAPlatform.direct.rawValue ? "direct" : "ota"
            )
            summary.otaBookingCount += 1
            summary.otaQuotedRevenue += booking.totalPrice
            switch booking.status {
            case BookingStatus.confirmed.rawValue: summary.confirmedOtaBookingCount += 1
            case BookingStatus.checkedIn.rawValue: summary.checkedInOtaBookingCount += 1
            case BookingStatus.cancelled.rawValue: summary.cancelledOtaBookingCount += 1
            case BookingStatus.noShow.rawValue: summary.noShowOtaBookingCount += 1
            default: break
            }
            summaries[booking.platformDisplayName] = summary
        }

        return summaries.values
            .map {
                AISourceRevenueSummary(
                    sourceDisplayName: $0.sourceDisplayName,
                    sourceCategory: $0.sourceCategory,
                    reservationCount: $0.reservationCount,
                    activeReservationCount: $0.activeReservationCount,
                    completedReservationCount: $0.completedReservationCount,
                    actualNights: $0.actualNights,
                    projectedNights: $0.projectedNights,
                    actualRevenue: $0.actualRevenue,
                    projectedRevenue: $0.projectedRevenue,
                    otaBookingCount: $0.otaBookingCount,
                    confirmedOtaBookingCount: $0.confirmedOtaBookingCount,
                    checkedInOtaBookingCount: $0.checkedInOtaBookingCount,
                    cancelledOtaBookingCount: $0.cancelledOtaBookingCount,
                    noShowOtaBookingCount: $0.noShowOtaBookingCount,
                    otaQuotedRevenue: $0.otaQuotedRevenue
                )
            }
            .sorted {
                if $0.actualRevenue == $1.actualRevenue {
                    return $0.sourceDisplayName.localizedStandardCompare($1.sourceDisplayName) == .orderedAscending
                }
                return $0.actualRevenue > $1.actualRevenue
            }
    }

    private func matchReservationSources(
        reservations: [Reservation],
        otaBookings: [OTABooking]
    ) -> [String: AIReservationSourceMatch] {
        let candidateBookings = otaBookings.filter {
            $0.status != .cancelled && $0.status != .noShow
        }
        var remainingBookings = candidateBookings
        var result: [String: AIReservationSourceMatch] = [:]

        for reservation in reservations.sorted(by: { $0.checkInDate < $1.checkInDate }) {
            let reservationGuest = reservation.guest
            let reservationRoom = reservation.room
            let guestName = normalizedName(reservationGuest?.name ?? "")
            let guestPhone = digitsOnly(reservationGuest?.phone ?? "")
            let plannedStayNights = plannedNights(for: reservation)

            var bestIndex: Int?
            var bestScore = 0
            var bestEvidence: [String] = []

            for (index, booking) in remainingBookings.enumerated() {
                var score = 0
                var evidence: [String] = []

                if let assignedRoomID = booking.assignedRoomID, assignedRoomID == reservation.roomID {
                    score += 70
                    evidence.append("room_id")
                }
                if let assignedRoomNumber = booking.assignedRoomNumber,
                   let roomNumber = reservationRoom?.roomNumber,
                   assignedRoomNumber == roomNumber {
                    score += 55
                    evidence.append("room_number")
                }

                let bookingName = normalizedName(booking.guestName)
                if !guestName.isEmpty, bookingName == guestName {
                    score += 30
                    evidence.append("guest_name")
                }

                let bookingPhone = digitsOnly(booking.guestPhone)
                if !guestPhone.isEmpty, !bookingPhone.isEmpty {
                    if bookingPhone == guestPhone {
                        score += 28
                        evidence.append("guest_phone")
                    } else if bookingPhone.count >= 4,
                              guestPhone.count >= 4,
                              bookingPhone.suffix(4) == guestPhone.suffix(4) {
                        score += 12
                        evidence.append("guest_phone_last4")
                    }
                }

                let dayGap = dayDistance(booking.checkInDate, reservation.checkInDate)
                if dayGap == 0 {
                    score += 24
                    evidence.append("check_in_date")
                } else if dayGap == 1 {
                    score += 8
                    evidence.append("nearby_check_in_date")
                }

                if booking.nights == plannedStayNights {
                    score += 12
                    evidence.append("nights")
                }

                if let roomType = reservationRoom?.roomType, booking.roomType == roomType {
                    score += 8
                    evidence.append("room_type")
                }

                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                    bestEvidence = evidence
                }
            }

            if let bestIndex, bestScore >= 40 {
                let matchedBooking = remainingBookings.remove(at: bestIndex)
                result[reservation.id] = AIReservationSourceMatch(
                    sourceDisplayName: matchedBooking.platformDisplayName,
                    sourceCategory: matchedBooking.platform == .direct ? "direct" : "ota",
                    bookingID: matchedBooking.id,
                    platformOrderID: matchedBooking.platformOrderID.nilIfBlank,
                    matchScore: bestScore,
                    matchEvidence: bestEvidence.joined(separator: ",")
                )
            } else {
                result[reservation.id] = defaultSourceMatch()
            }
        }

        return result
    }

    private func defaultSourceMatch() -> AIReservationSourceMatch {
        AIReservationSourceMatch(
            sourceDisplayName: "前台入住",
            sourceCategory: "frontdesk",
            bookingID: nil,
            platformOrderID: nil,
            matchScore: 0,
            matchEvidence: "default_frontdesk"
        )
    }

    private func reservationStatus(for reservation: Reservation, referenceDate: Date) -> String {
        if reservation.isActive {
            return reservation.checkInDate > referenceDate ? "待入住" : "在住"
        }
        return "已退房"
    }

    private func realizedNights(for reservation: Reservation, referenceDate: Date) -> Int {
        if reservation.checkInDate > referenceDate, reservation.actualCheckOut == nil {
            return 0
        }

        let endDate = reservation.actualCheckOut ?? referenceDate
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: reservation.checkInDate),
            to: Calendar.current.startOfDay(for: endDate)
        ).day ?? 0

        if reservation.actualCheckOut != nil || reservation.checkInDate <= referenceDate {
            return max(days, 1)
        }
        return 0
    }

    private func plannedNights(for reservation: Reservation) -> Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: reservation.checkInDate),
            to: Calendar.current.startOfDay(for: reservation.actualCheckOut ?? reservation.expectedCheckOut)
        ).day ?? 0
        return max(days, 1)
    }

    private func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    private func digitsOnly(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private func dayDistance(_ lhs: Date, _ rhs: Date) -> Int {
        abs(Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lhs),
            to: Calendar.current.startOfDay(for: rhs)
        ).day ?? .max)
    }

    private func maskPhone(_ value: String) -> String {
        let digits = digitsOnly(value)
        guard digits.count >= 7 else { return value }
        let prefix = digits.prefix(3)
        let suffix = digits.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    private func maskIdentityNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "" : "\(trimmed.prefix(1))***\(trimmed.suffix(1))" }
        return "\(trimmed.prefix(3))********\(trimmed.suffix(4))"
    }

    private func writeDataPackageReadme(to exportDir: URL) throws {
        let content = """
        酒店前台数据包说明

        1. hotel_data_bundle.json
           单个 JSON 文件，包含房间、客人、入住、押金、OTA 订单、来源归因和收益汇总。
        2. reservations_flat.csv
           扁平化入住明细，适合直接上传给 ChatGPT、Gemini、Excel 或表格工具。
        3. rooms_overview.csv / guests_overview.csv / ota_bookings.csv / source_revenue_summary.csv / deposits.csv
           分主题拆开的 CSV，适合单独做房间、客人、来源和押金分析。
        4. 为了降低隐私风险，手机号和证件号已经做脱敏处理；客人姓名会保留，方便识别回头客和订单归因。
        5. 入住来源是根据 OTA 订单、房号、入住日期、姓名和手机号做匹配；无法匹配时默认标记为“前台入住”。
        """
        try content.write(
            to: exportDir.appendingPathComponent("README_数据说明.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeCSVFiles(for bundle: AIAnalysisBundle, to exportDir: URL) throws {
        try writeCSV(
            fileName: "reservations_flat.csv",
            headers: [
                "reservation_id", "status", "source_display_name", "source_category",
                "matched_ota_booking_id", "platform_order_id", "guest_id", "guest_name",
                "guest_phone_masked", "room_id", "room_number", "room_type",
                "check_in_at", "expected_check_out_at", "actual_check_out_at",
                "number_of_guests", "daily_rate", "actual_nights", "projected_nights",
                "actual_revenue", "projected_revenue", "deposit_collected",
                "deposit_refunded", "deposit_balance", "source_match_score", "source_match_evidence"
            ],
            rows: bundle.reservations.map {
                [
                    $0.reservationId,
                    $0.status,
                    $0.sourceDisplayName,
                    $0.sourceCategory,
                    $0.matchedOtaBookingId ?? "",
                    $0.platformOrderId ?? "",
                    $0.guestId,
                    $0.guestName,
                    $0.guestPhoneMasked,
                    $0.roomId,
                    $0.roomNumber,
                    $0.roomType,
                    isoString($0.checkInAt),
                    isoString($0.expectedCheckOutAt),
                    isoString($0.actualCheckOutAt),
                    String($0.numberOfGuests),
                    formatNumber($0.dailyRate),
                    String($0.actualNights),
                    String($0.projectedNights),
                    formatNumber($0.actualRevenue),
                    formatNumber($0.projectedRevenue),
                    formatNumber($0.depositCollected),
                    formatNumber($0.depositRefunded),
                    formatNumber($0.depositBalance),
                    String($0.sourceMatchScore),
                    $0.sourceMatchEvidence
                ]
            },
            to: exportDir
        )

        try writeCSV(
            fileName: "rooms_overview.csv",
            headers: [
                "room_id", "room_number", "floor", "room_type", "orientation",
                "current_status", "current_status_label", "weekday_price", "weekend_price",
                "monthly_cost", "reservation_count", "active_reservation_count",
                "actual_nights", "projected_nights", "actual_revenue", "projected_revenue",
                "last_check_in_at", "last_check_out_at", "notes"
            ],
            rows: bundle.rooms.map {
                [
                    $0.roomId,
                    $0.roomNumber,
                    String($0.floor),
                    $0.roomType,
                    $0.orientation,
                    $0.currentStatus,
                    $0.currentStatusLabel,
                    formatNumber($0.weekdayPrice),
                    formatNumber($0.weekendPrice),
                    formatNumber($0.monthlyCost),
                    String($0.reservationCount),
                    String($0.activeReservationCount),
                    String($0.actualNights),
                    String($0.projectedNights),
                    formatNumber($0.actualRevenue),
                    formatNumber($0.projectedRevenue),
                    isoString($0.lastCheckInAt),
                    isoString($0.lastCheckOutAt),
                    $0.notes ?? ""
                ]
            },
            to: exportDir
        )

        try writeCSV(
            fileName: "guests_overview.csv",
            headers: [
                "guest_id", "name", "id_type", "id_number_masked", "phone_masked",
                "reservation_count", "active_reservation_count", "actual_nights",
                "projected_nights", "actual_revenue", "projected_revenue",
                "last_check_in_at", "last_check_out_at", "sources", "notes"
            ],
            rows: bundle.guests.map {
                [
                    $0.guestId,
                    $0.name,
                    $0.idType,
                    $0.idNumberMasked,
                    $0.phoneMasked,
                    String($0.reservationCount),
                    String($0.activeReservationCount),
                    String($0.actualNights),
                    String($0.projectedNights),
                    formatNumber($0.actualRevenue),
                    formatNumber($0.projectedRevenue),
                    isoString($0.lastCheckInAt),
                    isoString($0.lastCheckOutAt),
                    $0.sources.joined(separator: "|"),
                    $0.notes ?? ""
                ]
            },
            to: exportDir
        )

        try writeCSV(
            fileName: "ota_bookings.csv",
            headers: [
                "booking_id", "platform", "platform_display_name", "platform_order_id",
                "status", "guest_name", "guest_phone_masked", "room_type",
                "assigned_room_id", "assigned_room_number", "check_in_at", "check_out_at",
                "nights", "nightly_price", "total_price", "created_at", "created_by", "notes"
            ],
            rows: bundle.otaBookings.map {
                [
                    $0.bookingId,
                    $0.platform,
                    $0.platformDisplayName,
                    $0.platformOrderId,
                    $0.status,
                    $0.guestName,
                    $0.guestPhoneMasked,
                    $0.roomType,
                    $0.assignedRoomId ?? "",
                    $0.assignedRoomNumber ?? "",
                    isoString($0.checkInAt),
                    isoString($0.checkOutAt),
                    String($0.nights),
                    formatNumber($0.nightlyPrice),
                    formatNumber($0.totalPrice),
                    isoString($0.createdAt),
                    $0.createdBy,
                    $0.notes ?? ""
                ]
            },
            to: exportDir
        )

        try writeCSV(
            fileName: "source_revenue_summary.csv",
            headers: [
                "source_display_name", "source_category", "reservation_count",
                "active_reservation_count", "completed_reservation_count", "actual_nights",
                "projected_nights", "actual_revenue", "projected_revenue",
                "ota_booking_count", "confirmed_ota_booking_count", "checked_in_ota_booking_count",
                "cancelled_ota_booking_count", "no_show_ota_booking_count", "ota_quoted_revenue"
            ],
            rows: bundle.sourceRevenueSummary.map {
                [
                    $0.sourceDisplayName,
                    $0.sourceCategory,
                    String($0.reservationCount),
                    String($0.activeReservationCount),
                    String($0.completedReservationCount),
                    String($0.actualNights),
                    String($0.projectedNights),
                    formatNumber($0.actualRevenue),
                    formatNumber($0.projectedRevenue),
                    String($0.otaBookingCount),
                    String($0.confirmedOtaBookingCount),
                    String($0.checkedInOtaBookingCount),
                    String($0.cancelledOtaBookingCount),
                    String($0.noShowOtaBookingCount),
                    formatNumber($0.otaQuotedRevenue)
                ]
            },
            to: exportDir
        )

        try writeCSV(
            fileName: "deposits.csv",
            headers: [
                "deposit_id", "reservation_id", "type", "amount",
                "payment_method", "timestamp", "operator_name", "notes"
            ],
            rows: bundle.deposits.map {
                [
                    $0.depositId,
                    $0.reservationId,
                    $0.type,
                    formatNumber($0.amount),
                    $0.paymentMethod,
                    isoString($0.timestamp),
                    $0.operatorName ?? "",
                    $0.notes ?? ""
                ]
            },
            to: exportDir
        )
    }

    private func writeCSV(
        fileName: String,
        headers: [String],
        rows: [[String]],
        to directory: URL
    ) throws {
        var lines = [headers.map(csvEscaped).joined(separator: ",")]
        lines.append(contentsOf: rows.map { $0.map(csvEscaped).joined(separator: ",") })
        let content = lines.joined(separator: "\n")
        try content.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func isoString(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func formatNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - 辅助

    private func saveLastBackupTime() {
        UserDefaults.standard.set(lastBackupTime?.timeIntervalSince1970, forKey: "lastICloudBackupTime")
    }

    private func loadLastBackupTime() {
        let ts = UserDefaults.standard.double(forKey: "lastICloudBackupTime")
        lastBackupTime = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private func saveLastRestoreTime() {
        UserDefaults.standard.set(lastRestoreTime?.timeIntervalSince1970, forKey: Self.lastRestoreTimeKey)
    }

    private func loadLastRestoreTime() {
        let ts = UserDefaults.standard.double(forKey: Self.lastRestoreTimeKey)
        lastRestoreTime = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }

    private func formatDisplayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter.string(from: date)
    }
}

private struct AIAnalysisBundle: Codable {
    let metadata: AIExportMetadata
    let summary: AIExportSummary
    let rooms: [AIRoomRecord]
    let guests: [AIGuestRecord]
    let reservations: [AIReservationRecord]
    let deposits: [AIDepositRecord]
    let otaBookings: [AIOTABookingRecord]
    let sourceRevenueSummary: [AISourceRevenueSummary]
}

private struct AIExportMetadata: Codable {
    let exportedAt: Date
    let exportMode: String
    let appVersion: String
    let counts: AIExportCounts
}

private struct AIExportCounts: Codable {
    let rooms: Int
    let guests: Int
    let reservations: Int
    let deposits: Int
    let otaBookings: Int
    let sources: Int
}

private struct AIExportSummary: Codable {
    let totalRooms: Int
    let totalGuests: Int
    let totalReservations: Int
    let activeReservations: Int
    let completedReservations: Int
    let actualNights: Int
    let projectedNights: Int
    let actualRevenue: Double
    let projectedRevenue: Double
    let averageDailyRate: Double
    let otaQuotedRevenue: Double
    let depositCollected: Double
    let depositRefunded: Double
    let depositBalance: Double
    let roomStatusBreakdown: [String: Int]
}

private struct AIRoomRecord: Codable {
    let roomId: String
    let roomNumber: String
    let floor: Int
    let roomType: String
    let orientation: String
    let currentStatus: String
    let currentStatusLabel: String
    let weekdayPrice: Double
    let weekendPrice: Double
    let monthlyCost: Double
    let notes: String?
    let reservationCount: Int
    let activeReservationCount: Int
    let actualNights: Int
    let projectedNights: Int
    let actualRevenue: Double
    let projectedRevenue: Double
    let lastCheckInAt: Date?
    let lastCheckOutAt: Date?
}

private struct AIGuestRecord: Codable {
    let guestId: String
    let name: String
    let idType: String
    let idNumberMasked: String
    let phoneMasked: String
    let notes: String?
    let reservationCount: Int
    let activeReservationCount: Int
    let actualNights: Int
    let projectedNights: Int
    let actualRevenue: Double
    let projectedRevenue: Double
    let lastCheckInAt: Date?
    let lastCheckOutAt: Date?
    let sources: [String]
}

private struct AIReservationRecord: Codable {
    let reservationId: String
    let status: String
    let sourceDisplayName: String
    let sourceCategory: String
    let sourceMatchScore: Int
    let sourceMatchEvidence: String
    let matchedOtaBookingId: String?
    let platformOrderId: String?
    let guestId: String
    let guestName: String
    let guestPhoneMasked: String
    let guestIdType: String
    let guestIdNumberMasked: String
    let roomId: String
    let roomNumber: String
    let roomType: String
    let checkInAt: Date
    let expectedCheckOutAt: Date
    let actualCheckOutAt: Date?
    let numberOfGuests: Int
    let dailyRate: Double
    let actualNights: Int
    let projectedNights: Int
    let actualRevenue: Double
    let projectedRevenue: Double
    let depositCollected: Double
    let depositRefunded: Double
    let depositBalance: Double
}

private struct AIDepositRecord: Codable {
    let depositId: String
    let reservationId: String
    let type: String
    let amount: Double
    let paymentMethod: String
    let timestamp: Date
    let operatorName: String?
    let notes: String?
}

private struct AIOTABookingRecord: Codable {
    let bookingId: String
    let platform: String
    let platformDisplayName: String
    let platformOrderId: String
    let status: String
    let guestName: String
    let guestPhoneMasked: String
    let roomType: String
    let assignedRoomId: String?
    let assignedRoomNumber: String?
    let checkInAt: Date
    let checkOutAt: Date
    let nights: Int
    let nightlyPrice: Double
    let totalPrice: Double
    let notes: String?
    let createdAt: Date
    let createdBy: String
}

private struct AISourceRevenueSummary: Codable {
    let sourceDisplayName: String
    let sourceCategory: String
    let reservationCount: Int
    let activeReservationCount: Int
    let completedReservationCount: Int
    let actualNights: Int
    let projectedNights: Int
    let actualRevenue: Double
    let projectedRevenue: Double
    let otaBookingCount: Int
    let confirmedOtaBookingCount: Int
    let checkedInOtaBookingCount: Int
    let cancelledOtaBookingCount: Int
    let noShowOtaBookingCount: Int
    let otaQuotedRevenue: Double
}

private struct AIReservationSourceMatch {
    let sourceDisplayName: String
    let sourceCategory: String
    let bookingID: String?
    let platformOrderID: String?
    let matchScore: Int
    let matchEvidence: String
}

private struct AISourceRevenueAccumulator {
    let sourceDisplayName: String
    let sourceCategory: String
    var reservationCount = 0
    var activeReservationCount = 0
    var completedReservationCount = 0
    var actualNights = 0
    var projectedNights = 0
    var actualRevenue = 0.0
    var projectedRevenue = 0.0
    var otaBookingCount = 0
    var confirmedOtaBookingCount = 0
    var checkedInOtaBookingCount = 0
    var cancelledOtaBookingCount = 0
    var noShowOtaBookingCount = 0
    var otaQuotedRevenue = 0.0
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 备份元信息
struct BackupMeta: Codable {
    let timestamp: Date
    let deviceName: String
    let appVersion: String
    let fileCount: Int
    let includedFiles: [String]?
    let receiptsIncluded: Bool?
}

struct BackupHealthItem: Identifiable {
    enum State {
        case good
        case warning
        case error
        case info

        var icon: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: UIColor {
            switch self {
            case .good: return .systemGreen
            case .warning: return .systemOrange
            case .error: return .systemRed
            case .info: return .systemBlue
            }
        }
    }

    var id: String { title }
    let title: String
    let detail: String
    let state: State
}
