import SwiftUI

/// Centralized design tokens matching the approved mockup.
enum Theme {
    // MARK: - Colors
    static let bgDeep       = Color(hex: 0xF5F0E8)
    static let bgBase       = Color(hex: 0xFAF7F2)
    static let bgSurface    = Color(hex: 0xF0EBE3)
    static let bgCard       = Color.white
    static let bgCardHover  = Color(hex: 0xFBF9F6)
    static let bgSidebar    = Color(hex: 0xF0EBE3)

    static let textPrimary   = Color(hex: 0x1A1A1A)
    static let textSecondary = Color(hex: 0x6B6560)
    static let textTertiary  = Color(hex: 0x9C958C)

    static let accent       = Color(hex: 0xD97757)
    static let accentHover  = Color(hex: 0xC4653A)

    static let border       = Color(hex: 0xE8E0D4)

    static let confirm      = Color(hex: 0x5D8C5A)
    static let cancel       = Color(hex: 0xC4653A)

    static let diffRemoved  = Color(hex: 0xC4653A).opacity(0.10)
    static let diffAdded    = Color(hex: 0x5D8C5A).opacity(0.12)
}

// MARK: - Color hex initializer

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
