import Foundation
import CloudKit

// MARK: - 押金操作类型
enum DepositType: String, Codable, Identifiable {
    case collect = "收取"
    case refund = "退还"

    var id: String { rawValue }
}

// MARK: - 支付方式
enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash = "现金"
    case wechat = "微信"
    case alipay = "支付宝"
    case bankCard = "银行卡"
    case pos = "POS机"
    case transfer = "转账"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .cash: L("payment.cash")
        case .wechat: L("payment.wechat")
        case .alipay: L("payment.alipay")
        case .bankCard: L("payment.bankCard")
        case .pos: L("payment.pos")
        case .transfer: L("payment.transfer")
        }
    }

    var icon: String {
        switch self {
        case .cash: "banknote"
        case .wechat: "message.fill"
        case .alipay: "a.circle.fill"
        case .bankCard: "creditcard"
        case .pos: "rectangle.and.hand.point.up.left"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}

// MARK: - 押金记录模型
struct DepositRecord: Identifiable {
    let id: String
    var reservationID: String
    var type: DepositType
    var amount: Double
    var paymentMethod: PaymentMethod
    var timestamp: Date
    var operatorName: String?
    var notes: String? // POS回单号等
}

// MARK: - CloudKit Conversion
extension DepositRecord {
    static let recordType = "DepositRecord"

    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.reservationID = (record["reservationRef"] as? CKRecord.Reference)?.recordID.recordName ?? ""
        self.type = DepositType(rawValue: record["type"] as? String ?? "") ?? .collect
        self.amount = record["amount"] as? Double ?? 0
        self.paymentMethod = PaymentMethod(rawValue: record["paymentMethod"] as? String ?? "") ?? .cash
        self.timestamp = record["timestamp"] as? Date ?? Date()
        self.operatorName = record["operatorName"] as? String
        self.notes = record["notes"] as? String
    }

    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: DepositRecord.recordType, recordID: CKRecord.ID(recordName: id))
        record["reservationRef"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: reservationID), action: .none) as CKRecordValue
        record["type"] = type.rawValue as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["paymentMethod"] = paymentMethod.rawValue as CKRecordValue
        record["timestamp"] = timestamp as CKRecordValue
        record["operatorName"] = operatorName as CKRecordValue?
        record["notes"] = notes as CKRecordValue?
        return record
    }
}

// MARK: - 押金汇总
struct DepositSummary {
    let totalCollected: Double
    let totalRefunded: Double
    var balance: Double { totalCollected - totalRefunded }

    init(records: [DepositRecord]) {
        self.totalCollected = records
            .filter { $0.type == .collect }
            .reduce(0) { $0 + $1.amount }
        self.totalRefunded = records
            .filter { $0.type == .refund }
            .reduce(0) { $0 + $1.amount }
    }
}
