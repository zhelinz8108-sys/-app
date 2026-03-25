import SwiftUI

/// OTA 预订管理页面
struct OTABookingListView: View {
    @ObservedObject private var bookingService = OTABookingService.shared
    @State private var showAdd = false
    @State private var selectedTab = 0 // 0=今日预到 1=未来 2=全部

    private let colorMap: [String: Color] = [
        "yellow": .yellow, "orange": .orange, "blue": .blue,
        "indigo": .indigo, "red": .red, "green": .green, "gray": .gray
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab 切换
                Picker("", selection: $selectedTab) {
                    Text("今日预到 (\(bookingService.todayArrivals.count))").tag(0)
                    Text("未来预订 (\(bookingService.upcomingBookings.count))").tag(1)
                    Text("全部 (\(bookingService.bookings.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // 列表
                List {
                    // 平台统计
                    if selectedTab == 2 && !bookingService.platformStats.isEmpty {
                        Section("平台统计") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(bookingService.platformStats) { stat in
                                        VStack(spacing: 4) {
                                            Image(systemName: stat.platform.icon)
                                                .font(.title3)
                                                .foregroundStyle(colorMap[stat.platform.color] ?? .gray)
                                            Text(stat.displayName)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                            Text("\(stat.count)单")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text("¥\(Int(stat.revenue))")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.blue)
                                        }
                                        .frame(width: 70)
                                        .padding(.vertical, 8)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                    }

                    // 预订列表
                    let displayBookings: [OTABooking] = {
                        switch selectedTab {
                        case 0: return bookingService.todayArrivals
                        case 1: return bookingService.upcomingBookings
                        default: return bookingService.bookings
                        }
                    }()

                    if displayBookings.isEmpty {
                        Section {
                            ContentUnavailableView(
                                selectedTab == 0 ? "今日无预到" : "暂无预订",
                                systemImage: "calendar",
                                description: Text("点击右上角 + 录入 OTA 订单")
                            )
                        }
                    } else {
                        Section {
                            ForEach(displayBookings) { booking in
                                bookingRow(booking)
                                    .swipeActions(edge: .trailing) {
                                        if booking.status == .confirmed {
                                            Button {
                                                bookingService.updateStatus(id: booking.id, status: .cancelled)
                                            } label: {
                                                Label("取消", systemImage: "xmark")
                                            }
                                            .tint(.red)

                                            Button {
                                                bookingService.updateStatus(id: booking.id, status: .noShow)
                                            } label: {
                                                Label("未到", systemImage: "person.slash")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("OTA 预订")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                OTABookingFormView()
            }
        }
    }

    // MARK: - 预订行

    private func bookingRow(_ booking: OTABooking) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：平台 + 客人 + 状态
            HStack {
                Image(systemName: booking.platform.icon)
                    .foregroundStyle(colorMap[booking.platform.color] ?? .gray)
                Text(booking.platformDisplayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((colorMap[booking.platform.color] ?? .gray).opacity(0.15))
                    .clipShape(Capsule())
                Text(booking.guestName)
                    .fontWeight(.medium)
                Spacer()
                Text(booking.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor(booking.status).opacity(0.15))
                    .foregroundStyle(statusColor(booking.status))
                    .clipShape(Capsule())
            }

            // 第二行：房型 + 日期 + 晚数
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "bed.double")
                        .font(.caption2)
                    Text(booking.roomType.rawValue)
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text("\(formatDate(booking.checkInDate)) 入住")
                        .font(.caption)
                }
                Text("\(booking.nights)晚")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)

            // 第三行：价格 + 分配房间 + 订单号
            HStack {
                Text("¥\(Int(booking.price))/晚 · 共¥\(Int(booking.totalPrice))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                Spacer()
                if let room = booking.assignedRoomNumber {
                    Text("已分房: \(room)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
                if !booking.platformOrderID.isEmpty {
                    Text("单号: \(booking.platformOrderID)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: BookingStatus) -> Color {
        switch status {
        case .pending: .orange
        case .confirmed: .blue
        case .checkedIn: .green
        case .cancelled: .red
        case .noShow: .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
