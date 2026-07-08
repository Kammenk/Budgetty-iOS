//
//  Palette.swift
//  Budgetty
//
//  Color tokens for the iOS app. The mockups lean on iOS system semantic colors (grouped
//  backgrounds, label levels, fills, system green/orange/red) so light/dark come mostly for free —
//  we only pin the brand violet tint and the hero gradient. Token names mirror the mockup CSS vars.
//

import SwiftUI
import UIKit

extension Color {
    /// Build a Color from a packed 0xAARRGGBB integer — the format category colors are stored in.
    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum Palette {
    // MARK: - Brand

    /// Brand accent, dynamic: violet in light (#6650A4), lightened in dark (#BFA8FF) — matches the
    /// mockup `--tint`. Use as the app tint and for selected/active states.
    static let tint = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xBF/255, green: 0xA8/255, blue: 1.0, alpha: 1)
            : UIColor(red: 0x66/255, green: 0x50/255, blue: 0xA4/255, alpha: 1)
    })

    /// Faint brand wash behind selected sidebar rows / chips (`--tint-bg`).
    static let tintSoft = tint.opacity(0.12)

    /// Hero "Total spent" card gradient (mockup: linear 140°, #5E4CAB → #7B5AC8 → #9A6FE0).
    static let heroGradient = LinearGradient(
        colors: [Color(argb: 0xFF5E4CAB), Color(argb: 0xFF7B5AC8), Color(argb: 0xFF9A6FE0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Surfaces (iOS grouped-background system)

    static let groupedBackground = Color(uiColor: .systemGroupedBackground)         // --bg
    static let card = Color(uiColor: .secondarySystemGroupedBackground)             // --bg2
    static let tertiaryBackground = Color(uiColor: .tertiarySystemGroupedBackground) // --bg3
    static let fill = Color(uiColor: .tertiarySystemFill)                           // --fill (track)
    static let separator = Color(uiColor: .separator)                              // --sep

    // MARK: - Text

    static let label = Color(uiColor: .label)
    static let secondaryLabel = Color(uiColor: .secondaryLabel)                     // --label2
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)                       // --label3

    // MARK: - Budget status "traffic light" (iOS system semantics)

    static let good = Color(uiColor: .systemGreen)
    static let warn = Color(uiColor: .systemOrange)
    static let bad = Color(uiColor: .systemRed)
}
