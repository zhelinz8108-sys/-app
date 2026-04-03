import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var roomListVM = RoomListViewModel()
    @State private var showCheckIn = false
    @State private var showCheckOutPicker = false
    @State private var selectedCheckOutRoom: Room?

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "早上好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    header

                    // Occupancy gauge + Revenue side by side
                    HStack(spacing: 14) {
                        occupancyGauge
                        revenueCard
                    }

                    // Check-in / Check-out / ADR row
                    HStack(spacing: 14) {
                        kpiMiniCard(
                            title: "今日入住",
                            value: "\(viewModel.todayCheckIns)",
                            icon: "arrow.right.circle.fill",
                            color: .appSuccess
                        )
                        kpiMiniCard(
                            title: "预计退房",
                            value: "\(viewModel.expectedCheckOutCount)",
                            icon: "arrow.left.circle.fill",
                            color: .appWarning
                        )
                        kpiMiniCard(
                            title: "平均房价",
                            value: "¥\(viewModel.todayADRFormatted)",
                            icon: "yensign.circle.fill",
                            color: .appAccent
                        )
                    }

                    // Walk-in vs OTA
                    walkInOTACard

                    // Room status breakdown
                    roomStatusSection

                    // Room status grid (mini map)
                    roomMiniGrid

                    // Quick actions
                    quickActions

                    // Today's expected check-outs
                    todayCheckOuts

                    // Auto-refresh indicator
                    refreshIndicator
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("实时仪表盘")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.textPrimary)
                }
            }
            .refreshable {
                await viewModel.loadDashboard()
            }
            .task {
                await viewModel.loadDashboard()
                await roomListVM.loadRooms()
                viewModel.startAutoRefresh()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
            .fullScreenCover(isPresented: $showCheckIn) {
                CheckInView(roomListViewModel: roomListVM)
            }
            .sheet(isPresented: $showCheckOutPicker) {
                OccupiedRoomPickerView(rooms: roomListVM.rooms.filter { $0.status == .occupied }) { room in
                    selectedCheckOutRoom = room
                    showCheckOutPicker = false
                }
            }
            .sheet(item: $selectedCheckOutRoom) { room in
                CheckOutSheetView(room: room, roomListVM: roomListVM) {
                    selectedCheckOutRoom = nil
                    Task { await viewModel.loadDashboard() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.textPrimary)
                Text(dateText)
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
            }
            Spacer()
            // Live indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.appSuccess)
                    .frame(width: 6, height: 6)
                Text("实时")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.appSuccess.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.top, 4)
    }

    // MARK: - Occupancy Gauge

    private var occupancyGauge: some View {
        VStack(spacing: 10) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.appPrimary.opacity(0.08), lineWidth: 10)

                // Progress ring
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.occupancyRate))
                    .stroke(
                        viewModel.occupancyColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: viewModel.occupancyRate)

                // Center text
                VStack(spacing: 2) {
                    Text(viewModel.occupancyPercent)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.textPrimary)
                    Text("入住率")
                        .font(.caption2)
                        .foregroundStyle(.textSecondary)
                }
            }
            .frame(width: 100, height: 100)

            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(viewModel.occupiedRooms)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.roomOccupied)
                    Text("已住")
                        .font(.caption2)
                        .foregroundStyle(.textSecondary)
                }
                Rectangle()
                    .fill(Color.appPrimary.opacity(0.1))
                    .frame(width: 1, height: 24)
                VStack(spacing: 2) {
                    Text("\(viewModel.totalRooms)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("总房")
                        .font(.caption2)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.card)
    }

    // MARK: - Revenue Card

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "yensign.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.appAccent)
                Spacer()
                Text("今日")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("¥\(viewModel.todayRevenueFormatted)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.textPrimary)
                Text("收款金额")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            Divider()

            // OTA arrivals today
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.roomReserved)
                Text("OTA预到")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                Spacer()
                Text("\(OTABookingService.shared.todayArrivals.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.card)
    }

    // MARK: - KPI Mini Card

    private func kpiMiniCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .luxuryShadow(.subtle)
    }

    // MARK: - Walk-in vs OTA

    private var walkInOTACard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("散客 vs OTA")

            HStack(spacing: 14) {
                // Walk-in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.appPrimary)
                        .frame(width: 10, height: 10)
                    Text("散客")
                        .font(.subheadline)
                        .foregroundStyle(.textSecondary)
                    Spacer()
                    Text("\(viewModel.todayWalkInCount)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.textPrimary)
                }

                // OTA
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 10, height: 10)
                    Text("OTA")
                        .font(.subheadline)
                        .foregroundStyle(.textSecondary)
                    Spacer()
                    Text("\(viewModel.todayOTACount)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.textPrimary)
                }
            }

            // Ratio bar
            GeometryReader { geo in
                let total = viewModel.todayWalkInCount + viewModel.todayOTACount
                let walkInWidth = total > 0
                    ? geo.size.width * CGFloat(viewModel.todayWalkInCount) / CGFloat(total)
                    : geo.size.width * 0.5

                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appPrimary)
                        .frame(width: max(walkInWidth, 4))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appAccent)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.card)
    }

    // MARK: - Room Status Breakdown

    private var roomStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("房态一览")

            HStack(spacing: 0) {
                ForEach(viewModel.roomStatusBreakdown, id: \.status) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.status.icon)
                            .font(.body)
                            .foregroundStyle(item.color)

                        Text("\(item.count)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.textPrimary)

                        Text(item.status.displayName)
                            .font(.caption2)
                            .foregroundStyle(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)

            // Status bar
            GeometryReader { geo in
                let total = max(viewModel.totalRooms, 1)
                HStack(spacing: 2) {
                    ForEach(viewModel.roomStatusBreakdown, id: \.status) { item in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.color)
                            .frame(width: max(geo.size.width * CGFloat(item.count) / CGFloat(total), 4))
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.card)
    }

    // MARK: - Room Mini Grid

    private var roomMiniGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("房间状态图")

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(viewModel.allRooms.sorted { ($0.floor, $0.roomNumber) < ($1.floor, $1.roomNumber) }, id: \.id) { room in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(room.status.color)
                            .frame(height: 28)
                            .overlay {
                                Text(room.roomNumber)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                ForEach(RoomStatus.allCases) { status in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 6, height: 6)
                        Text(status.displayName)
                            .font(.caption2)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.card)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("快捷操作")

            HStack(spacing: 14) {
                Button {
                    showCheckIn = true
                } label: {
                    Label("办理入住", systemImage: "person.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appSuccess)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .luxuryShadow(.subtle)
                }

                Button {
                    showCheckOutPicker = true
                } label: {
                    Label("办理退房", systemImage: "door.right.hand.open")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appWarning)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .luxuryShadow(.subtle)
                }
            }
        }
    }

    // MARK: - Today Check-Outs

    private var todayCheckOuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("今日预计退房")

            if viewModel.todayExpectedCheckOuts.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(.appSuccess)
                        Text("今日暂无预计退房")
                            .font(.subheadline)
                            .foregroundStyle(.textSecondary)
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .luxuryShadow(.subtle)
            } else {
                ForEach(viewModel.todayExpectedCheckOuts) { reservation in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(reservation.room?.roomNumber ?? "?") 房")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(.textPrimary)
                            Text(reservation.guest?.name ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.textSecondary)
                        }
                        Spacer()
                        Text("入住 \(reservation.nightsStayed) 晚")
                            .font(.subheadline)
                            .foregroundStyle(.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.textSecondary.opacity(0.5))
                    }
                    .padding(16)
                    .background(Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .luxuryShadow(.subtle)
                }
            }
        }
    }

    // MARK: - Refresh Indicator

    private var refreshIndicator: some View {
        Group {
            if let lastRefresh = viewModel.lastRefreshed {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text("每30秒自动刷新")
                        .font(.caption2)
                    Text("·")
                    Text("上次: \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                }
                .foregroundStyle(.textSecondary.opacity(0.6))
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.appAccent)
                .frame(width: 4, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            Text(title)
                .font(.headline)
                .foregroundStyle(.textPrimary)
        }
    }
}

/// Wrapper that loads the reservation and shows CheckOutView directly
private struct CheckOutSheetView: View {
    let room: Room
    let roomListVM: RoomListViewModel
    var onComplete: () -> Void

    @StateObject private var checkOutVM = CheckOutViewModel()

    var body: some View {
        Group {
            if checkOutVM.isLoading {
                ProgressView("加载入住信息...")
            } else {
                CheckOutView(room: room, viewModel: checkOutVM, roomListViewModel: roomListVM, onComplete: onComplete)
            }
        }
        .task {
            await checkOutVM.loadReservation(forRoomID: room.id)
        }
    }
}

#Preview {
    DashboardView()
}
