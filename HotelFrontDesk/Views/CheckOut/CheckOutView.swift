import SwiftUI
import MessageUI

struct CheckOutView: View {
    let room: Room
    @ObservedObject var viewModel: CheckOutViewModel
    @ObservedObject var roomListViewModel: RoomListViewModel
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var invoiceURL: URL?
    @State private var showShareSheet = false
    @State private var isGeneratingInvoice = false
    @State private var showMailComposer = false
    @State private var showMailUnavailableAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.checkOutSuccess {
                        // 退房成功界面
                        checkOutSuccessView

                    } else if let reservation = viewModel.reservation {
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
                    if viewModel.checkOutSuccess {
                        Button("完成") {
                            onComplete()
                        }
                    } else {
                        Button("取消") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = invoiceURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showMailComposer) {
                if let url = invoiceURL, let reservation = viewModel.reservation {
                    let hotelName = UserDefaults.standard.string(forKey: "hotelName") ?? "酒店"
                    let roomNumber = reservation.room?.roomNumber ?? room.roomNumber
                    MailComposerView(
                        subject: "【\(hotelName)】住宿收据 - \(roomNumber)房",
                        body: """
                        尊敬的\(reservation.guest?.name ?? "客人")，您好！

                        感谢您选择入住\(hotelName)，以下是您的住宿收据，请查收。

                        房间号：\(roomNumber)
                        入住日期：\(reservation.checkInDate.chineseDate)
                        退房日期：\((reservation.actualCheckOut ?? reservation.expectedCheckOut).chineseDate)

                        如有任何疑问，请随时联系我们。
                        祝您生活愉快！

                        \(hotelName)
                        """,
                        recipients: reservation.guest?.email.map { [$0] } ?? [],
                        attachmentURL: url,
                        attachmentMimeType: "application/pdf"
                    ) { _ in
                        showMailComposer = false
                    }
                }
            }
            .alert("无法发送邮件", isPresented: $showMailUnavailableAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("此设备未配置邮件账户，请在系统设置中添加邮件账户后重试。")
            }
        }
    }

    // MARK: - 退房成功界面
    private var checkOutSuccessView: some View {
        VStack(spacing: 20) {
            // 成功图标
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 20)

            Text("退房成功")
                .font(.title2)
                .fontWeight(.bold)

            if let reservation = viewModel.reservation {
                VStack(spacing: 8) {
                    Text("房间 \(room.roomNumber) · \(reservation.guest?.name ?? "客人")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("共住 \(reservation.nightsStayed) 晚 · 房费 ¥\(Int(reservation.totalRevenue))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.horizontal)

            // 生成收据按钮
            Button {
                generateInvoice()
            } label: {
                HStack {
                    Spacer()
                    if isGeneratingInvoice {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 8)
                    }
                    Label("生成收据", systemImage: "doc.text")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isGeneratingInvoice)

            // 已生成收据后，显示分享和邮件按钮
            if invoiceURL != nil {
                HStack(spacing: 12) {
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("分享/打印", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        sendInvoiceEmail()
                    } label: {
                        HStack {
                            Spacer()
                            Label("发送到邮箱", systemImage: "envelope")
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            // 完成按钮
            Button {
                onComplete()
            } label: {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 8)
        }
    }

    // MARK: - 生成收据
    private func generateInvoice() {
        guard let reservation = viewModel.reservation else { return }
        isGeneratingInvoice = true
        Task {
            let url = await InvoiceGenerator.generateInvoice(
                reservation: reservation,
                depositRecords: viewModel.depositRecords
            )
            invoiceURL = url
            isGeneratingInvoice = false
            showShareSheet = true
        }
    }

    // MARK: - 发送收据邮件
    private func sendInvoiceEmail() {
        guard MFMailComposeViewController.canSendMail() else {
            showMailUnavailableAlert = true
            return
        }
        showMailComposer = true
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
