import Foundation

/// 动态定价服务
/// 优先级：特殊日期价 > 周末价 > 平日价
@MainActor
final class PricingService: ObservableObject {
    static let shared = PricingService()

    @Published var specialDates: [SpecialDatePrice] = []

    private let fileManager = FileManager.default
    private let filePath: URL

    /// 周末天数（周五、周六晚算周末价）
    /// dayOfWeek: 1=周日, 2=周一, ..., 6=周五, 7=周六
    static let weekendDays: Set<Int> = [6, 7] // 周五、周六入住算周末

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: dir, excludeFromBackup: true)
        filePath = dir.appendingPathComponent("special_dates.json")
        load()
    }

    // MARK: - 计算单晚价格

    /// 获取指定房间在指定日期的价格
    func priceForNight(room: Room, date: Date) -> Double {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)

        // 1. 检查特殊日期（优先级最高）
        // 多个特殊日期重叠时取最后添加的（后面的覆盖前面的）
        if let specialPrice = specialDates.last(where: { $0.covers(day) })?.price(for: room.roomType) {
            return specialPrice
        }

        // 2. 检查是否周末
        let weekday = cal.component(.weekday, from: day)
        if Self.weekendDays.contains(weekday) {
            return room.weekendPrice > 0 ? room.weekendPrice : room.pricePerNight
        }

        // 3. 平日价
        return room.pricePerNight
    }

    // MARK: - 计算多晚总价

    /// 计算入住期间每晚价格明细
    struct NightPrice: Identifiable {
        let id: Int
        let date: Date
        let price: Double
        let priceType: PriceType
    }

    enum PriceType: String {
        case weekday = "平日"
        case weekend = "周末"
        case special = "特价"
    }

    /// 获取入住期间每晚价格明细
    func priceBreakdown(room: Room, checkIn: Date, checkOut: Date) -> [NightPrice] {
        let cal = Calendar.current
        var result: [NightPrice] = []
        var current = cal.startOfDay(for: checkIn)
        var end = cal.startOfDay(for: checkOut)
        // Same-day checkout: ensure at least 1 night minimum
        if end <= current {
            end = cal.date(byAdding: .day, value: 1, to: current) ?? current
        }
        var index = 0

        while current < end {
            let price = priceForNight(room: room, date: current)
            let weekday = cal.component(.weekday, from: current)

            let priceType: PriceType
            if specialDates.contains(where: { $0.covers(current) && $0.price(for: room.roomType) != nil }) {
                priceType = .special
            } else if Self.weekendDays.contains(weekday) && room.weekendPrice > 0 {
                priceType = .weekend
            } else {
                priceType = .weekday
            }

            result.append(NightPrice(id: index, date: current, price: price, priceType: priceType))
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
            index += 1
        }
        return result
    }

    /// 计算入住期间总价
    func totalPrice(room: Room, checkIn: Date, checkOut: Date) -> Double {
        priceBreakdown(room: room, checkIn: checkIn, checkOut: checkOut)
            .reduce(0) { $0 + $1.price }
    }

    /// 计算入住期间平均每晚价格
    func averageNightlyRate(room: Room, checkIn: Date, checkOut: Date) -> Double {
        let breakdown = priceBreakdown(room: room, checkIn: checkIn, checkOut: checkOut)
        guard !breakdown.isEmpty else { return room.pricePerNight }
        return breakdown.reduce(0) { $0 + $1.price } / Double(breakdown.count)
    }

    // MARK: - 特殊日期 CRUD

    func addSpecialDate(_ item: SpecialDatePrice) {
        specialDates.append(item)
        persist()
    }

    func updateSpecialDate(_ item: SpecialDatePrice) {
        if let idx = specialDates.firstIndex(where: { $0.id == item.id }) {
            specialDates[idx] = item
            persist()
        }
    }

    func deleteSpecialDate(id: String) {
        specialDates.removeAll { $0.id == id }
        persist()
    }

    func fetchAll() -> [SpecialDatePrice] {
        specialDates.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - 持久化

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(specialDates) else { return }
        try? SecureStorageHelper.write(data, to: filePath, excludeFromBackup: true)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([SpecialDatePrice].self, from: data) else { return }
        specialDates = items
    }
}
