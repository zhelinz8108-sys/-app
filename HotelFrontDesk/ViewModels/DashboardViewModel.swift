import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var totalRooms = 0
    @Published var occupiedRooms = 0
    @Published var vacantRooms = 0
    @Published var reservedRooms = 0
    @Published var todayCheckIns = 0
    @Published var todayExpectedCheckOuts: [Reservation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = CloudKitService.shared

    var occupancyRate: Double {
        guard totalRooms > 0 else { return 0 }
        return Double(occupiedRooms) / Double(totalRooms)
    }

    var occupancyPercent: String {
        String(format: "%.0f%%", occupancyRate * 100)
    }

    func loadDashboard() async {
        isLoading = true
        do {
            let rooms = try await service.fetchAllRooms()
            totalRooms = rooms.count
            occupiedRooms = rooms.filter { $0.status == .occupied }.count
            vacantRooms = rooms.filter { $0.status == .vacant }.count
            reservedRooms = rooms.filter { $0.status == .reserved }.count
            todayCheckIns = try await service.fetchTodayCheckInCount()
            todayExpectedCheckOuts = try await service.fetchTodayExpectedCheckOuts()
        } catch {
            errorMessage = "加载数据失败: \(ErrorHelper.userMessage(error))"
            // 开发阶段用预览数据
            totalRooms = PreviewData.rooms.count
            occupiedRooms = PreviewData.rooms.filter { $0.status == .occupied }.count
            vacantRooms = PreviewData.rooms.filter { $0.status == .vacant }.count
            reservedRooms = PreviewData.rooms.filter { $0.status == .reserved }.count
        }
        isLoading = false
    }
}
