import SwiftUI
import CloudKit

// MARK: - 房间状态
enum RoomStatus: String, CaseIterable, Codable, Identifiable {
    case vacant = "vacant"
    case reserved = "reserved"
    case occupied = "occupied"
    case cleaning = "cleaning"
    case maintenance = "maintenance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vacant: L("room.vacant")
        case .reserved: L("room.reserved")
        case .occupied: L("room.occupied")
        case .cleaning: L("room.cleaning")
        case .maintenance: L("room.maintenance")
        }
    }

    var color: Color {
        switch self {
        case .vacant: .roomVacant
        case .reserved: .roomReserved
        case .occupied: .roomOccupied
        case .cleaning: .roomCleaning
        case .maintenance: .roomMaintenance
        }
    }

    var icon: String {
        switch self {
        case .vacant: "door.left.hand.open"
        case .reserved: "bookmark.fill"
        case .occupied: "person.fill"
        case .cleaning: "sparkles"
        case .maintenance: "wrench.fill"
        }
    }
}

// MARK: - 房间类型
enum RoomType: String, CaseIterable, Codable, Identifiable {
    case king = "大床房"
    case twin = "双床房"
    case suite = "套房"

    var id: String { rawValue }
}

// MARK: - 房间朝向
enum RoomOrientation: String, CaseIterable, Codable, Identifiable {
    case south = "朝南"
    case north = "朝北"
    case east = "朝东"
    case west = "朝西"
    case southEast = "东南"
    case southWest = "西南"
    case northEast = "东北"
    case northWest = "西北"

    var id: String { rawValue }
}

// MARK: - 房间模型
struct Room: Identifiable, Hashable {
    let id: String // CKRecord.ID.recordName
    var roomNumber: String
    var floor: Int
    var roomType: RoomType
    var orientation: RoomOrientation
    var status: RoomStatus
    var pricePerNight: Double   // 平日价
    var weekendPrice: Double    // 周末价（周五周六晚）
    var monthlyCost: Double     // 每月成本（水电、折旧、清洁等）
    var notes: String?

    // CloudKit record reference (not persisted in model)
    var recordID: CKRecord.ID? {
        CKRecord.ID(recordName: id)
    }
}

// MARK: - CloudKit Conversion
extension Room {
    static let recordType = "Room"

    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.roomNumber = record["roomNumber"] as? String ?? ""
        self.floor = record["floor"] as? Int ?? 1
        self.roomType = RoomType(rawValue: record["roomType"] as? String ?? "") ?? .king
        self.orientation = RoomOrientation(rawValue: record["orientation"] as? String ?? "") ?? .south
        self.status = RoomStatus(rawValue: record["status"] as? String ?? "") ?? .vacant
        self.pricePerNight = record["pricePerNight"] as? Double ?? 0
        self.weekendPrice = record["weekendPrice"] as? Double ?? 0
        self.monthlyCost = record["monthlyCost"] as? Double ?? 0
        self.notes = record["notes"] as? String
    }

    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Room.recordType, recordID: CKRecord.ID(recordName: id))
        record["roomNumber"] = roomNumber as CKRecordValue
        record["floor"] = floor as CKRecordValue
        record["roomType"] = roomType.rawValue as CKRecordValue
        record["orientation"] = orientation.rawValue as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        record["pricePerNight"] = pricePerNight as CKRecordValue
        record["weekendPrice"] = weekendPrice as CKRecordValue
        record["monthlyCost"] = monthlyCost as CKRecordValue
        record["notes"] = notes as CKRecordValue?
        return record
    }
}
