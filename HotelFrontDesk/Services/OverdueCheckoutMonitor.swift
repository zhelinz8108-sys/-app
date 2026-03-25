import Foundation
import Combine

/// 超期未退房监控 — 中午12点起每30分钟弹窗提醒，直到全部退完
@MainActor
final class OverdueCheckoutMonitor: ObservableObject {
    static let shared = OverdueCheckoutMonitor()

    /// 超期未退的预订列表
    @Published var overdueReservations: [Reservation] = []
    /// 是否显示提醒弹窗
    @Published var showAlert = false

    /// 提醒开始时间（每天12点）
    private let reminderStartHour = 12
    /// 提醒间隔（秒）
    private let reminderInterval: TimeInterval = 30 * 60 // 30分钟
    /// 上次提醒时间
    private var lastReminderTime: Date?
    /// 定时器
    private var timer: Timer?

    private let service = CloudKitService.shared
    private let calendar = Calendar.current

    private init() {}

    /// 启动监控（登录后调用）
    func start() {
        guard timer == nil else { return }
        // 每60秒检查一次
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.tick()
            }
        }
        // 立即执行一次
        Task { await tick() }
    }

    /// 停止监控（登出时调用）
    func stop() {
        timer?.invalidate()
        timer = nil
        overdueReservations = []
        showAlert = false
        lastReminderTime = nil
    }

    /// 用户关闭弹窗后调用
    func dismissAlert() {
        showAlert = false
    }

    // MARK: - 核心检测

    private func tick() async {
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        // 12点前不提醒
        guard hour >= reminderStartHour else { return }

        // 获取超期预订
        let overdue = await fetchOverdueReservations()

        // 没有超期 → 清空状态
        guard !overdue.isEmpty else {
            overdueReservations = []
            return
        }

        overdueReservations = overdue

        // 已经在显示弹窗 → 不重复弹
        guard !showAlert else { return }

        // 检查是否到达下一个提醒时间点
        if let lastTime = lastReminderTime {
            let elapsed = now.timeIntervalSince(lastTime)
            guard elapsed >= reminderInterval else { return }
        }

        // 触发提醒
        lastReminderTime = now
        showAlert = true
    }

    /// 获取所有超期未退的预订
    private func fetchOverdueReservations() async -> [Reservation] {
        do {
            let allReservations = try await service.fetchAllReservations()
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
            let hour = calendar.component(.hour, from: now)

            return allReservations.filter { res in
                guard res.isActive else { return false }
                let expectedEnd = calendar.startOfDay(for: res.expectedCheckOut)

                // 昨天及更早该退的
                if expectedEnd < startOfToday { return true }

                // 今天该退且已过12点的
                if expectedEnd >= startOfToday && expectedEnd < endOfToday && hour >= reminderStartHour {
                    return true
                }

                return false
            }
        } catch {
            print("超期检测失败: \(error)")
            return []
        }
    }

    /// 弹窗显示文本
    var alertMessage: String {
        let rooms = overdueReservations.compactMap { res -> String? in
            let roomNum = res.room?.roomNumber ?? "?"
            let guestName = res.guest?.name ?? "未知"
            return "\(roomNum)房 \(guestName)"
        }

        if rooms.isEmpty { return "" }
        return rooms.joined(separator: "、") + "\n共\(rooms.count)间超期未退"
    }
}
