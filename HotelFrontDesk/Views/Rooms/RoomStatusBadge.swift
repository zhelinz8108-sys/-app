import SwiftUI

struct RoomStatusBadge: View {
    let status: RoomStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.clear)
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(0.5), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

#Preview {
    HStack {
        ForEach(RoomStatus.allCases) { status in
            RoomStatusBadge(status: status)
        }
    }
}
