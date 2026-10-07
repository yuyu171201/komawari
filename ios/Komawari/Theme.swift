import KomawariCore
import SwiftUI
import UIKit

extension Color {
    /// ライト・ダークで切り替わる色。
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }
}

/// Web 版（style.css）と同じ配色。
enum Theme {
    static let background = Color(light: 0xF3F8FE, dark: 0x1A1E26)
    static let surface = Color(light: 0xFFFFFF, dark: 0x242A35)
    static let line = Color(light: 0xD6E4F5, dark: 0x353F51)
    static let text = Color(light: 0x474747, dark: 0xE6E9EF)
    static let muted = Color(light: 0x8A93A3, dark: 0x98A2B5)

    static let main = Color(light: 0x5F86D8, dark: 0x86A8EE)
    static let mainDeep = Color(light: 0x4D6AA8, dark: 0x4A639C)
    static let mainSoft = Color(light: 0xE6F1FF, dark: 0x2A3449)
    static let mainPale = Color(light: 0xCDE4FF, dark: 0x3A4A69)
    static let accent = Color(light: 0xF0706F, dark: 0xFF8F8E)
    static let accentSoft = Color(light: 0xFFEAEA, dark: 0x46292B)
    static let warm = Color(light: 0xFFA726, dark: 0xFFB74D)
    static let warmSoft = Color(light: 0xFFF3D6, dark: 0x453611)
    static let offSurface = Color(light: 0xF1F2F5, dark: 0x20252E)
    /// 色付きラベルの上に載せる文字色。
    static let onLabel = Color(light: 0xFFFFFF, dark: 0x1A1E26)

    /// 授業カードの色帯と背景。
    static func card(_ status: Status) -> (bar: Color, fill: Color) {
        switch status {
        case .normal: (Color(light: 0x6F9BE0, dark: 0x86A8EE), Color(light: 0xFFFFFF, dark: 0x2D3543))
        case .swapped: (Color(light: 0x7A62CF, dark: 0xAB97F2), Color(light: 0xF1ECFF, dark: 0x342D52))
        case .extra: (Color(light: 0x2F9E5B, dark: 0x5CCB86), Color(light: 0xE4F7EA, dark: 0x1F3B2B))
        case .roomChanged: (Color(light: 0xD98500, dark: 0xF3B040), Color(light: 0xFFF3D6, dark: 0x453611))
        case .off: (Color(light: 0xB3BAC6, dark: 0x677085), Color(light: 0xEEF0F3, dark: 0x2A2F39))
        }
    }

    static func badge(_ status: Status) -> String? {
        switch status {
        case .normal: nil
        case .swapped: "振替"
        case .extra: "補講"
        case .roomChanged: "教室変更"
        case .off: "休講"
        }
    }
}
