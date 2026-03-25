import SwiftUI

struct RoomPickerView: View {
    let vacantRooms: [Room]
    @Binding var selectedRoom: Room?
    var onSelectRoom: ((Room) -> Bool)? // 返回 false 表示锁定失败

    @ObservedObject private var lockService = RoomLockService.shared
    @State private var showPicker = false
    @State private var selectedType: RoomType? = nil
    @State private var lockError: String?

    // 按户型筛选
    private var filteredRooms: [Room] {
        let rooms = selectedType == nil ? vacantRooms : vacantRooms.filter { $0.roomType == selectedType }
        return rooms.sorted { $0.roomNumber > $1.roomNumber }
    }

    // 按楼层分组
    private var groupedByFloor: [(floor: Int, rooms: [Room])] {
        Dictionary(grouping: filteredRooms) { $0.floor }
            .sorted { $0.key > $1.key }
            .map { (floor: $0.key, rooms: $0.value.sorted { $0.roomNumber > $1.roomNumber }) }
    }

    private func countForType(_ type: RoomType) -> Int {
        vacantRooms.filter { $0.roomType == type }.count
    }

    var body: some View {
        Section("选择房间") {
            Button {
                lockError = nil
                showPicker = true
            } label: {
                HStack {
                    if let room = selectedRoom {
                        HStack(spacing: 8) {
                            Text(room.roomNumber)
                                .font(.title3.bold())
                                .foregroundStyle(Color.appPrimary)
                            Text(room.roomType.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(room.floor)楼")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(room.orientation.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("¥\(Int(room.pricePerNight))/晚")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("点击选择空房")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("空房 \(vacantRooms.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .sheet(isPresented: $showPicker) {
            roomPickerSheet
        }
    }

    // MARK: - 房间选择弹窗
    private var roomPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 锁定提示
                if let error = lockError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                }

                // 户型筛选标签
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        typeChip(label: "全部", type: nil, count: vacantRooms.count)
                        ForEach(RoomType.allCases) { type in
                            typeChip(label: type.rawValue, type: type, count: countForType(type))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))

                // 房间列表
                if groupedByFloor.isEmpty {
                    Spacer()
                    Text("该类型暂无空房")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(groupedByFloor, id: \.floor) { group in
                            Section("\(group.floor)楼 · \(group.rooms.count)间空房") {
                                ForEach(group.rooms) { room in
                                    roomRow(room)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            handleRoomTap(room)
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("选择房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showPicker = false }
                }
            }
        }
    }

    private func handleRoomTap(_ room: Room) {
        lockError = nil
        if let onSelect = onSelectRoom {
            if onSelect(room) {
                showPicker = false
            } else {
                let info = lockService.lockInfo(roomID: room.id)
                lockError = "\(room.roomNumber)房正在被 \(info?.staffName ?? "其他人") 办理，请选择其他房间"
            }
        } else {
            selectedRoom = room
            showPicker = false
        }
    }

    // MARK: - 户型筛选 chip
    private func typeChip(label: String, type: RoomType?, count: Int) -> some View {
        let isActive = selectedType == type
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isActive ? Color.white.opacity(0.3) : Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isActive ? Color.appPrimary : Color(.secondarySystemBackground))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - 房间行
    private func roomRow(_ room: Room) -> some View {
        let isSelected = selectedRoom?.id == room.id
        let isLocked = lockService.isLockedByOther(roomID: room.id)
        let lockInfo = lockService.lockInfo(roomID: room.id)

        return HStack(spacing: 12) {
            Text(room.roomNumber)
                .font(.title2.bold())
                .foregroundStyle(isLocked ? .gray : (isSelected ? Color.appPrimary : .primary))
                .frame(width: 60)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(room.roomType.rawValue)
                        .font(.subheadline)
                    Text(room.orientation.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isLocked, let info = lockInfo {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("\(info.staffName) 正在办理")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                } else if let notes = room.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("¥\(Int(room.pricePerNight))")
                .font(.headline)
                .foregroundStyle(isLocked ? .gray : .orange)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appPrimary)
                    .font(.title3)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.appPrimary.opacity(0.08) : (isLocked ? Color.orange.opacity(0.05) : nil))
    }
}
