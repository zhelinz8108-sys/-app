import Foundation
import CloudKit

// MARK: - 入住记录模型
struct Reservation: Identifiable {
    let id: String
    var guestID: String
    var roomID: String
    var checkInDate: Date
    var expectedCheckOut: Date
    var actualCheckOut: Date?
    var isActive: Bool
    var numberOfGuests: Int
    var dailyRate: Double // 入住时的房价（用于历史记录）

    // 关联数据（查询后填充）
    var guest: Guest?
    var room: Room?
}

// MARK: - CloudKit Conversion
extension Reservation {
    static let recordType = "Reservation"

    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.guestID = (record["guestRef"] as? CKRecord.Reference)?.recordID.recordName ?? ""
        self.roomID = (record["roomRef"] as? CKRecord.Reference)?.recordID.recordName ?? ""
        self.checkInDate = record["checkInDate"] as? Date ?? Date()
        self.expectedCheckOut = record["expectedCheckOut"] as? Date ?? Date()
        self.actualCheckOut = record["actualCheckOut"] as? Date
        self.isActive = (record["isActive"] as? Int64 ?? 1) == 1
        self.numberOfGuests = Int(record["numberOfGuests"] as? Int64 ?? 1)
        self.dailyRate = record["dailyRate"] as? Double ?? 0
    }

    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Reservation.recordType, recordID: CKRecord.ID(recordName: id))
        record["guestRef"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: guestID), action: .none) as CKRecordValue
        record["roomRef"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: roomID), action: .none) as CKRecordValue
        record["checkInDate"] = checkInDate as CKRecordValue
        record["expectedCheckOut"] = expectedCheckOut as CKRecordValue
        record["actualCheckOut"] = actualCheckOut as CKRecordValue?
        record["isActive"] = (isActive ? 1 : 0) as CKRecordValue
        record["numberOfGuests"] = numberOfGuests as CKRecordValue
        record["dailyRate"] = dailyRate as CKRecordValue
        return record
    }
}

// MARK: - 计算属性
extension Reservation {
    var nightsStayed: Int {
        let endDate = actualCheckOut ?? expectedCheckOut
        let components = Calendar.current.dateComponents([.day], from: checkInDate, to: endDate)
        let days = components.day ?? 1
        if days < 0 {
            print("⚠️ Reservation \(id): checkInDate (\(checkInDate)) > endDate (\(endDate)), nightsStayed clamped to 1")
        }
        return max(days, 1)
    }

    /// 总房费 = 天数 × 每晚价格
    var totalRevenue: Double {
        Double(nightsStayed) * dailyRate
    }
}
