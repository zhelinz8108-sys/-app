import SwiftUI

struct RoomCardView: View {
    let room: Room
    @ObservedObject private var lockService = RoomLockService.shared

    private var isLocked: Bool {
        lockService.isLockedByOther(roomID: room.id)
    }

    private var lockInfo: RoomLockService.RoomLock? {
        lockService.lockInfo(roomID: room.id)
    }

    private var statusColor: Color {
        isLocked ? .appWarning : room.status.color
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧状态色条
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 5)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 5) {
                // 房号
                Text(room.roomNumber)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(statusTextColor)

                // 房型
                Text(room.roomType.rawValue)
                    .font(.caption)
                    .foregroundStyle(statusTextColor.opacity(0.6))

                Spacer(minLength: 4)

                // 状态或锁定信息
                if isLocked, let info = lockInfo {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("\(info.staffName)办理中")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.appWarning)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: room.status.icon)
                            .font(.system(size: 10))
                        Text(room.status.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(statusTextColor.opacity(0.8))
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(statusBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 状态背景色

    private var statusBackground: Color {
        switch room.status {
        case .vacant:      return Color.roomVacant.opacity(0.10)
        case .reserved:    return Color.roomReserved.opacity(0.12)
        case .occupied:    return Color.roomOccupied.opacity(0.12)
        case .cleaning:    return Color.roomCleaning.opacity(0.12)
        case .maintenance: return Color.roomMaintenance.opacity(0.08)
        }
    }

    // MARK: - 状态文字色

    private var statusTextColor: Color {
        switch room.status {
        case .vacant:      return Color(hex: 0x3D5C42)  // 深绿
        case .reserved:    return Color(hex: 0x4E4270)  // 深紫
        case .occupied:    return Color(hex: 0x8B3A3A)  // 深红
        case .cleaning:    return Color(hex: 0x8B6B3D)  // 深琥珀
        case .maintenance: return Color(hex: 0x5A5A5A)  // 深灰
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
        ForEach(PreviewData.rooms.prefix(8)) { room in
            RoomCardView(room: room)
        }
    }
    .padding()
    .background(Color.appBackground)
}
