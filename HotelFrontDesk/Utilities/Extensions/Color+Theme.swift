import SwiftUI

extension Color {
    // MARK: - Luxury Hotel Palette

    // Core
    static let appPrimary = Color(hex: 0x1B2838)
    static let appAccent = Color(hex: 0xC5A55A)
    static let appBackground = Color(hex: 0xFAFAF8)
    static let appCard = Color.white

    // Semantic
    static let appSuccess = Color(hex: 0x6B8F71)
    static let appWarning = Color(hex: 0xD4A574)
    static let appError = Color(hex: 0xC47070)

    // Text
    static let textPrimary = Color(hex: 0x1B2838)
    static let textSecondary = Color(hex: 0x5C5C5C)

    // 房态颜色 — refined palette
    static let roomVacant = Color(hex: 0x6B8F71)       // sage green
    static let roomReserved = Color(hex: 0x7B6FA0)     // muted purple
    static let roomOccupied = Color(hex: 0xC47070)     // muted rose
    static let roomCleaning = Color(hex: 0xD4A574)     // warm amber
    static let roomMaintenance = Color(hex: 0xA0A0A0)  // cool gray

    // 押金状态
    static let depositCollected = Color(hex: 0x1B2838)
    static let depositRefunded = Color(hex: 0x6B8F71)
    static let depositBalance = Color(hex: 0xD4A574)

    // MARK: - Hex Initializer
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - ShapeStyle convenience for foregroundStyle()

extension ShapeStyle where Self == Color {
    static var appPrimary: Color { Color.appPrimary }
    static var appAccent: Color { Color.appAccent }
    static var appBackground: Color { Color.appBackground }
    static var appCard: Color { Color.appCard }
    static var appSuccess: Color { Color.appSuccess }
    static var appWarning: Color { Color.appWarning }
    static var appError: Color { Color.appError }
    static var textPrimary: Color { Color.textPrimary }
    static var textSecondary: Color { Color.textSecondary }
    static var roomVacant: Color { Color.roomVacant }
    static var roomReserved: Color { Color.roomReserved }
    static var roomOccupied: Color { Color.roomOccupied }
    static var roomCleaning: Color { Color.roomCleaning }
    static var roomMaintenance: Color { Color.roomMaintenance }
}

// MARK: - Shadow Styles

struct LuxuryShadow: ViewModifier {
    enum Style {
        case card, elevated, subtle
    }

    let style: Style

    func body(content: Content) -> some View {
        switch style {
        case .card:
            content.shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        case .elevated:
            content.shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
        case .subtle:
            content.shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
    }
}

extension View {
    func luxuryShadow(_ style: LuxuryShadow.Style = .card) -> some View {
        modifier(LuxuryShadow(style: style))
    }
}
