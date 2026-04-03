import Foundation

/// 夜审数据
struct NightAuditResult {
    let auditDate: Date
    let totalRooms: Int
    let occupiedRooms: Int
    let vacantRooms: Int
    let reservedRooms: Int
    let todayCheckIns: Int
    let todayCheckOuts: Int
    let todayRevenue: Double
    let overdueReservations: [Reservation]  // 超过预计退房未退的
    let occupancyRate: Double
}

/// 延住请求
struct ExtendStayRequest: Identifiable, Codable {
    let id: String
    let reservationID: String
    let roomID: String
    let roomNumber: String
    let guestName: String
    let originalCheckOut: Date
    let requestedCheckOut: Date
    let requestedBy: String    // 谁申请的
    let requestedAt: Date
    var status: ExtendStatus   // pending / approved / rejected

    enum ExtendStatus: String, Codable {
        case pending = "待审批"
        case approved = "已批准"
        case rejected = "已驳回"
    }
}

/// 夜审服务
@MainActor
final class NightAuditService: ObservableObject {
    static let shared = NightAuditService()

    @Published var extendRequests: [ExtendStayRequest] = []

    private let service = CloudKitService.shared
    private let logService = OperationLogService.shared
    private let fileManager = FileManager.default
    private let filePath: URL

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: dir, excludeFromBackup: true)
        filePath = dir.appendingPathComponent("extend_requests.json")
        loadRequests()
    }

    // MARK: - 夜审

    func performAudit() async throws -> NightAuditResult {
        let rooms = try await service.fetchAllRooms()
        let allReservations = try await service.fetchAllReservations()
        let cal = Calendar.current
        let today = Date()
        let startOfDay = cal.startOfDay(for: today)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        let occupied = rooms.filter { $0.status == .occupied }.count
        let vacant = rooms.filter { $0.status == .vacant }.count
        let reserved = rooms.filter { $0.status == .reserved }.count

        let todayCheckIns = allReservations.filter {
            $0.checkInDate >= startOfDay && $0.checkInDate < endOfDay
        }.count

        let todayCheckOuts = allReservations.filter {
            guard let co = $0.actualCheckOut else { return false }
            return co >= startOfDay && co < endOfDay
        }.count

        let todayRevenue = allReservations.filter {
            guard let co = $0.actualCheckOut else { return false }
            return co >= startOfDay && co < endOfDay
        }.reduce(0) { $0 + $1.totalRevenue }

        // 超期未退：isActive 且 expectedCheckOut < 今天开始
        let overdue = allReservations.filter {
            $0.isActive && $0.expectedCheckOut < startOfDay
        }

        let rate = rooms.count > 0 ? Double(occupied) / Double(rooms.count) * 100 : 0

        return NightAuditResult(
            auditDate: today,
            totalRooms: rooms.count,
            occupiedRooms: occupied,
            vacantRooms: vacant,
            reservedRooms: reserved,
            todayCheckIns: todayCheckIns,
            todayCheckOuts: todayCheckOuts,
            todayRevenue: todayRevenue,
            overdueReservations: overdue,
            occupancyRate: rate
        )
    }

    // MARK: - 延住申请

    func requestExtend(reservation: Reservation, newCheckOut: Date, requestedBy: String) {
        let request = ExtendStayRequest(
            id: UUID().uuidString,
            reservationID: reservation.id,
            roomID: reservation.roomID,
            roomNumber: reservation.room?.roomNumber ?? "未知",
            guestName: reservation.guest?.name ?? "未知",
            originalCheckOut: reservation.expectedCheckOut,
            requestedCheckOut: newCheckOut,
            requestedBy: requestedBy,
            requestedAt: Date(),
            status: .pending
        )
        extendRequests.insert(request, at: 0)
        persist()

        logService.log(
            type: .roomStatusChange,
            summary: "\(request.roomNumber)房 申请延住",
            detail: "客人: \(request.guestName) | 原退房: \(formatDate(request.originalCheckOut)) | 延至: \(formatDate(newCheckOut)) | 申请人: \(requestedBy)",
            roomNumber: request.roomNumber
        )
    }

    /// 管理员审批延住
    func approveExtend(requestID: String) async {
        guard let idx = extendRequests.firstIndex(where: { $0.id == requestID }) else { return }
        extendRequests[idx].status = .approved

        let request = extendRequests[idx]
        // 更新预订的退房日期（通过 CloudKitService 保持一致性）
        do {
            let allRes = try await service.fetchAllReservations()
            if var res = allRes.first(where: { $0.id == request.reservationID }) {
                res.expectedCheckOut = request.requestedCheckOut
                try await service.saveReservation(res)
            }
        } catch {
            print("延住审批：更新预订失败 \(error)")
        }

        persist()

        logService.log(
            type: .roomStatusChange,
            summary: "\(request.roomNumber)房 延住已批准",
            detail: "客人: \(request.guestName) | 延至: \(formatDate(request.requestedCheckOut)) | 审批人: \(StaffService.shared.currentName)",
            roomNumber: request.roomNumber
        )
    }

    func rejectExtend(requestID: String) {
        guard let idx = extendRequests.firstIndex(where: { $0.id == requestID }) else { return }
        extendRequests[idx].status = .rejected
        let request = extendRequests[idx]
        persist()

        logService.log(
            type: .roomStatusChange,
            summary: "\(request.roomNumber)房 延住已驳回",
            detail: "客人: \(request.guestName) | 驳回人: \(StaffService.shared.currentName)",
            roomNumber: request.roomNumber
        )
    }

    var pendingCount: Int {
        extendRequests.filter { $0.status == .pending }.count
    }

    // MARK: - 持久化

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(extendRequests) else { return }
        try? SecureStorageHelper.write(data, to: filePath, excludeFromBackup: true)
    }

    private func loadRequests() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([ExtendStayRequest].self, from: data) else { return }
        extendRequests = items
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
