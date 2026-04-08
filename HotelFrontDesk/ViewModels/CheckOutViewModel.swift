import SwiftUI

@MainActor
final class CheckOutViewModel: ObservableObject {
    @Published var reservation: Reservation?
    @Published var depositRecords: [DepositRecord] = []
    @Published var refundAmount: String = ""
    @Published var refundPaymentMethod: PaymentMethod = .cash
    @Published var refundNotes = "" // POS回单号
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var checkOutSuccess = false

    private let service = CloudKitService.shared
    private let logService = OperationLogService.shared

    // MARK: - 押金汇总
    var depositSummary: DepositSummary {
        DepositSummary(records: depositRecords)
    }

    var refundValue: Double {
        Double(refundAmount) ?? 0
    }

    var canRefund: Bool {
        refundValue > 0 && refundValue <= depositSummary.balance
    }

    // MARK: - 加载房间的入住信息和押金
    func loadReservation(forRoomID roomID: String) async {
        isLoading = true
        do {
            if let res = try await service.fetchActiveReservation(forRoomID: roomID) {
                var reservation = res
                // 加载客人信息
                reservation.guest = try await service.fetchGuest(id: res.guestID)
                self.reservation = reservation
                // 加载押金记录
                depositRecords = try await service.fetchDeposits(forReservationID: res.id)
                // 默认退全部余额
                let balance = depositSummary.balance
                if balance > 0 {
                    refundAmount = String(format: "%.0f", balance)
                }
            }
        } catch {
            errorMessage = "加载入住信息失败: \(ErrorHelper.userMessage(error))"
        }
        isLoading = false
    }

    // MARK: - 退押金
    func performRefund() async {
        guard canRefund, let res = reservation else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let deposit = DepositRecord(
                id: UUID().uuidString,
                reservationID: res.id,
                type: .refund,
                amount: refundValue,
                paymentMethod: refundPaymentMethod,
                timestamp: Date(),
                operatorName: StaffService.shared.currentStaff?.name ?? "未知",
                notes: refundNotes.isEmpty ? nil : refundNotes
            )
            try await service.saveDepositRecord(deposit)
            depositRecords.append(deposit)

            let roomNum = res.room?.roomNumber ?? "未知"
            let guestName = res.guest?.name ?? "未知"
            logService.log(
                type: .depositRefund,
                summary: "\(roomNum)房 退还押金 ¥\(Int(refundValue))（\(refundPaymentMethod.rawValue)）",
                detail: "客人: \(guestName) | 金额: ¥\(Int(refundValue)) | 方式: \(refundPaymentMethod.rawValue) | 退后余额: ¥\(Int(depositSummary.balance))",
                roomNumber: roomNum
            )

            refundAmount = ""
            refundNotes = ""
        } catch {
            errorMessage = "退押金失败: \(ErrorHelper.userMessage(error))"
        }
        isSubmitting = false
    }

    // MARK: - 执行退房
    func performCheckOut(roomID: String) async {
        guard let res = reservation else { return }
        isSubmitting = true
        errorMessage = nil

        var didCheckOutReservation = false
        do {
            // 1. 关闭入住记录
            try await service.checkOut(reservationID: res.id)
            didCheckOutReservation = true
            // 2. 房间状态改为脏房
            try await service.updateRoomStatus(roomID: roomID, status: .cleaning)

            // 3. 记录日志
            let roomNum = res.room?.roomNumber ?? "未知"
            let guestName = res.guest?.name ?? "未知"
            let nights = res.nightsStayed
            let revenue = res.totalRevenue
            let balance = depositSummary.balance
            logService.log(
                type: .checkOut,
                summary: "\(roomNum)房 \(guestName) 退房",
                detail: "客人: \(guestName) | 住了\(nights)晚 | 房费合计: ¥\(Int(revenue)) | 押金余额: ¥\(Int(balance)) | 房间转为脏房",
                roomNumber: roomNum
            )

            checkOutSuccess = true
        } catch {
            if didCheckOutReservation {
                try? await service.restoreActiveReservation(reservationID: res.id)
                // 恢复房间状态为入住中
                try? await service.updateRoomStatus(roomID: roomID, status: .occupied)
            }
            errorMessage = "退房失败: \(ErrorHelper.userMessage(error))"
        }
        isSubmitting = false
    }
}
