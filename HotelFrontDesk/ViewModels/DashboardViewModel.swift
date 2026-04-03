import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Room counts
    @Published var totalRooms = 0
    @Published var occupiedRooms = 0
    @Published var vacantRooms = 0
    @Published var reservedRooms = 0
    @Published var cleaningRooms = 0
    @Published var maintenanceRooms = 0

    // MARK: - Today's metrics
    @Published var todayCheckIns = 0
    @Published var todayExpectedCheckOuts: [Reservation] = []
    @Published var todayRevenue: Double = 0
    @Published var todayADR: Double = 0
    @Published var todayWalkInCount = 0
    @Published var todayOTACount = 0

    // MARK: - Room list for status grid
    @Published var allRooms: [Room] = []

    // MARK: - State
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshed: Date?

    private let service = CloudKitService.shared
    private var refreshTimer: Timer?

    // MARK: - Computed

    var occupancyRate: Double {
        guard totalRooms > 0 else { return 0 }
        return Double(occupiedRooms) / Double(totalRooms)
    }

    var occupancyPercent: String {
        String(format: "%.0f%%", occupancyRate * 100)
    }

    var occupancyColor: Color {
        let rate = occupancyRate
        if rate >= 0.8 { return .appSuccess }
        if rate >= 0.5 { return .appWarning }
        return .appError
    }

    var todayRevenueFormatted: String {
        if todayRevenue >= 10000 {
            return String(format: "%.1f万", todayRevenue / 10000)
        }
        return String(format: "%.0f", todayRevenue)
    }

    var todayADRFormatted: String {
        String(format: "%.0f", todayADR)
    }

    var walkInRatioText: String {
        let total = todayWalkInCount + todayOTACount
        guard total > 0 else { return "0/0" }
        return "\(todayWalkInCount)/\(todayOTACount)"
    }

    var walkInPercent: Double {
        let total = todayWalkInCount + todayOTACount
        guard total > 0 else { return 0 }
        return Double(todayWalkInCount) / Double(total)
    }

    var expectedCheckOutCount: Int {
        todayExpectedCheckOuts.count
    }

    var roomStatusBreakdown: [(status: RoomStatus, count: Int, color: Color)] {
        [
            (.vacant, vacantRooms, .roomVacant),
            (.occupied, occupiedRooms, .roomOccupied),
            (.reserved, reservedRooms, .roomReserved),
            (.cleaning, cleaningRooms, .roomCleaning),
            (.maintenance, maintenanceRooms, .roomMaintenance)
        ].filter { $0.count > 0 }
    }

    // MARK: - Timer

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadDashboard()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Data Loading

    func loadDashboard() async {
        isLoading = true
        errorMessage = nil
        do {
            // Fetch rooms
            let rooms = try await service.fetchAllRooms()
            allRooms = rooms
            totalRooms = rooms.count
            occupiedRooms = rooms.filter { $0.status == .occupied }.count
            vacantRooms = rooms.filter { $0.status == .vacant }.count
            reservedRooms = rooms.filter { $0.status == .reserved }.count
            cleaningRooms = rooms.filter { $0.status == .cleaning }.count
            maintenanceRooms = rooms.filter { $0.status == .maintenance }.count

            // Today check-ins / check-outs
            todayCheckIns = try await service.fetchTodayCheckInCount()
            todayExpectedCheckOuts = try await service.fetchTodayExpectedCheckOuts()

            // Today's revenue from deposits collected today
            let allDeposits = try await service.fetchAllDeposits()
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: Date())
            let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

            let todayDeposits = allDeposits.filter { deposit in
                deposit.type == .collect &&
                deposit.timestamp >= startOfDay &&
                deposit.timestamp < endOfDay
            }
            todayRevenue = todayDeposits.reduce(0) { $0 + $1.amount }

            // ADR: average daily rate from today's active reservations
            let activeReservations = rooms.filter { $0.status == .occupied }
            if !activeReservations.isEmpty {
                // Fetch all reservations to get daily rates
                let allReservations = try await fetchTodayActiveReservations()
                if !allReservations.isEmpty {
                    let totalRate = allReservations.reduce(0.0) { $0 + $1.dailyRate }
                    todayADR = totalRate / Double(allReservations.count)
                } else {
                    todayADR = 0
                }
            } else {
                todayADR = 0
            }

            // Walk-in vs OTA ratio today
            calculateWalkInOTARatio(startOfDay: startOfDay, endOfDay: endOfDay)

            lastRefreshed = Date()
        } catch {
            errorMessage = "加载数据失败: \(ErrorHelper.userMessage(error))"
#if DEBUG
            // 仅在调试阶段回退到预览数据，避免生产环境误用假统计
            totalRooms = PreviewData.rooms.count
            occupiedRooms = PreviewData.rooms.filter { $0.status == .occupied }.count
            vacantRooms = PreviewData.rooms.filter { $0.status == .vacant }.count
            reservedRooms = PreviewData.rooms.filter { $0.status == .reserved }.count
            cleaningRooms = PreviewData.rooms.filter { $0.status == .cleaning }.count
            maintenanceRooms = PreviewData.rooms.filter { $0.status == .maintenance }.count
            allRooms = PreviewData.rooms
#endif
        }
        isLoading = false
    }

    // MARK: - Private helpers

    /// Fetch active reservations (currently checked in)
    private func fetchTodayActiveReservations() async throws -> [Reservation] {
        // Use the local storage service for active reservations
        let local = LocalStorageService.shared
        return local.fetchActiveReservations()
    }

    /// Calculate walk-in vs OTA ratio for today
    private func calculateWalkInOTARatio(startOfDay: Date, endOfDay: Date) {
        let otaService = OTABookingService.shared
        // OTA bookings that checked in today
        let todayOTA = otaService.bookings.filter { booking in
            booking.status == .checkedIn &&
            booking.checkInDate >= startOfDay &&
            booking.checkInDate < endOfDay
        }
        // Also count confirmed arrivals for today as OTA
        let todayOTAArrivals = otaService.todayArrivals
        todayOTACount = todayOTA.count + todayOTAArrivals.count

        // Walk-ins = total today check-ins - OTA check-ins
        // todayCheckIns counts all reservations created today
        // OTA checked-in today = those that transitioned to checkedIn status today
        let otaCheckedIn = todayOTA.count
        todayWalkInCount = max(todayCheckIns - otaCheckedIn, 0)
    }
}
