import SwiftUI

@MainActor
final class RoomListViewModel: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selectedFloor: Int? = nil // nil = 全部楼层
    @Published var selectedStatus: RoomStatus? = nil // nil = 全部状态
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = CloudKitService.shared
    private let logService = OperationLogService.shared

    // MARK: - 筛选后的房间
    var filteredRooms: [Room] {
        rooms.filter { room in
            let floorMatch = selectedFloor == nil || room.floor == selectedFloor
            let statusMatch = selectedStatus == nil || room.status == selectedStatus
            return floorMatch && statusMatch
        }
    }

    // MARK: - 可用楼层列表
    var floors: [Int] {
        Array(Set(rooms.map(\.floor))).sorted()
    }

    // MARK: - 统计
    var totalCount: Int { rooms.count }
    var vacantCount: Int { rooms.filter { $0.status == .vacant }.count }
    var reservedCount: Int { rooms.filter { $0.status == .reserved }.count }
    var occupiedCount: Int { rooms.filter { $0.status == .occupied }.count }
    var cleaningCount: Int { rooms.filter { $0.status == .cleaning }.count }

    var occupancyRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(occupiedCount) / Double(totalCount)
    }

    // MARK: - 获取空房列表（真实可分配的空房，不含已预订）
    var vacantRooms: [Room] {
        rooms.filter { $0.status == .vacant }
    }

    // MARK: - 加载数据
    func loadRooms() async {
        isLoading = true
        errorMessage = nil
        do {
            rooms = try await service.fetchAllRooms()
        } catch {
            errorMessage = "加载房间失败: \(ErrorHelper.userMessage(error))"
#if DEBUG
            // 仅在调试阶段回退到预览数据，避免生产环境误用假房态
            if rooms.isEmpty {
                rooms = PreviewData.rooms
            }
#endif
        }
        isLoading = false
    }

    // MARK: - 更新房态
    func updateStatus(for room: Room, to status: RoomStatus) async {
        // 先更新本地
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index].status = status
        }
        // 同步到 CloudKit
        do {
            try await service.updateRoomStatus(roomID: room.id, status: status)
            logService.log(
                type: .roomStatusChange,
                summary: "\(room.roomNumber)房 \(room.status.displayName) → \(status.displayName)",
                detail: "房间: \(room.roomNumber) | \(room.floor)楼 | \(room.roomType.rawValue) | 状态: \(room.status.displayName) → \(status.displayName)",
                roomNumber: room.roomNumber
            )
        } catch {
            // 回滚
            if let index = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[index].status = room.status
            }
            errorMessage = "更新状态失败: \(ErrorHelper.userMessage(error))"
        }
    }
}
