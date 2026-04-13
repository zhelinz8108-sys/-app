import SwiftUI

/// 入住办理错误
enum CheckInError: LocalizedError {
    case roomNoLongerVacant(String)
    case roomLockedByOther(String)

    var errorDescription: String? {
        switch self {
        case .roomNoLongerVacant(let num): return "\(num)房已被其他人办理入住，请选择其他房间"
        case .roomLockedByOther(let who): return "该房间正在被 \(who) 办理入住，请稍候或选择其他房间"
        }
    }
}

@MainActor
final class CheckInViewModel: ObservableObject {
    // 客人信息
    @Published var guestName = ""
    @Published var idType: IDType = .idCard
    @Published var idNumber = ""
    @Published var phone = ""
    @Published var guestNotes = ""
    @Published var guestEmail = ""
    @Published var numberOfGuests = 1

    // 房间选择
    @Published var selectedRoom: Room?

    // 入住类型
    @Published var isHourlyRoom = false  // 钟点房
    @Published var hourlyDuration = 3    // 钟点房时长（小时）
    static let hourlyOptions = [2, 3, 4, 5, 6] // 可选时长

    // 入住信息
    @Published var roomPrice: String = ""
    @Published var checkInDate = Date()
    @Published var expectedCheckOut = Date.tomorrow
    @Published var depositAmount: String = ""
    @Published var depositPaymentMethod: PaymentMethod = .cash

    /// 钟点房的预计退房时间
    var hourlyCheckOut: Date {
        Calendar.current.date(byAdding: .hour, value: hourlyDuration, to: checkInDate) ?? checkInDate
    }

    // 状态
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var checkInSuccess = false
    @Published var receiptImage: UIImage?  // POS小票照片
    var lastDepositID: String?             // 最近创建的押金ID（用于保存小票）

    /// 房间锁定中（异步加锁期间为 true）
    @Published var isLocking = false

    private let service = CloudKitService.shared
    private let logService = OperationLogService.shared
    private let lockService = RoomLockService.shared

    // MARK: - 表单验证
    /// 实际使用的退房时间（钟点房用小时计算）
    var effectiveCheckOut: Date {
        isHourlyRoom ? hourlyCheckOut : expectedCheckOut
    }

    /// 表单验证错误提示
    var validationErrors: [String] {
        var errors: [String] = []
        if guestName.trimmingCharacters(in: .whitespaces).isEmpty { errors.append("请填写客人姓名") }
        if phone.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("请填写手机号")
        } else if !Validators.isValidPhone(phone) {
            errors.append("手机号格式不正确（11位）")
        }
        if idNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("请填写证件号")
        } else if idType == .idCard && !Validators.isValidIDCard(idNumber) {
            errors.append("身份证号格式不正确（18位）")
        }
        if selectedRoom == nil { errors.append("请选择房间") }
        if effectiveCheckOut <= checkInDate { errors.append("退房时间必须晚于入住时间") }
        return errors
    }

    var isFormValid: Bool {
        validationErrors.isEmpty
    }

    var roomPriceValue: Double {
        Double(roomPrice) ?? 0
    }

    var depositValue: Double {
        Double(depositAmount) ?? 0
    }

    // MARK: - 选择房间时加锁

    /// 尝试选择房间（会尝试加锁，异步操作）
    func selectRoom(_ room: Room) async -> Bool {
        // 先同步检查是否被他人锁定（快速排除）
        if lockService.isLockedByOther(roomID: room.id) {
            let lockInfo = lockService.lockInfo(roomID: room.id)
            errorMessage = "该房间正在被 \(lockInfo?.staffName ?? "其他人") 办理入住，请稍候"
            return false
        }
        // 释放之前选中房间的锁
        if let prev = selectedRoom, prev.id != room.id {
            lockService.unlock(roomID: prev.id)
        }
        // 异步加锁（含 CloudKit 远端检查）
        isLocking = true
        let locked = await lockService.tryLock(roomID: room.id)
        isLocking = false

        if locked {
            selectedRoom = room
            roomPrice = String(Int(room.pricePerNight))
            errorMessage = nil
            return true
        } else {
            let lockInfo = lockService.lockInfo(roomID: room.id)
            errorMessage = "该房间正在被 \(lockInfo?.staffName ?? "其他人") 办理入住，请稍候"
            return false
        }
    }

    // MARK: - 执行入住（带并发检查 + 补偿回滚）
    func performCheckIn() async {
        guard isFormValid else {
            errorMessage = "请填写所有必填信息"
            return
        }
        guard let room = selectedRoom else { return }

        isSubmitting = true
        errorMessage = nil

        // ── 并发保护：最终一致性检查 ──
        // 重新获取房间最新状态，确认仍然是空房
        do {
            let currentRooms = try await service.fetchAllRooms()
            guard let latestRoom = currentRooms.first(where: { $0.id == room.id }) else {
                errorMessage = "房间不存在，请刷新后重试"
                isSubmitting = false
                return
            }
            if latestRoom.status != .vacant && latestRoom.status != .reserved {
                lockService.unlock(roomID: room.id)
                throw CheckInError.roomNoLongerVacant(room.roomNumber)
            }
        } catch let e as CheckInError {
            errorMessage = e.localizedDescription
            isSubmitting = false
            return
        } catch {
            errorMessage = "检查房态失败: \(ErrorHelper.userMessage(error))"
            isSubmitting = false
            return
        }

        // ── 正式办理入住 ──
        var savedGuestID: String?
        var savedReservationID: String?
        var savedDepositID: String?

        do {
            // 1. 创建客人记录
            let trimmedGuestName = guestName.trimmingCharacters(in: .whitespaces)
            let trimmedIDNumber = idNumber.trimmingCharacters(in: .whitespaces)
            let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
            let guestID = UUID().uuidString
            let trimmedEmail = guestEmail.trimmingCharacters(in: .whitespaces)
            let guest = Guest(
                id: guestID,
                name: trimmedGuestName,
                idType: idType,
                idNumber: trimmedIDNumber,
                phone: trimmedPhone,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                notes: guestNotes.isEmpty ? nil : guestNotes
            )
            try await service.saveGuest(guest)
            savedGuestID = guestID

            // 2. 创建入住记录
            let reservationID = UUID().uuidString
            let reservation = Reservation(
                id: reservationID,
                guestID: guestID,
                roomID: room.id,
                checkInDate: checkInDate,
                expectedCheckOut: effectiveCheckOut,
                isActive: true,
                numberOfGuests: numberOfGuests,
                dailyRate: roomPriceValue > 0
                    ? roomPriceValue
                    : (isHourlyRoom
                        ? room.pricePerNight * 0.5 // 钟点房默认半价
                        : PricingService.shared.averageNightlyRate(room: room, checkIn: checkInDate, checkOut: expectedCheckOut))
            )
            try await service.saveReservation(reservation)
            savedReservationID = reservationID

            // 3. 如果有押金，创建押金记录
            if depositValue > 0 {
                let depositID = UUID().uuidString
                let deposit = DepositRecord(
                    id: depositID,
                    reservationID: reservationID,
                    type: .collect,
                    amount: depositValue,
                    paymentMethod: depositPaymentMethod,
                    timestamp: Date()
                )
                try await service.saveDepositRecord(deposit)
                savedDepositID = depositID
                lastDepositID = depositID
                // 保存POS小票照片
                if let image = receiptImage {
                    _ = ReceiptImageService.save(depositID: depositID, image: image)
                }
            }

            // 4. 更新房间状态为已住
            try await service.updateRoomStatus(roomID: room.id, status: .occupied)

            // 5. 释放房间锁
            lockService.unlock(roomID: room.id)

            // 6. 记录日志
            let rate = roomPriceValue > 0
                ? roomPriceValue
                : (isHourlyRoom ? room.pricePerNight * 0.5 : room.pricePerNight)
            let stayDesc = isHourlyRoom ? "钟点房\(hourlyDuration)小时" : "预住\(Calendar.current.dateComponents([.day], from: checkInDate, to: effectiveCheckOut).day ?? 1)晚"
            let maskedDocument = switch idType {
            case .idCard:
                Validators.maskedIDCard(trimmedIDNumber)
            default:
                Validators.maskedSensitive(trimmedIDNumber)
            }
            let maskedPhone = Validators.maskedPhone(trimmedPhone) != trimmedPhone
                ? Validators.maskedPhone(trimmedPhone)
                : Validators.maskedSensitive(trimmedPhone)
            logService.log(
                type: .checkIn,
                summary: "\(room.roomNumber)房 \(trimmedGuestName) \(isHourlyRoom ? "钟点房" : "入住")",
                detail: "客人: \(trimmedGuestName) | 证件: \(maskedDocument) | 电话: \(maskedPhone) | 房型: \(room.roomType.rawValue) | \(isHourlyRoom ? "钟点房 \(hourlyDuration)小时 | 房价: ¥\(Int(rate))" : "房价: ¥\(Int(rate))/晚 | \(stayDesc)") | 押金: ¥\(Int(depositValue)) | 入住人数: \(numberOfGuests)",
                roomNumber: room.roomNumber
            )
            if depositValue > 0 {
                logService.log(
                    type: .depositCollect,
                    summary: "\(room.roomNumber)房 收取押金 ¥\(Int(depositValue))",
                    detail: "客人: \(trimmedGuestName) | 金额: ¥\(Int(depositValue))",
                    roomNumber: room.roomNumber
                )
            }

            checkInSuccess = true
        } catch {
            // 补偿回滚
            let rollbackFailures = await rollback(
                guestID: savedGuestID,
                reservationID: savedReservationID,
                depositID: savedDepositID,
                roomID: room.id,
                originalStatus: room.status
            )
            lockService.unlock(roomID: room.id)
            errorMessage = makeFailureMessage(
                action: "入住办理失败",
                error: error,
                rollbackFailures: rollbackFailures
            )
            if !rollbackFailures.isEmpty {
                logService.log(
                    type: .roomStatusChange,
                    summary: "\(room.roomNumber)房 入住回滚待核对",
                    detail: "办理入住失败后自动回滚未完全成功，需人工核对：\(rollbackFailures.joined(separator: "、")) | 原因: \(ErrorHelper.userMessage(error))",
                    roomNumber: room.roomNumber
                )
            }
        }

        isSubmitting = false
    }

    /// 回滚已完成的入住步骤
    private func rollback(
        guestID: String?,
        reservationID: String?,
        depositID: String?,
        roomID: String,
        originalStatus: RoomStatus
    ) async -> [String] {
        var failures: [String] = []

        if let depositID {
            do {
                try await service.deleteDeposit(id: depositID)
            } catch {
                failures.append("押金记录")
            }
        }
        if let reservationID {
            do {
                try await service.deleteReservation(id: reservationID)
            } catch {
                failures.append("入住记录")
            }
        }
        if let guestID {
            do {
                try await service.deleteGuest(id: guestID)
            } catch {
                failures.append("客人档案")
            }
        }
        do {
            try await service.updateRoomStatus(roomID: roomID, status: originalStatus)
        } catch {
            failures.append("房态恢复")
        }

        return failures
    }

    private func makeFailureMessage(action: String, error: Error, rollbackFailures: [String]) -> String {
        let base = "\(action): \(ErrorHelper.userMessage(error))"
        guard !rollbackFailures.isEmpty else { return base }
        return "\(base)。系统已尝试回滚，但以下项目仍需人工核对：\(rollbackFailures.joined(separator: "、"))。"
    }

    // MARK: - 重置表单
    func reset() {
        // 释放房间锁
        if let room = selectedRoom {
            lockService.unlock(roomID: room.id)
        }
        guestName = ""
        idType = .idCard
        idNumber = ""
        phone = ""
        guestNotes = ""
        guestEmail = ""
        numberOfGuests = 1
        isHourlyRoom = false
        hourlyDuration = 3
        selectedRoom = nil
        roomPrice = ""
        checkInDate = Date()
        expectedCheckOut = Date.tomorrow
        depositAmount = ""
        depositPaymentMethod = .cash
        isSubmitting = false
        isLocking = false
        errorMessage = nil
        checkInSuccess = false
    }
}
