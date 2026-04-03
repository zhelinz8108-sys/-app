import Foundation

// MARK: - 对账记录模型

struct ReconciliationRecord: Identifiable, Codable {
    let id: String
    let date: Date
    let openingBalance: Double
    let expectedCash: Double
    let actualCash: Double
    let variance: Double // actual - expected
    let incomeByMethod: [String: Double] // PaymentMethod.rawValue -> total
    let totalIncome: Double
    let depositCount: Int
    let refundCount: Int
    let operatorName: String
    let notes: String
    let createdAt: Date
}

// MARK: - 今日交易记录（展示用）

struct DailyTransaction: Identifiable {
    let id: String
    let time: Date
    let description: String
    let amount: Double
    let type: DepositType
    let paymentMethod: PaymentMethod
    let roomNumber: String?
}

// MARK: - 日结对账 ViewModel

@MainActor
final class DailyReconciliationViewModel: ObservableObject {
    // 数据
    @Published var todayDeposits: [DepositRecord] = []
    @Published var transactions: [DailyTransaction] = []
    @Published var incomeByMethod: [PaymentMethod: Double] = [:]
    @Published var totalIncome: Double = 0
    @Published var totalRefunds: Double = 0
    @Published var depositCount: Int = 0
    @Published var refundCount: Int = 0

    // 现金对账输入
    @Published var openingBalance: String = "0"
    @Published var actualCashCount: String = ""
    @Published var notes: String = ""

    // 历史记录
    @Published var history: [ReconciliationRecord] = []

    // 状态
    @Published var isLoading = false
    @Published var showCompletion = false
    @Published var errorMessage: String?

    private let service = CloudKitService.shared
    private let fileManager = FileManager.default
    private let filePath: URL

    // MARK: - 计算属性

    /// 预期现金余额 = 开店现金 + 现金收入 - 现金退款
    var expectedCash: Double {
        let opening = Double(openingBalance) ?? 0
        let cashIncome = incomeByMethod[.cash] ?? 0
        let cashRefunds = todayDeposits
            .filter { $0.type == .refund && $0.paymentMethod == .cash }
            .reduce(0) { $0 + $1.amount }
        return opening + cashIncome - cashRefunds
    }

    /// 实际现金
    var actualCashValue: Double {
        Double(actualCashCount) ?? 0
    }

    /// 差异 = 实际 - 预期
    var variance: Double {
        actualCashValue - expectedCash
    }

    /// 差异是否超过警戒线（¥10）
    var hasWarning: Bool {
        abs(variance) > 10
    }

    /// 今天是否已经完成对账
    var todayAlreadyReconciled: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return history.contains { cal.startOfDay(for: $0.date) == today }
    }

    // MARK: - 初始化

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: dir, excludeFromBackup: true)
        filePath = dir.appendingPathComponent("reconciliation_history.json")
        loadHistory()
    }

    // MARK: - 加载今日数据

    func loadTodayData() async {
        isLoading = true
        errorMessage = nil
        do {
            let allDeposits = try await service.fetchAllDeposits()
            let allReservations = try await service.fetchAllReservations()
            let allRooms = try await service.fetchAllRooms()

            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: Date())
            let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

            // 筛选今日押金记录
            todayDeposits = allDeposits.filter { d in
                d.timestamp >= startOfDay && d.timestamp < endOfDay
            }

            // 构建房间号映射：reservationID -> roomNumber
            let roomMap = Dictionary(uniqueKeysWithValues: allRooms.map { ($0.id, $0.roomNumber) })
            let resRoomMap = Dictionary(uniqueKeysWithValues: allReservations.map { ($0.id, roomMap[$0.roomID] ?? "?") })

            // 构建交易列表
            transactions = todayDeposits.map { d in
                let roomNumber = resRoomMap[d.reservationID]
                let desc = d.type == .collect
                    ? "收取押金"
                    : "退还押金"
                return DailyTransaction(
                    id: d.id,
                    time: d.timestamp,
                    description: desc,
                    amount: d.amount,
                    type: d.type,
                    paymentMethod: d.paymentMethod,
                    roomNumber: roomNumber
                )
            }.sorted { $0.time < $1.time }

            // 按支付方式统计收入（仅收取）
            var methodTotals: [PaymentMethod: Double] = [:]
            var totalInc: Double = 0
            var totalRef: Double = 0
            var depCount = 0
            var refCount = 0

            for d in todayDeposits {
                if d.type == .collect {
                    methodTotals[d.paymentMethod, default: 0] += d.amount
                    totalInc += d.amount
                    depCount += 1
                } else {
                    totalRef += d.amount
                    refCount += 1
                }
            }

            incomeByMethod = methodTotals
            totalIncome = totalInc
            totalRefunds = totalRef
            depositCount = depCount
            refundCount = refCount
        } catch {
            errorMessage = "加载数据失败: \(ErrorHelper.userMessage(error))"
        }
        isLoading = false
    }

    // MARK: - 完成对账

    func completeReconciliation() {
        let operatorName = StaffService.shared.currentName

        // 构建按方式统计的字典（String key for Codable）
        var methodDict: [String: Double] = [:]
        for (method, amount) in incomeByMethod {
            methodDict[method.rawValue] = amount
        }

        let record = ReconciliationRecord(
            id: UUID().uuidString,
            date: Date(),
            openingBalance: Double(openingBalance) ?? 0,
            expectedCash: expectedCash,
            actualCash: actualCashValue,
            variance: variance,
            incomeByMethod: methodDict,
            totalIncome: totalIncome,
            depositCount: depositCount,
            refundCount: refundCount,
            operatorName: operatorName,
            notes: notes,
            createdAt: Date()
        )

        history.insert(record, at: 0)
        persistHistory()

        // 记录操作日志
        OperationLogService.shared.log(
            type: .roomStatusChange,
            summary: "完成日结对账",
            detail: "预期现金: ¥\(Int(expectedCash)) | 实际现金: ¥\(Int(actualCashValue)) | 差异: ¥\(Int(variance)) | 总收入: ¥\(Int(totalIncome)) | 操作人: \(operatorName)",
            roomNumber: nil
        )

        showCompletion = true
    }

    // MARK: - 导出对账报告文本

    func exportReportText() -> String {
        let dateStr = Date().chineseDate
        var text = """
        ============================
        日结对账报告 - \(dateStr)
        ============================

        【收入汇总】
        """

        let sortedMethods = incomeByMethod.sorted { $0.value > $1.value }
        for (method, amount) in sortedMethods {
            text += "\n  \(method.rawValue): ¥\(String(format: "%.2f", amount))"
        }
        text += "\n  总收入: ¥\(String(format: "%.2f", totalIncome))"
        text += "\n  总退款: ¥\(String(format: "%.2f", totalRefunds))"
        text += "\n  净收入: ¥\(String(format: "%.2f", totalIncome - totalRefunds))"

        text += """

        \n【现金对账】
          开店现金: ¥\(openingBalance)
          预期现金: ¥\(String(format: "%.2f", expectedCash))
          实际现金: ¥\(actualCashCount.isEmpty ? "未填写" : "¥" + actualCashCount)
          差异: ¥\(String(format: "%.2f", variance))
        """

        if !notes.isEmpty {
            text += "\n\n【备注】\n  \(notes)"
        }

        text += "\n\n【交易明细】(共\(transactions.count)笔)"
        for t in transactions {
            let sign = t.type == .collect ? "+" : "-"
            let room = t.roomNumber ?? "?"
            text += "\n  \(t.time.timeString) | \(room)房 | \(t.description) | \(sign)¥\(String(format: "%.2f", t.amount)) | \(t.paymentMethod.rawValue)"
        }

        text += "\n\n对账人: \(StaffService.shared.currentName)"
        text += "\n============================\n"

        return text
    }

    /// 生成对账报告文件 URL（供分享）
    func generateReportFile() -> URL? {
        let text = exportReportText()
        let fileName = "日结对账_\(Date().chineseDate).txt"
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent(fileName)
        do {
            try SecureStorageHelper.write(Data(text.utf8), to: fileURL, excludeFromBackup: true)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - 持久化

    private func persistHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return }
        try? SecureStorageHelper.write(data, to: filePath, excludeFromBackup: true)
    }

    private func loadHistory() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: filePath),
              let items = try? decoder.decode([ReconciliationRecord].self, from: data) else { return }
        history = items
    }
}
