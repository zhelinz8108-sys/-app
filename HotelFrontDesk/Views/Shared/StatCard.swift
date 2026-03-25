import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .appPrimary

    var body: some View {
        HStack(spacing: 0) {
            // Accent line
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)

                Text(value)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.textPrimary)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.textPrimary.opacity(0.6))
            }
            .padding(.leading, 14)
            .padding(.vertical, 14)
            .padding(.trailing, 10)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .luxuryShadow(.card)
    }
}

#Preview {
    HStack(spacing: 14) {
        StatCard(title: "总房数", value: "24", icon: "building", color: .appPrimary)
        StatCard(title: "已住", value: "16", icon: "person.fill", color: .appError)
        StatCard(title: "空房", value: "6", icon: "door.left.hand.open", color: .appSuccess)
    }
    .padding()
    .background(Color.appBackground)
}
