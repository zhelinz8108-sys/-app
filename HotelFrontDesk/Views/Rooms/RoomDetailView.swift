import SwiftUI

struct RoomDetailView: View {
    let room: Room
    @ObservedObject var roomListViewModel: RoomListViewModel
    var onCheckIn: () -> Void

    @StateObject private var checkOutVM = CheckOutViewModel()
    @State private var showCheckOut = false
    @State private var showExtendStay = false
    @State private var extendDate = Date.tomorrow
    @State private var showRoomTransfer = false
    @State private var historyRecords: [Reservation] = []
    @State private var isLoadingHistory = false
    @State private var pendingStatus: RoomStatus?
    @State private var showStatusConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 房间头部信息
                    roomHeader

                    // 当前状态切换
                    statusToggle

                    // 如果已住，显示客人和押金信息
                    if room.status == .occupied {
                        if checkOutVM.isLoading {
                            ProgressView("加载入住信息...")
                                .padding()
                        } else if let reservation = checkOutVM.reservation {
                            guestInfo(reservation: reservation)
                            depositSection
                        }
                    }

                    // 历史入住记录
                    historySection

                    // 操作按钮
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("房间 \(room.roomNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if room.status == .occupied {
                    await checkOutVM.loadReservation(forRoomID: room.id)
                }
                await loadHistory()
            }
            .sheet(isPresented: $showCheckOut) {
                CheckOutView(room: room, viewModel: checkOutVM, roomListViewModel: roomListViewModel) {
                    showCheckOut = false
                    dismiss()
                }
            }
            .alert("申请延住", isPresented: $showExtendStay) {
                Button("延1天") { submitExtend(days: 1) }
                Button("延2天") { submitExtend(days: 2) }
                Button("延3天") { submitExtend(days: 3) }
                Button("取消", role: .cancel) {}
            } message: {
                if let res = checkOutVM.reservation {
                    Text("客人: \(res.guest?.name ?? "未知")\n当前预计退房: \(res.expectedCheckOut.chineseDate)\n选择延住天数（需管理员审批）")
                }
            }
            .sheet(isPresented: $showRoomTransfer) {
                RoomTransferView(
                    currentRoom: room,
                    reservation: checkOutVM.reservation,
                    depositRecords: checkOutVM.depositRecords,
                    roomListViewModel: roomListViewModel
                ) {
                    showRoomTransfer = false
                    dismiss()
                }
            }
        }
    }

    private func submitExtend(days: Int) {
        guard let res = checkOutVM.reservation,
              let newCheckOut = Calendar.current.date(byAdding: .day, value: days, to: res.expectedCheckOut) else { return }
        NightAuditService.shared.requestExtend(
            reservation: res,
            newCheckOut: newCheckOut,
            requestedBy: StaffService.shared.currentName
        )
    }

    // MARK: - 房间头部
    private var roomHeader: some View {
        VStack(spacing: 12) {
            Text(room.roomNumber)
                .font(.system(size: 48, weight: .bold))

            HStack(spacing: 16) {
                Label(room.roomType.rawValue, systemImage: "bed.double")
                Label(room.orientation.rawValue, systemImage: "compass.drawing")
                Label("\(room.floor)楼", systemImage: "building")
                Label("¥\(Int(room.pricePerNight))/晚", systemImage: "yensign")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            RoomStatusBadge(status: room.status)

            if let notes = room.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 状态切换
    private var statusToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速切换状态")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(RoomStatus.allCases) { status in
                    Button {
                        pendingStatus = status
                        showStatusConfirm = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: status.icon)
                            Text(status.displayName)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(room.status == status ? status.color.opacity(0.2) : Color(.tertiarySystemBackground))
                        .foregroundStyle(room.status == status ? status.color : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(room.status == status)
                }
            }
        }
        .alert("确认修改状态", isPresented: $showStatusConfirm) {
            Button("取消", role: .cancel) {
                pendingStatus = nil
            }
            Button("确定") {
                if let status = pendingStatus {
                    Task {
                        await roomListViewModel.updateStatus(for: room, to: status)
                        dismiss()
                    }
                }
            }
        } message: {
            if let status = pendingStatus {
                Text("确定将房间 \(room.roomNumber) 从「\(room.status.displayName)」改为「\(status.displayName)」吗？")
            }
        }
    }

    // MARK: - 客人信息
    private func guestInfo(reservation: Reservation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("入住信息")
                .font(.headline)

            if let guest = reservation.guest {
                infoRow(label: "客人", value: guest.name)
                infoRow(label: "证件", value: "\(guest.idType.rawValue) \(Validators.maskedIDCard(guest.idNumber))")
                infoRow(label: "电话", value: guest.phone)
            }
            infoRow(label: "入住日期", value: reservation.checkInDate.chineseDate)
            infoRow(label: "预计退房", value: reservation.expectedCheckOut.chineseDate)
            infoRow(label: "已住天数", value: "\(reservation.nightsStayed) 晚")
            infoRow(label: "入住人数", value: "\(reservation.numberOfGuests) 人")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 押金区域
    private var depositSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("押金信息")
                .font(.headline)

            let summary = checkOutVM.depositSummary

            HStack(spacing: 16) {
                depositCard(title: "已收", amount: summary.totalCollected, color: .depositCollected)
                depositCard(title: "已退", amount: summary.totalRefunded, color: .depositRefunded)
                depositCard(title: "余额", amount: summary.balance, color: .depositBalance)
            }

            // 押金明细
            if !checkOutVM.depositRecords.isEmpty {
                Divider()
                Text("押金明细")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(checkOutVM.depositRecords) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: record.type == .collect ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(record.type == .collect ? .blue : .green)
                            Text(record.type.rawValue)
                            Text(record.paymentMethod.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                            Spacer()
                            Text(record.type == .collect ? "+¥\(Int(record.amount))" : "-¥\(Int(record.amount))")
                                .fontWeight(.medium)
                                .foregroundStyle(record.type == .collect ? .blue : .green)
                            Text(record.timestamp.chineseDateTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        // POS小票照片 — lazy load only when tapped
                        if ReceiptImageService.exists(depositID: record.id) {
                            ReceiptThumbnailLazyView(depositID: record.id)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func depositCard(title: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("¥\(Int(amount))")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 操作按钮
    private var actionButtons: some View {
        Group {
            if room.status == .vacant || room.status == .reserved {
                Button {
                    onCheckIn()
                } label: {
                    Label("办理入住", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if room.status == .occupied {
                Button {
                    showCheckOut = true
                } label: {
                    Label("办理退房", systemImage: "door.right.hand.open")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                HStack(spacing: 10) {
                    // 换房按钮
                    Button {
                        showRoomTransfer = true
                    } label: {
                        Label("换房", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 延住按钮
                    Button {
                        showExtendStay = true
                    } label: {
                        Label("延住", systemImage: "calendar.badge.plus")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.purple.opacity(0.12))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: - 历史入住记录（日历视图）
    private var historySection: some View {
        Group {
            if isLoadingHistory {
                VStack {
                    ProgressView("加载历史记录...")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoomHistoryCalendarView(historyRecords: historyRecords, room: room)
            }
        }
    }

    // MARK: - 加载历史记录
    private func loadHistory() async {
        isLoadingHistory = true
        do {
            historyRecords = try await CloudKitService.shared.fetchReservationHistory(forRoomID: room.id)
            print("📋 房间\(room.roomNumber) 加载到 \(historyRecords.count) 条历史记录")
            // 对于没有存 dailyRate 的旧记录，用房间当前价格补上
            for i in historyRecords.indices {
                if historyRecords[i].dailyRate == 0 {
                    historyRecords[i].dailyRate = room.pricePerNight
                }
            }
        } catch {
            print("❌ 加载历史记录失败: \(error)")
        }
        isLoadingHistory = false
    }

    // MARK: - 辅助
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
