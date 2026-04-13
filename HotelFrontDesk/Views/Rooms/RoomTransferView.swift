import SwiftUI

private enum RoomTransferError: LocalizedError {
    case currentRoomUnavailable(String)
    case targetRoomUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .currentRoomUnavailable(let roomNumber):
            return "\(roomNumber) 房当前状态已变化，请刷新房态后重试换房"
        case .targetRoomUnavailable(let roomNumber):
            return "\(roomNumber) 房已不可用，请重新选择目标房间"
        }
    }
}

/// 换房操作：将客人从当前房间转移到另一间空房
struct RoomTransferView: View {
    let currentRoom: Room
    let reservation: Reservation?
    let depositRecords: [DepositRecord]
    @ObservedObject var roomListViewModel: RoomListViewModel
    var onComplete: () -> Void

    @State private var targetRoom: Room?
    @State private var adjustPrice = false
    @State private var newDailyRate = ""
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let service = CloudKitService.shared
    private let logService = OperationLogService.shared

    /// 可选的目标房间：空房 + 已预订，排除当前房间
    private var availableRooms: [Room] {
        roomListViewModel.rooms.filter {
            ($0.status == .vacant || $0.status == .reserved) && $0.id != currentRoom.id
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 当前房间信息
                Section("当前房间") {
                    HStack {
                        Text(currentRoom.roomNumber)
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text(currentRoom.roomType.rawValue)
                            Text("\(currentRoom.floor)楼 · \(currentRoom.orientation.rawValue) · ¥\(Int(currentRoom.pricePerNight))/晚")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let res = reservation {
                        HStack {
                            Text("客人")
                            Spacer()
                            Text(res.guest?.name ?? "未知")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("入住")
                            Spacer()
                            Text(res.checkInDate.chineseDate)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("当前房价")
                            Spacer()
                            Text("¥\(Int(res.dailyRate))/晚")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 选择目标房间
                Section("换到哪间") {
                    if availableRooms.isEmpty {
                        Text("没有空房可换")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableRooms) { room in
                            Button {
                                targetRoom = room
                                if !adjustPrice {
                                    newDailyRate = String(Int(room.pricePerNight))
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(room.roomNumber)
                                        .font(.title3.bold())
                                        .foregroundStyle(targetRoom?.id == room.id ? .blue : .primary)
                                        .frame(width: 50)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(room.roomType.rawValue)
                                                .font(.subheadline)
                                            Text(room.orientation.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("\(room.floor)楼 · ¥\(Int(room.pricePerNight))/晚")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if room.status == .reserved {
                                        Text("已预订")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.15))
                                            .clipShape(Capsule())
                                    }

                                    if targetRoom?.id == room.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                // 价格调整
                if targetRoom != nil {
                    Section("房价") {
                        Toggle("调整房价", isOn: $adjustPrice)
                        if adjustPrice {
                            HStack {
                                Text("新房价 ¥")
                                TextField("每晚", text: $newDailyRate)
                                    .keyboardType(.numberPad)
                            }
                        } else if let target = targetRoom, let res = reservation {
                            let priceDiff = target.pricePerNight - res.dailyRate
                            HStack {
                                Text("房价变化")
                                Spacer()
                                Text(priceDiff == 0 ? "不变" : (priceDiff > 0 ? "+¥\(Int(priceDiff))/晚" : "-¥\(Int(abs(priceDiff)))/晚"))
                                    .foregroundStyle(priceDiff > 0 ? .red : (priceDiff < 0 ? .green : .secondary))
                            }
                        }
                    }
                }

                // 换房原因
                Section("换房原因（选填）") {
                    TextField("如：客人嫌吵、空调故障等", text: $reason)
                }

                // 错误
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("换房")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认换房") {
                        isSubmitting = true
                        Task { await performTransfer() }
                    }
                    .fontWeight(.bold)
                    .disabled(targetRoom == nil || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("换房中...").font(.caption).foregroundStyle(.white)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: - 执行换房

    @MainActor
    private func performTransfer() async {
        guard let target = targetRoom, let res = reservation else {
            errorMessage = "请选择目标房间"
            isSubmitting = false
            return
        }

        var latestTargetRoom = target
        var didUpdateReservation = false
        var didUpdateCurrentRoom = false
        var didUpdateTargetRoom = false

        do {
            latestTargetRoom = try await validateTransferState(targetRoomID: target.id)

            let newRate: Double
            if adjustPrice, let rate = Double(newDailyRate), rate > 0 {
                newRate = rate
            } else {
                newRate = latestTargetRoom.pricePerNight
            }

            // 1. 更新预订的 roomID 和房价
            var updatedRes = res
            updatedRes.roomID = target.id
            updatedRes.dailyRate = newRate
            try await service.saveReservation(updatedRes)
            didUpdateReservation = true

            // 2. 原房间 → 脏房
            try await service.updateRoomStatus(roomID: currentRoom.id, status: .cleaning)
            didUpdateCurrentRoom = true

            // 3. 新房间 → 已住
            try await service.updateRoomStatus(roomID: target.id, status: .occupied)
            didUpdateTargetRoom = true

            // 4. 押金记录不变（跟着 reservationID 走，不跟房间）

            // 5. 记录日志
            let guestName = res.guest?.name ?? "未知"
            logService.log(
                type: .roomStatusChange,
                summary: "\(guestName) 换房 \(currentRoom.roomNumber) → \(latestTargetRoom.roomNumber)",
                detail: "客人: \(guestName) | 原房: \(currentRoom.roomNumber)(\(currentRoom.roomType.rawValue) ¥\(Int(res.dailyRate))/晚) → 新房: \(latestTargetRoom.roomNumber)(\(latestTargetRoom.roomType.rawValue) ¥\(Int(newRate))/晚)\(reason.isEmpty ? "" : " | 原因: \(reason)")",
                roomNumber: latestTargetRoom.roomNumber
            )

            // 6. 刷新房间列表
            await roomListViewModel.loadRooms()

            isSubmitting = false
            onComplete()
        } catch {
            let rollbackFailures = await rollbackTransfer(
                reservation: res,
                targetRoomID: target.id,
                originalCurrentRoomStatus: currentRoom.status,
                originalTargetRoomStatus: latestTargetRoom.status,
                didUpdateReservation: didUpdateReservation,
                didUpdateCurrentRoom: didUpdateCurrentRoom,
                didUpdateTargetRoom: didUpdateTargetRoom
            )
            errorMessage = makeFailureMessage(error: error, rollbackFailures: rollbackFailures)
            if !rollbackFailures.isEmpty {
                logService.log(
                    type: .roomStatusChange,
                    summary: "\(currentRoom.roomNumber)房 换房回滚待核对",
                    detail: "换房失败后自动回滚未完全成功，需人工核对：\(rollbackFailures.joined(separator: "、")) | 原因: \(ErrorHelper.userMessage(error))",
                    roomNumber: currentRoom.roomNumber
                )
            }
            isSubmitting = false
        }
    }

    @MainActor
    private func validateTransferState(targetRoomID: String) async throws -> Room {
        if service.isReadOnlyMode {
            throw CloudKitMutationError.readOnlyProtection
        }

        let latestRooms = try await service.fetchAllRooms()
        guard let latestCurrent = latestRooms.first(where: { $0.id == currentRoom.id }),
              latestCurrent.status == .occupied else {
            throw RoomTransferError.currentRoomUnavailable(currentRoom.roomNumber)
        }
        guard let latestTarget = latestRooms.first(where: { $0.id == targetRoomID }),
              latestTarget.status == .vacant || latestTarget.status == .reserved else {
            throw RoomTransferError.targetRoomUnavailable(targetRoom?.roomNumber ?? "目标房间")
        }
        return latestTarget
    }

    @MainActor
    private func rollbackTransfer(
        reservation: Reservation,
        targetRoomID: String,
        originalCurrentRoomStatus: RoomStatus,
        originalTargetRoomStatus: RoomStatus,
        didUpdateReservation: Bool,
        didUpdateCurrentRoom: Bool,
        didUpdateTargetRoom: Bool
    ) async -> [String] {
        var failures: [String] = []

        if didUpdateTargetRoom {
            do {
                try await service.updateRoomStatus(roomID: targetRoomID, status: originalTargetRoomStatus)
            } catch {
                failures.append("目标房态恢复")
            }
        }
        if didUpdateCurrentRoom {
            do {
                try await service.updateRoomStatus(roomID: currentRoom.id, status: originalCurrentRoomStatus)
            } catch {
                failures.append("原房房态恢复")
            }
        }
        if didUpdateReservation {
            do {
                try await service.saveReservation(reservation)
            } catch {
                failures.append("入住记录恢复")
            }
        }

        return failures
    }

    private func makeFailureMessage(error: Error, rollbackFailures: [String]) -> String {
        let base = "换房失败: \(ErrorHelper.userMessage(error))"
        guard !rollbackFailures.isEmpty else { return base }
        return "\(base)。系统已尝试回滚，但以下项目仍需人工核对：\(rollbackFailures.joined(separator: "、"))。"
    }
}
