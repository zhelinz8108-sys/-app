import Foundation

/// OTA 预订管理服务
@MainActor
final class OTABookingService: ObservableObject {
    static let shared = OTABookingService()

    @Published var bookings: [OTABooking] = []

    private let fileManager = FileManager.default
    private let filePath: URL

    private init() {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("无法访问 Documents 目录")
        }
        let dir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: dir, excludeFromBackup: true)
        filePath = dir.appendingPathComponent("ota_bookings.json")
        load()
    }

    // MARK: - CRUD

    func add(_ booking: OTABooking) {
        bookings.insert(booking, at: 0)
        persist()
    }

    func update(_ booking: OTABooking) {
        if let idx = bookings.firstIndex(where: { $0.id == booking.id }) {
            bookings[idx] = booking
            persist()
        }
    }

    func delete(id: String) {
        bookings.removeAll { $0.id == id }
        persist()
    }

    func updateStatus(id: String, status: BookingStatus) {
        if let idx = bookings.firstIndex(where: { $0.id == id }) {
            bookings[idx].status = status
            persist()
        }
    }

    func assignRoom(bookingID: String, roomID: String, roomNumber: String) {
        if let idx = bookings.firstIndex(where: { $0.id == bookingID }) {
            bookings[idx].assignedRoomID = roomID
            bookings[idx].assignedRoomNumber = roomNumber
            persist()
        }
    }

    // MARK: - 查询

    /// 今日预到（已确认 + 今天入住）
    var todayArrivals: [OTABooking] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return bookings.filter {
            $0.status == .confirmed && $0.checkInDate >= today && $0.checkInDate < tomorrow
        }
    }

    /// 未来预订（已确认 + 入住日期在明天及以后）
    var upcomingBookings: [OTABooking] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        return bookings.filter {
            $0.status == .confirmed && $0.checkInDate >= tomorrow
        }.sorted { $0.checkInDate < $1.checkInDate }
    }

    /// 按平台统计
    var platformStats: [OTABookingPlatformStat] {
        var stats: [String: (platform: OTAPlatform, count: Int, revenue: Double)] = [:]
        for booking in bookings where booking.status != .cancelled {
            let platformKey = booking.platformDisplayName
            let existing = stats[platformKey] ?? (platform: booking.platform, count: 0, revenue: 0)
            stats[platformKey] = (
                platform: existing.platform,
                count: existing.count + 1,
                revenue: existing.revenue + booking.totalPrice
            )
        }
        return stats.map {
            OTABookingPlatformStat(
                id: $0.key,
                platform: $0.value.platform,
                displayName: $0.key,
                count: $0.value.count,
                revenue: $0.value.revenue
            )
        }
            .sorted { $0.revenue > $1.revenue }
    }

    // MARK: - 持久化

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bookings) else { return }
        try? SecureStorageHelper.write(data, to: filePath, excludeFromBackup: true)
        BackupService.shared.markDirty()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([OTABooking].self, from: data) else { return }
        bookings = items
    }
}
