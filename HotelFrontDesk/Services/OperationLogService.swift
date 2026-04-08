import Foundation

/// 操作日志存储服务
@MainActor
final class OperationLogService {
    static let shared = OperationLogService()

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv
        case json

        var id: String { rawValue }
        var displayName: String { rawValue.uppercased() }
        var fileExtension: String { rawValue }
    }

    enum ExportError: LocalizedError {
        case noLogs

        var errorDescription: String? {
            switch self {
            case .noLogs:
                return "当前没有可导出的日志"
            }
        }
    }

    private let fileManager = FileManager.default
    private let filePath: URL
    private var logs: [OperationLog] = []

    private init() {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("无法访问 Documents 目录")
        }
        let dir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: dir, excludeFromBackup: true)
        filePath = dir.appendingPathComponent("operation_logs.json")
        loadLogs()
    }

    // MARK: - 写入日志

    func log(
        type: OperationType,
        summary: String,
        detail: String,
        roomNumber: String? = nil
    ) {
        let staff = StaffService.shared.currentStaff
        let entry = OperationLog(
            type: type,
            summary: summary,
            detail: detail,
            roomNumber: roomNumber,
            staffName: staff?.name ?? "系统",
            staffRole: staff?.role.rawValue ?? "系统"
        )
        logs.insert(entry, at: 0)
        // 限制日志总量，防止无限增长
        if logs.count > 10000 {
            logs = Array(logs.prefix(10000))
        }
        persist()
        BackupService.shared.markDirty()
    }

    // MARK: - 查询

    /// 获取所有日志（最新在前）
    func fetchAll() -> [OperationLog] {
        logs
    }

    /// 按类型筛选
    func fetch(type: OperationType) -> [OperationLog] {
        logs.filter { $0.type == type }
    }

    /// 按日期范围筛选
    func fetch(from startDate: Date, to endDate: Date) -> [OperationLog] {
        logs.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
    }

    /// 按房间号筛选
    func fetch(roomNumber: String) -> [OperationLog] {
        logs.filter { $0.roomNumber == roomNumber }
    }

    /// 日志总数
    var count: Int { logs.count }

    func exportLogs(_ selectedLogs: [OperationLog]? = nil, format: ExportFormat = .csv) throws -> URL {
        let logsToExport = selectedLogs ?? logs
        guard !logsToExport.isEmpty else {
            throw ExportError.noLogs
        }

        let fileName = "operation_logs_\(timestampForFileName()).\(format.fileExtension)"
        let url = fileManager.temporaryDirectory.appendingPathComponent(fileName)

        switch format {
        case .csv:
            try SecureStorageHelper.write(Data(csvContent(for: logsToExport).utf8), to: url, excludeFromBackup: true)
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(logsToExport)
            try SecureStorageHelper.write(data, to: url, excludeFromBackup: true)
        }

        return url
    }

    // MARK: - 持久化

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(logs) else { return }
        try? SecureStorageHelper.write(data, to: filePath, excludeFromBackup: true)
    }

    private func loadLogs() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([OperationLog].self, from: data) else { return }
        logs = items
    }

    /// 清除所有日志（仅用于重置）
    func clearAll() {
        logs.removeAll()
        persist()
        BackupService.shared.markDirty()
    }

    private func csvContent(for logs: [OperationLog]) -> String {
        let header = ["timestamp", "type", "summary", "detail", "roomNumber", "operatorName", "operatorRole"]
        let formatter = ISO8601DateFormatter()

        let rows = logs.map { log in
            [
                formatter.string(from: log.timestamp),
                log.type.rawValue,
                log.summary,
                log.detail,
                log.roomNumber ?? "",
                log.operatorName,
                log.operatorRole,
            ]
            .map(csvEscaped)
            .joined(separator: ",")
        }

        return ([header.joined(separator: ",")] + rows).joined(separator: "\n")
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func timestampForFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
