import Foundation
import CloudKit

// MARK: - 证件类型
enum IDType: String, CaseIterable, Codable, Identifiable {
    case idCard = "身份证"
    case passport = "护照"
    case other = "其他"

    var id: String { rawValue }
}

// MARK: - 客人模型
struct Guest: Identifiable {
    let id: String
    var name: String
    var idType: IDType
    var idNumber: String
    var phone: String
    var notes: String?
}

// MARK: - CloudKit Conversion
extension Guest {
    static let recordType = "Guest"

    init(from record: CKRecord) throws {
        self.id = record.recordID.recordName
        self.name = record["name"] as? String ?? ""
        self.idType = IDType(rawValue: record["idType"] as? String ?? "") ?? .idCard
        self.idNumber = try EncryptionHelper.decrypt(record["idNumber"] as? String ?? "")
        self.phone = try EncryptionHelper.decrypt(record["phone"] as? String ?? "")
        self.notes = record["notes"] as? String
    }

    func toRecord(existingRecord: CKRecord? = nil) throws -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: Guest.recordType, recordID: CKRecord.ID(recordName: id))
        record["name"] = name as CKRecordValue
        record["idType"] = idType.rawValue as CKRecordValue
        record["idNumber"] = try EncryptionHelper.encrypt(idNumber) as CKRecordValue
        record["phone"] = try EncryptionHelper.encrypt(phone) as CKRecordValue
        record["notes"] = notes as CKRecordValue?
        return record
    }
}
