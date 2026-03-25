import SwiftUI

struct RoomGridView: View {
    @StateObject private var viewModel = RoomListViewModel()
    @State private var selectedRoom: Room?
    @State private var showCheckIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 楼层选择
                floorPicker

                // 状态筛选
                statusFilter

                // 房间网格
                ScrollView {
                    if viewModel.isLoading {
                        ProgressView("加载中...")
                            .padding(.top, 40)
                    } else if viewModel.filteredRooms.isEmpty {
                        ContentUnavailableView(
                            "暂无房间",
                            systemImage: "building.2",
                            description: Text("请在设置中初始化房间")
                        )
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(viewModel.filteredRooms) { room in
                                RoomCardView(room: room)
                                    .onTapGesture {
                                        selectedRoom = room
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
                .background(Color.appBackground)
                .refreshable {
                    await viewModel.loadRooms()
                }
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("房态管理")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.textPrimary)
                }
            }
            .sheet(item: $selectedRoom) { room in
                RoomDetailView(
                    room: room,
                    roomListViewModel: viewModel,
                    onCheckIn: {
                        selectedRoom = nil
                        showCheckIn = true
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCheckIn) {
                CheckInView(roomListViewModel: viewModel)
            }
            .task {
                await viewModel.loadRooms()
            }
            .alert("错误", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - 楼层选择器
    private var floorPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                floorChip(title: "全部", floor: nil)
                ForEach(viewModel.floors, id: \.self) { floor in
                    floorChip(title: "\(floor)楼", floor: floor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appCard)
    }

    private func floorChip(title: String, floor: Int?) -> some View {
        let isSelected = viewModel.selectedFloor == floor
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedFloor = floor
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(isSelected ? Color.appPrimary : Color.clear)
                .foregroundStyle(isSelected ? .white : .textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.textSecondary.opacity(0.2),
                            lineWidth: 1
                        )
                )
        }
    }

    // MARK: - 状态筛选
    private var statusFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusChip(title: "全部 \(viewModel.totalCount)", status: nil)
                ForEach(RoomStatus.allCases) { status in
                    let count = viewModel.rooms.filter { $0.status == status }.count
                    statusChip(title: "\(status.displayName) \(count)", status: status)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.appCard)
    }

    private func statusChip(title: String, status: RoomStatus?) -> some View {
        let isSelected = viewModel.selectedStatus == status
        let color = status?.color ?? .appPrimary
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedStatus = status
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color.opacity(0.12) : Color.clear)
                .foregroundStyle(isSelected ? color : .textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? color.opacity(0.3) : Color.textSecondary.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
    }
}

#Preview {
    RoomGridView()
}
