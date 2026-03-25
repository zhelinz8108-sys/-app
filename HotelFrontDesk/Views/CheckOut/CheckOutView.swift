import SwiftUI

struct CheckOutView: View {
    let room: Room
    @ObservedObject var viewModel: CheckOutViewModel
    @ObservedObject var roomListViewModel: RoomListViewModel
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let reservation = viewModel.reservation {
                        // 入住信息摘要
                        stayInfoCard(reservation: reservation)

                        // 退押金
                        DepositRefundView(viewModel: viewModel)

                        // 确认退房按钮
                        Button {
                            viewModel.isSubmitting = true
                            Task {
                                await viewModel.performCheckOut(roomID: room.id)
                                if viewModel.checkOutSuccess {
                                    await roomListViewModel.loadRooms()
                                    onComplete()
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if viewModel.isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 8)
                                }
                                Label("确认退房", systemImage: "door.right.hand.open")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding()
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(viewModel.isSubmitting)

                        // 提示：押金余额
                        if viewModel.depositSummary.balance > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("还有 ¥\(Int(viewModel.depositSummary.balance)) 押金未退，确认退房后仍可退还")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                    } else if viewModel.isLoading {
                        ProgressView("加载中...")
                            .padding(.top, 40)
                    } else {
                        ContentUnavailableView(
                            "无入住记录",
                            systemImage: "exclamationmark.triangle",
                            description: Text("该房间没有找到活跃的入住记录")
                        )
                    }

                    // 错误提示
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding()
            }
            .navigationTitle("办理退房 - \(room.roomNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - 入住信息卡片
    private func stayInfoCard(reservation: Reservation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("入住信息")
                    .font(.headline)
                Spacer()
                Text("房间 \(room.roomNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let guest = reservation.guest {
                infoRow(icon: "person.fill", label: "客人", value: guest.name)
                infoRow(icon: "phone.fill", label: "电话", value: guest.phone)
            }

            infoRow(icon: "calendar", label: "入住日期", value: reservation.checkInDate.chineseDate)
            infoRow(icon: "calendar.badge.clock", label: "预计退房", value: reservation.expectedCheckOut.chineseDate)

            Divider()

            HStack {
                Label("已住 \(reservation.nightsStayed) 晚", systemImage: "moon.fill")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                let rate = reservation.dailyRate > 0 ? reservation.dailyRate : room.pricePerNight
                let total = Double(reservation.nightsStayed) * rate
                Text("房费 ¥\(Int(total))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
