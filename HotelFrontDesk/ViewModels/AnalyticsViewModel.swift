import SwiftUI

// MARK: - 数据分析 ViewModel
@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published var selectedYear: Int
    @Published var selectedMonth: Int
    @Published var isLoading = false

    // 原始数据
    @Published var monthlyReservations: [Reservation] = []
    @Published var previousMonthReservations: [Reservation] = []
    @Published var allRooms: [Room] = []
    @Published var dailyOccupancyData: [(day: Int, count: Int)] = []
    @Published var prevDailyOccupancyData: [(day: Int, count: Int)] = []

    private let service = CloudKitService.shared
    private let cal = Calendar.current

    private var availableRoomCount: Int {
        allRooms.filter { $0.status != .maintenance }.count
    }

    init() {
        let now = Date()
        selectedYear = Calendar.current.component(.year, from: now)
        selectedMonth = Calendar.current.component(.month, from: now)
    }

    // MARK: - 加载数据
    func loadData() async {
        isLoading = true
        do {
            allRooms = try await service.fetchAllRooms()
            monthlyReservations = try await service.fetchReservationsForMonth(year: selectedYear, month: selectedMonth)
            // 上个月
            let (prevY, prevM) = previousMonth(year: selectedYear, month: selectedMonth)
            previousMonthReservations = try await service.fetchReservationsForMonth(year: prevY, month: prevM)
            // 每日入住数
            dailyOccupancyData = try await service.fetchDailyOccupancy(year: selectedYear, month: selectedMonth, totalRooms: availableRoomCount)
            // 上月每日入住数
            prevDailyOccupancyData = try await service.fetchDailyOccupancy(year: prevY, month: prevM, totalRooms: availableRoomCount)
        } catch {
            print("分析数据加载失败: \(error)")
        }
        isLoading = false
    }

    // MARK: - 月份切换
    func goToPreviousMonth() {
        let (y, m) = previousMonth(year: selectedYear, month: selectedMonth)
        selectedYear = y
        selectedMonth = m
        Task { await loadData() }
    }

    func goToNextMonth() {
        var m = selectedMonth + 1
        var y = selectedYear
        if m > 12 { m = 1; y += 1 }
        selectedYear = y
        selectedMonth = m
        Task { await loadData() }
    }

    var isCurrentMonth: Bool {
        let now = Date()
        return selectedYear == cal.component(.year, from: now)
            && selectedMonth == cal.component(.month, from: now)
    }

    var monthTitle: String {
        "\(selectedYear)年\(selectedMonth)月"
    }

    // MARK: - KPI 计算

    /// 当月总收入
    var monthlyRevenue: Double {
        monthlyReservations.reduce(0) { $0 + $1.totalRevenue }
    }

    /// 上月总收入
    var prevMonthRevenue: Double {
        previousMonthReservations.reduce(0) { $0 + $1.totalRevenue }
    }

    /// 收入环比变化 %
    var revenueChange: Double? {
        guard prevMonthRevenue > 0 else { return nil }
        return (monthlyRevenue - prevMonthRevenue) / prevMonthRevenue * 100
    }

    /// 当月总间夜数
    var totalNights: Int {
        monthlyReservations.reduce(0) { $0 + $1.nightsStayed }
    }

    /// 上月总间夜数
    var prevTotalNights: Int {
        previousMonthReservations.reduce(0) { $0 + $1.nightsStayed }
    }

    /// 平均每日房价 ADR
    var averageDailyRate: Double {
        guard totalNights > 0 else { return 0 }
        return monthlyRevenue / Double(totalNights)
    }

    var prevADR: Double {
        guard prevTotalNights > 0 else { return 0 }
        return prevMonthRevenue / Double(prevTotalNights)
    }

    var adrChange: Double? {
        guard prevADR > 0 else { return nil }
        return (averageDailyRate - prevADR) / prevADR * 100
    }

    /// 当月入住率
    var occupancyRate: Double {
        guard availableRoomCount > 0 else { return 0 }
        let daysInMonth = Double(daysInSelectedMonth)
        let totalRoomNights = Double(availableRoomCount) * daysInMonth
        let occupiedNights = dailyOccupancyData.reduce(0) { $0 + $1.count }
        return Double(occupiedNights) / totalRoomNights * 100
    }

    var prevOccupancyRate: Double {
        guard availableRoomCount > 0 else { return 0 }
        let (prevY, prevM) = previousMonth(year: selectedYear, month: selectedMonth)
        guard let firstOfPrev = cal.date(from: DateComponents(year: prevY, month: prevM, day: 1)),
              let daysRange = cal.range(of: .day, in: .month, for: firstOfPrev) else { return 0 }
        let totalRoomNights = Double(availableRoomCount) * Double(daysRange.count)
        let occupiedNights = prevDailyOccupancyData.reduce(0) { $0 + $1.count }
        return Double(occupiedNights) / totalRoomNights * 100
    }

    var occupancyChange: Double? {
        guard prevOccupancyRate > 0 else { return nil }
        return occupancyRate - prevOccupancyRate // 百分点差
    }

    // MARK: - 成本与利润

    /// 当月总成本（所有房间的月成本之和）
    var monthlyCost: Double {
        allRooms.reduce(0) { $0 + $1.monthlyCost }
    }

    /// 当月利润 = 收入 - 成本
    var monthlyProfit: Double {
        monthlyRevenue - monthlyCost
    }

    /// 上月利润
    var prevMonthProfit: Double {
        prevMonthRevenue - monthlyCost
    }

    /// 利润率 = 利润 / 收入 × 100
    var profitMargin: Double {
        guard monthlyRevenue > 0 else { return 0 }
        return monthlyProfit / monthlyRevenue * 100
    }

    /// 利润环比变化
    var profitChange: Double? {
        guard abs(prevMonthProfit) > 0.01 else { return nil }
        return (monthlyProfit - prevMonthProfit) / abs(prevMonthProfit) * 100
    }

    // MARK: - 每日收入数据（柱状图）

    struct DailyRevenue: Identifiable {
        let id: Int
        let day: Int
        let revenue: Double
        let reservations: [Reservation]
    }

    var dailyRevenueData: [DailyRevenue] {
        let days = daysInSelectedMonth
        var result: [DailyRevenue] = []
        for day in 1...days {
            // 找出该天退房的预订
            let dayReservations = monthlyReservations.filter { res in
                let checkOut = res.actualCheckOut ?? res.expectedCheckOut
                return cal.component(.day, from: checkOut) == day
            }
            let revenue = dayReservations.reduce(0) { $0 + $1.totalRevenue }
            result.append(DailyRevenue(id: day, day: day, revenue: revenue, reservations: dayReservations))
        }
        return result
    }

    // MARK: - 每日入住率数据（折线图）

    struct DailyOccupancy: Identifiable {
        let id: Int
        let day: Int
        let rate: Double
    }

    var dailyOccupancyRates: [DailyOccupancy] {
        guard availableRoomCount > 0 else { return [] }
        return dailyOccupancyData.map { item in
            let rate = Double(item.count) / Double(availableRoomCount) * 100
            return DailyOccupancy(id: item.day, day: item.day, rate: min(rate, 100))
        }
    }

    // MARK: - 房型收入占比（饼图）

    struct RoomTypeRevenue: Identifiable {
        let id = UUID()
        let type: String
        let revenue: Double
        let count: Int
        let color: Color
    }

    var roomTypeBreakdown: [RoomTypeRevenue] {
        // 需要通过 roomID 找到房间类型
        let roomMap = Dictionary(uniqueKeysWithValues: allRooms.map { ($0.id, $0) })
        var typeData: [RoomType: (revenue: Double, count: Int)] = [:]

        for res in monthlyReservations {
            let roomType = roomMap[res.roomID]?.roomType ?? .king
            let existing = typeData[roomType] ?? (revenue: 0, count: 0)
            typeData[roomType] = (revenue: existing.revenue + res.totalRevenue, count: existing.count + 1)
        }

        let colors: [RoomType: Color] = [.king: .blue, .twin: .green, .suite: .orange]
        return typeData.map { type, data in
            RoomTypeRevenue(type: type.rawValue, revenue: data.revenue, count: data.count, color: colors[type] ?? .gray)
        }.sorted { $0.revenue > $1.revenue }
    }

    // MARK: - 房间排行 TOP 10

    struct RoomRanking: Identifiable {
        let id: String
        let roomNumber: String
        let roomType: String
        let count: Int
        let revenue: Double
        let avgRate: Double
    }

    var topRooms: [RoomRanking] {
        let roomMap = Dictionary(uniqueKeysWithValues: allRooms.map { ($0.id, $0) })
        var roomData: [String: (count: Int, revenue: Double, nights: Int)] = [:]

        for res in monthlyReservations {
            let existing = roomData[res.roomID] ?? (count: 0, revenue: 0, nights: 0)
            roomData[res.roomID] = (
                count: existing.count + 1,
                revenue: existing.revenue + res.totalRevenue,
                nights: existing.nights + res.nightsStayed
            )
        }

        return roomData.compactMap { roomID, data in
            guard let room = roomMap[roomID] else { return nil }
            return RoomRanking(
                id: roomID,
                roomNumber: room.roomNumber,
                roomType: room.roomType.rawValue,
                count: data.count,
                revenue: data.revenue,
                avgRate: data.nights > 0 ? data.revenue / Double(data.nights) : 0
            )
        }
        .sorted { $0.revenue > $1.revenue }
        .prefix(10)
        .map { $0 }
    }

    // MARK: - 客源排行 TOP 10

    struct GuestRanking: Identifiable {
        let id: String
        let name: String
        let phone: String
        let count: Int
        let totalSpent: Double
    }

    var topGuests: [GuestRanking] {
        var guestData: [String: (name: String, phone: String, count: Int, total: Double)] = [:]

        for res in monthlyReservations {
            let name = res.guest?.name ?? "未知"
            let phone = Validators.maskedPhone(res.guest?.phone ?? "")
            let existing = guestData[res.guestID] ?? (name: name, phone: phone, count: 0, total: 0)
            guestData[res.guestID] = (
                name: name,
                phone: phone,
                count: existing.count + 1,
                total: existing.total + res.totalRevenue
            )
        }

        return guestData.map { guestID, data in
            GuestRanking(id: guestID, name: data.name, phone: data.phone, count: data.count, totalSpent: data.total)
        }
        .sorted { $0.count > $1.count }
        .prefix(10)
        .map { $0 }
    }

    // MARK: - 辅助

    var daysInSelectedMonth: Int {
        guard let firstOfMonth = cal.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return 30 }
        return range.count
    }

    private func previousMonth(year: Int, month: Int) -> (Int, Int) {
        if month == 1 { return (year - 1, 12) }
        return (year, month - 1)
    }
}
