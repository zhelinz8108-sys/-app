import SwiftUI
import MessageUI

// MARK: - 历史入住日历视图
struct RoomHistoryCalendarView: View {
    let historyRecords: [Reservation]
    let room: Room

    @State private var displayedMonth = Date()
    @State private var selectedReservation: Reservation?
    @State private var showGuestPopup = false
    @State private var popoverAnchor: CGPoint = .zero
    @State private var cachedDateReservationMap: [String: Reservation] = [:]
    @State private var invoiceURL: URL?
    @State private var showShareSheet = false
    @State private var isGeneratingInvoice = false
    @State private var showMailComposer = false
    @State private var showMailUnavailableAlert = false
    @State private var mailReservation: Reservation?

    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    // Cached date -> reservation mapping
    private var dateReservationMap: [String: Reservation] { cachedDateReservationMap }

    private func buildDateReservationMap() -> [String: Reservation] {
        var map: [String: Reservation] = [:]
        for res in historyRecords {
            let endDate = res.actualCheckOut ?? res.expectedCheckOut
            var current = res.checkInDate
            while current < endDate {
                let key = dateKey(current)
                map[key] = res
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
        }
        return map
    }

    var body: some View {
        VStack(spacing: 12) {
            // 标题 + 统计
            HStack {
                Label("历史入住记录", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                if !historyRecords.isEmpty {
                    Text("共 \(historyRecords.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !historyRecords.isEmpty {
                // 统计汇总
                let totalRevenue = historyRecords.reduce(0) { $0 + $1.totalRevenue }
                let totalNights = historyRecords.reduce(0) { $0 + $1.nightsStayed }

                HStack(spacing: 12) {
                    statCard(title: "总收入", value: "¥\(Int(totalRevenue))", color: .blue)
                    statCard(title: "总晚数", value: "\(totalNights) 晚", color: .green)
                    statCard(title: "均价", value: totalNights > 0 ? "¥\(Int(Double(totalRevenue) / Double(totalNights)))/晚" : "-", color: .orange)
                }
            }

            Divider()

            // 月份切换
            HStack {
                Button {
                    withAnimation { changeMonth(-1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation { changeMonth(1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.medium)
                }
                .disabled(isCurrentMonth)
            }
            .padding(.horizontal, 4)

            // 星期标题行
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 日期网格
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }

            // 图例
            HStack(spacing: 16) {
                legendItem(color: .blue, text: "有入住")
                legendItem(color: .clear, text: "空闲")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // 点击日期后的内联详情卡片
            if showGuestPopup, let res = selectedReservation {
                guestDetailCard(reservation: res)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: showGuestPopup)
        .onAppear { cachedDateReservationMap = buildDateReservationMap() }
        .onChange(of: historyRecords.map(\.id)) {
            cachedDateReservationMap = buildDateReservationMap()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = invoiceURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showMailComposer) {
            if let url = invoiceURL, let res = mailReservation {
                let hotelName = UserDefaults.standard.string(forKey: "hotelName") ?? "酒店"
                let roomNumber = res.room?.roomNumber ?? room.roomNumber
                MailComposerView(
                    subject: "【\(hotelName)】住宿收据 - \(roomNumber)房",
                    body: """
                    尊敬的\(res.guest?.name ?? "客人")，您好！

                    感谢您选择入住\(hotelName)，以下是您的住宿收据，请查收。

                    房间号：\(roomNumber)
                    入住日期：\(res.checkInDate.chineseDate)
                    退房日期：\((res.actualCheckOut ?? res.expectedCheckOut).chineseDate)

                    如有任何疑问，请随时联系我们。
                    祝您生活愉快！

                    \(hotelName)
                    """,
                    recipients: res.guest?.email.map { [$0] } ?? [],
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

    // MARK: - 日期单元格
    @ViewBuilder
    private func dayCell(_ day: DateComponents) -> some View {
        if let dayNum = day.day, let date = calendar.date(from: day) {
            let key = dateKey(date)
            let reservation = dateReservationMap[key]
            let isOccupied = reservation != nil
            let isToday = calendar.isDateInToday(date)
            let isFuture = date > Date()

            Button {
                if let res = reservation {
                    if selectedReservation?.id == res.id && showGuestPopup {
                        // 再次点击同一天：收起
                        showGuestPopup = false
                        selectedReservation = nil
                    } else {
                        selectedReservation = res
                        showGuestPopup = true
                    }
                }
            } label: {
                Text("\(dayNum)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(
                        isFuture ? Color.gray.opacity(0.3) :
                        isOccupied ? Color.white :
                        isToday ? Color.blue : Color.primary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        Group {
                            if isOccupied {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.8))
                            } else if isToday {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 1.5)
                            }
                        }
                    )
            }
            .disabled(!isOccupied)
        } else {
            // 空白占位
            Text("")
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
    }

    // MARK: - 内联客人详情卡片
    private func guestDetailCard(reservation: Reservation) -> some View {
        VStack(spacing: 0) {
            // 标题栏 + 关闭按钮
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.guest?.name ?? "未知客人")
                        .font(.title3)
                        .fontWeight(.bold)
                    if let guest = reservation.guest {
                        Text(guest.phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showGuestPopup = false
                    selectedReservation = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            Divider()

            // 详细信息
            VStack(spacing: 8) {
                if let guest = reservation.guest {
                    popupRow(icon: "creditcard", label: "证件号", value: guest.idNumber)
                    popupRow(icon: "doc.text", label: "证件类型", value: guest.idType.rawValue)
                }
                popupRow(icon: "calendar", label: "入住日期", value: reservation.checkInDate.chineseDate)
                popupRow(icon: "calendar.badge.clock", label: "退房日期", value: (reservation.actualCheckOut ?? reservation.expectedCheckOut).chineseDate)
                popupRow(icon: "moon.fill", label: "住了", value: "\(reservation.nightsStayed) 晚")
                popupRow(icon: "person.2", label: "入住人数", value: "\(reservation.numberOfGuests) 人")
            }
            .padding(.vertical, 10)

            Divider()

            // 费用
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("每晚房费")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("¥\(Int(reservation.dailyRate))")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 36)

                VStack(spacing: 2) {
                    Text("总房费")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("¥\(Int(reservation.totalRevenue))")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 查看收据 + 发送邮件按钮
            if !reservation.isActive {
                HStack(spacing: 10) {
                    Button {
                        generateHistoryInvoice(reservation: reservation)
                    } label: {
                        HStack {
                            Spacer()
                            if isGeneratingInvoice {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Label("查看收据", systemImage: "doc.text")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isGeneratingInvoice)

                    Button {
                        sendHistoryInvoiceEmail(reservation: reservation)
                    } label: {
                        HStack {
                            Spacer()
                            Label("发送到邮箱", systemImage: "envelope")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isGeneratingInvoice)
                }
                .padding(.top, 10)
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    // MARK: - 生成历史收据
    private func generateHistoryInvoice(reservation: Reservation) {
        isGeneratingInvoice = true
        Task {
            do {
                let url = try await InvoiceGenerator.generateInvoiceForHistory(reservation: reservation)
                invoiceURL = url
                showShareSheet = true
            } catch {
                print("生成收据失败: \(error)")
            }
            isGeneratingInvoice = false
        }
    }

    // MARK: - 发送历史收据邮件
    private func sendHistoryInvoiceEmail(reservation: Reservation) {
        guard MFMailComposeViewController.canSendMail() else {
            showMailUnavailableAlert = true
            return
        }
        isGeneratingInvoice = true
        Task {
            do {
                let url = try await InvoiceGenerator.generateInvoiceForHistory(reservation: reservation)
                invoiceURL = url
                mailReservation = reservation
                showMailComposer = true
            } catch {
                print("生成收据失败: \(error)")
            }
            isGeneratingInvoice = false
        }
    }

    private func popupRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    // MARK: - 辅助组件

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color == .clear ? Color(.tertiarySystemFill) : color.opacity(0.8))
                .frame(width: 12, height: 12)
            Text(text)
        }
    }

    // MARK: - 日历计算

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var isCurrentMonth: Bool {
        let now = Date()
        return calendar.component(.year, from: displayedMonth) == calendar.component(.year, from: now)
            && calendar.component(.month, from: displayedMonth) == calendar.component(.month, from: now)
    }

    private func changeMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func daysInMonth() -> [DateComponents] {
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)

        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) // 1=Sunday
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count

        var days: [DateComponents] = []

        // 前面的空白
        for _ in 0..<(firstWeekday - 1) {
            days.append(DateComponents()) // 空
        }

        // 每天
        for day in 1...daysInMonth {
            days.append(DateComponents(year: year, month: month, day: day))
        }

        return days
    }

    private func dateKey(_ date: Date) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(y)-\(m)-\(d)"
    }
}
