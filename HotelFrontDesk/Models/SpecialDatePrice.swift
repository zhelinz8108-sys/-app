import Foundation

/// 特殊日期定价（节假日、旺季等）
struct SpecialDatePrice: Identifiable, Codable {
    let id: String
    var name: String          // "国庆节", "春节", "淡季"
    var startDate: Date
    var endDate: Date
    var priceByRoomType: [String: Double] // RoomType.rawValue → 价格
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        startDate: Date,
        endDate: Date,
        priceByRoomType: [String: Double] = [:],
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.priceByRoomType = priceByRoomType
        self.isActive = isActive
    }

    /// 是否覆盖指定日期
    func covers(_ date: Date) -> Bool {
        guard isActive else { return false }
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let start = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        return day >= start && day <= end
    }

    /// 获取指定房型的价格
    func price(for roomType: RoomType) -> Double? {
        priceByRoomType[roomType.rawValue]
    }
}
