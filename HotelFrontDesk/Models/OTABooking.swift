import Foundation

/// OTA 平台
enum OTAPlatform: String, Codable, CaseIterable, Identifiable {
    case meituan = "美团"
    case fliggy = "飞猪"
    case ctrip = "携程"
    case booking = "Booking"
    case agoda = "Agoda"
    case direct = "电话/到店"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .meituan: "m.circle.fill"
        case .fliggy: "airplane.circle.fill"
        case .ctrip: "globe.asia.australia.fill"
        case .booking: "b.circle.fill"
        case .agoda: "a.circle.fill"
        case .direct: "phone.circle.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .meituan: "yellow"
        case .fliggy: "orange"
        case .ctrip: "blue"
        case .booking: "indigo"
        case .agoda: "red"
        case .direct: "green"
        case .other: "gray"
        }
    }
}

/// OTA 预订状态
enum BookingStatus: String, Codable {
    case pending = "待确认"
    case confirmed = "已确认"
    case checkedIn = "已入住"
    case cancelled = "已取消"
    case noShow = "未到店"
}

/// OTA 预订记录
struct OTABooking: Identifiable, Codable {
    let id: String
    var platform: OTAPlatform
    var customPlatformName: String?
    var platformOrderID: String  // OTA 平台订单号
    var guestName: String
    var guestPhone: String
    var roomType: RoomType
    var checkInDate: Date
    var nights: Int
    var price: Double            // OTA 结算价
    var assignedRoomID: String?  // 分配的房间 ID
    var assignedRoomNumber: String?
    var status: BookingStatus
    var notes: String?
    var createdAt: Date
    var createdBy: String        // 录入人

    var checkOutDate: Date {
        Calendar.current.date(byAdding: .day, value: nights, to: checkInDate) ?? checkInDate
    }

    var totalPrice: Double {
        price * Double(nights)
    }

    var platformDisplayName: String {
        let trimmedCustomPlatformName = customPlatformName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if platform == .other,
           let trimmedCustomPlatformName,
           !trimmedCustomPlatformName.isEmpty {
            return trimmedCustomPlatformName
        }

        return platform.rawValue
    }

    init(
        id: String = UUID().uuidString,
        platform: OTAPlatform,
        customPlatformName: String? = nil,
        platformOrderID: String = "",
        guestName: String,
        guestPhone: String = "",
        roomType: RoomType,
        checkInDate: Date,
        nights: Int,
        price: Double,
        assignedRoomID: String? = nil,
        assignedRoomNumber: String? = nil,
        status: BookingStatus = .confirmed,
        notes: String? = nil,
        createdBy: String = ""
    ) {
        self.id = id
        self.platform = platform
        self.customPlatformName = customPlatformName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.platformOrderID = platformOrderID
        self.guestName = guestName
        self.guestPhone = guestPhone
        self.roomType = roomType
        self.checkInDate = checkInDate
        self.nights = max(nights, 1)
        self.price = price
        self.assignedRoomID = assignedRoomID
        self.assignedRoomNumber = assignedRoomNumber
        self.status = status
        self.notes = notes
        self.createdAt = Date()
        self.createdBy = createdBy
    }
}

struct OTABookingPlatformStat: Identifiable {
    let id: String
    let platform: OTAPlatform
    let displayName: String
    let count: Int
    let revenue: Double
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
