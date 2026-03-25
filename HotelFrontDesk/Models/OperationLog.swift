import Foundation

/// 操作类型
enum OperationType: String, Codable, Identifiable {
    case checkIn = "入住"
    case checkOut = "退房"
    case roomStatusChange = "房态变更"
    case roomAdd = "新增房间"
    case roomEdit = "编辑房间"
    case roomDelete = "删除房间"
    case depositCollect = "收取押金"
    case depositRefund = "退还押金"
    case passwordChange = "修改密码"
    case dataReset = "数据重置"
    case testDataGenerate = "生成测试数据"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .checkIn: "arrow.right.circle.fill"
        case .checkOut: "arrow.left.circle.fill"
        case .roomStatusChange: "arrow.triangle.2.circlepath"
        case .roomAdd: "plus.circle.fill"
        case .roomEdit: "pencil.circle.fill"
        case .roomDelete: "trash.circle.fill"
        case .depositCollect: "banknote.fill"
        case .depositRefund: "arrow.uturn.left.circle.fill"
        case .passwordChange: "key.fill"
        case .dataReset: "exclamationmark.triangle.fill"
        case .testDataGenerate: "wand.and.stars"
        }
    }

    var color: String {
        switch self {
        case .checkIn: "green"
        case .checkOut: "blue"
        case .roomStatusChange: "orange"
        case .roomAdd: "green"
        case .roomEdit: "blue"
        case .roomDelete: "red"
        case .depositCollect: "blue"
        case .depositRefund: "orange"
        case .passwordChange: "purple"
        case .dataReset: "red"
        case .testDataGenerate: "purple"
        }
    }
}

/// 操作日志记录
struct OperationLog: Identifiable, Codable {
    let id: String
    let type: OperationType
    let timestamp: Date
    let summary: String     // 简要描述，如 "101房 张三入住"
    let detail: String      // 详细信息
    let roomNumber: String? // 关联房间号（可选）
    let operatorName: String // 操作人姓名
    let operatorRole: String // "管理员" 或 "前台员工"

    init(
        type: OperationType,
        summary: String,
        detail: String,
        roomNumber: String? = nil,
        staffName: String = "系统",
        staffRole: String = "系统"
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.timestamp = Date()
        self.summary = summary
        self.detail = detail
        self.roomNumber = roomNumber
        self.operatorName = staffName
        self.operatorRole = staffRole
    }
}
