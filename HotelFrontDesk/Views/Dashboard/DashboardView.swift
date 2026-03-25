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
                VStack(spacing: 24) {
                    // Refined header
                    header

                    // 统计卡片
                    statsGrid

                    // 快捷操作
                    quickActions

                    // 今日预计退房
                    todayCheckOuts
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("酒店前台")
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
        }
        .padding(.top, 4)
    }

    // MARK: - 统计卡片网格
    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 14
        ) {
            StatCard(title: "总房数", value: "\(viewModel.totalRooms)", icon: "building", color: .appPrimary)
            StatCard(title: "已住", value: "\(viewModel.occupiedRooms)", icon: "person.fill", color: .roomOccupied)
            StatCard(title: "空房", value: "\(viewModel.vacantRooms)", icon: "door.left.hand.open", color: .roomVacant)
            StatCard(title: "已预订", value: "\(viewModel.reservedRooms)", icon: "bookmark.fill", color: .roomReserved)
            StatCard(title: "入住率", value: viewModel.occupancyPercent, icon: "chart.bar.fill", color: .appAccent)
            StatCard(title: "今日入住", value: "\(viewModel.todayCheckIns)", icon: "arrow.right.circle", color: .appPrimary)
            StatCard(title: "今日退房", value: "\(viewModel.todayExpectedCheckOuts.count)", icon: "arrow.left.circle", color: .appWarning)
            StatCard(title: "OTA预到", value: "\(OTABookingService.shared.todayArrivals.count)", icon: "calendar.badge.clock", color: .roomReserved)
        }
    }

    // MARK: - 快捷操作
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

    // MARK: - 今日预计退房
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
