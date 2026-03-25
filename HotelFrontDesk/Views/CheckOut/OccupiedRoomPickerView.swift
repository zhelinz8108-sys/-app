import SwiftUI

/// 退房时选择已入住的房间
struct OccupiedRoomPickerView: View {
    let rooms: [Room]
    let onSelect: (Room) -> Void
    @Environment(\.dismiss) private var dismiss

    // 按楼层分组
    private var groupedByFloor: [(floor: Int, rooms: [Room])] {
        Dictionary(grouping: rooms) { $0.floor }
            .sorted { $0.key > $1.key }
            .map { (floor: $0.key, rooms: $0.value.sorted { $0.roomNumber < $1.roomNumber }) }
    }

    var body: some View {
        NavigationStack {
            if rooms.isEmpty {
                ContentUnavailableView(
                    "没有已入住的房间",
                    systemImage: "bed.double",
                    description: Text("当前没有在住客人")
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                }
            } else {
                List {
                    ForEach(groupedByFloor, id: \.floor) { group in
                        Section("\(group.floor)楼 · \(group.rooms.count)间在住") {
                            ForEach(group.rooms) { room in
                                Button {
                                    onSelect(room)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(room.roomNumber)
                                            .font(.title2.bold())
                                            .foregroundStyle(.red)
                                            .frame(width: 60)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(room.roomType.rawValue)
                                                .font(.subheadline)
                                            Text("\(room.orientation.rawValue) · ¥\(Int(room.pricePerNight))/晚")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("选择退房房间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(rooms.count)间在住")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
