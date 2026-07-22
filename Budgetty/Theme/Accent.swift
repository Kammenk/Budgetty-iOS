//
//  Accent.swift
//  Budgetty
//
//  The accent themes Premium unlocks (Android parity: `AccentTheme` in AppSettings.kt).
//
//  Android overrides its Material scheme's `primary`; the iOS equivalent is the `Palette.tint`
//  token, which the Liquid Glass spec already reserves for exactly that role — primary action,
//  active tab, links, selected states — so swapping it here reaches every surface without touching
//  the ~80 call sites that read it.
//

import SwiftUI
import UIKit

enum AccentOption: String, CaseIterable, Identifiable {
    case violet, sage, ocean, plum

    var id: String { rawValue }

    var label: String {
        switch self {
        case .violet: String(localized: "Violet (default)")
        case .sage: String(localized: "Sage")
        case .ocean: String(localized: "Ocean")
        case .plum: String(localized: "Plum")
        }
    }

    /// Light/dark hex pair. Sage/Ocean/Plum are Android's exact values (`ui/theme/Theme.kt`,
    /// `accentPrimary`) so someone running both apps gets the same colour; `violet` is the brand
    /// tint iOS shipped with, which is the same role Android's `DEFAULT` plays.
    var hexes: (light: Int, dark: Int) {
        switch self {
        case .violet: (0x6B_50A8, 0xC4_AEFF)
        case .sage: (0x3E_5E41, 0xA8_C6AA)
        case .ocean: (0x1C_5C6E, 0x8F_C8D8)
        case .plum: (0x6A_2E78, 0xCF_A6D6)
        }
    }

    /// `--tint`: the accent itself, resolved per light/dark trait.
    var color: Color { dynamic(lightAlpha: 1, darkAlpha: 1) }

    /// `--tint-bg`: the faint wash behind selected rows, chips and secondary buttons — same hue at
    /// the mockup's alphas (light .10 · dark .14).
    var soft: Color { dynamic(lightAlpha: 0.10, darkAlpha: 0.14) }

    /// The hero card's three gradient stops, dark → light along the accent's own hue.
    ///
    /// `violet` returns the mockup's CSS-exact gradient untouched; the others re-derive it at their
    /// own hue **matching each stop's luminance**, not its HSB numbers. That distinction matters:
    /// the hero carries white text, and green at the violet gradient's brightness is far lighter to
    /// the eye than violet is — copying the numbers would have shipped a Sage card with ~1.6:1 text
    /// contrast. Matching luminance instead keeps every accent exactly as readable as the one the
    /// mockup was drawn for. (Without any of this, picking Sage would tint the chrome green and
    /// leave a violet hero stranded — Android avoids that by deriving its hero from `primary`.)
    var heroStops: [Color] {
        guard self != .violet else { return Self.referenceHero.map { Color(argb: 0xFF00_0000 | $0) } }
        return Self.referenceHero.map { matchingLuminance(of: $0) }
    }

    /// The signature primary-action capsule (`--lg-cta`): the Scan pill, Subscribe, Sign In, Save.
    /// Stays rich in dark mode rather than washing out to the pale tint, and — like the hero —
    /// holds the reference colour's luminance so its white label survives the accent swap.
    var cta: Color {
        guard self != .violet else {
            return Color(uiColor: UIColor { trait in
                UIColor(rgb: trait.userInterfaceStyle == .dark ? Self.referenceCTA.dark : Self.referenceCTA.light,
                        alpha: 1)
            })
        }
        let light = matchingLuminance(of: Self.referenceCTA.light)
        let dark = matchingLuminance(of: Self.referenceCTA.dark)
        return Color(uiColor: UIColor { trait in
            UIColor(trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// The mockup's violet hero gradient — `linear-gradient(140deg, #5E4CAB, #7B5AC8, #9A6FE0)`.
    private static let referenceHero = [0x5E_4CAB, 0x7B_5AC8, 0x9A_6FE0]
    /// The mockup's violet CTA capsule (`--lg-cta`), light/dark.
    private static let referenceCTA = (light: 0x6B_50A8, dark: 0x7E_60E0)

    /// This accent's hue and saturation at whatever brightness reproduces `reference`'s luminance.
    /// Returns raw channels so the contrast tests can measure exactly what gets drawn.
    func rgbMatchingLuminance(of reference: Int) -> (Double, Double, Double) {
        let target = Self.luminance(ofRGB: reference)
        let h = Self.hue(of: hexes.light)
        let s = Self.saturation(of: hexes.light)
        // Luminance rises monotonically with brightness, so bisection converges cleanly.
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if Self.luminance(of: Self.rgb(hue: h, saturation: s, brightness: mid)) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return Self.rgb(hue: h, saturation: s, brightness: (low + high) / 2)
    }

    private func matchingLuminance(of reference: Int) -> Color {
        let (r, g, b) = rgbMatchingLuminance(of: reference)
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    private func dynamic(lightAlpha: CGFloat, darkAlpha: CGFloat) -> Color {
        let (light, dark) = hexes
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
    }

    // MARK: - Colour maths
    //
    // Hand-rolled rather than going through UIColor's in-out getters so every piece stays a pure
    // function the tests can call directly — which is how the white-text contrast on each derived
    // accent is checked instead of eyeballed.

    /// SwiftUI hue (0…1) of a packed 0xRRGGBB colour.
    static func hue(of rgb: Int) -> Double {
        let (r, g, b) = components(rgb)
        let mx = max(r, g, b), mn = min(r, g, b)
        let d = mx - mn
        guard d > 0 else { return 0 }
        let h: Double = switch mx {
        case r: (g - b) / d + (g < b ? 6 : 0)
        case g: (b - r) / d + 2
        default: (r - g) / d + 4
        }
        return h / 6
    }

    /// HSB saturation (0…1) of a packed 0xRRGGBB colour.
    static func saturation(of rgb: Int) -> Double {
        let (r, g, b) = components(rgb)
        let mx = max(r, g, b)
        guard mx > 0 else { return 0 }
        return (mx - min(r, g, b)) / mx
    }

    static func components(_ rgb: Int) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    /// HSB → RGB, all channels 0…1.
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        let c = brightness * saturation
        let hp = (hue * 6).truncatingRemainder(dividingBy: 6)
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double) = switch Int(hp) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    /// WCAG relative luminance.
    static func luminance(of rgb: (Double, Double, Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    static func luminance(ofRGB packed: Int) -> Double { luminance(of: components(packed)) }

    /// WCAG contrast ratio against white — what the hero and CTA labels are drawn in.
    static func contrastWithWhite(_ rgb: (Double, Double, Double)) -> Double {
        1.05 / (luminance(of: rgb) + 0.05)
    }
}

extension UIColor {
    /// From a packed 0xRRGGBB integer — the format the accent hexes share with Android.
    convenience init(rgb: Int, alpha: CGFloat) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Holds the live accent choice.
///
/// `@Observable` rather than `@AppStorage` on purpose: `Palette.tint` is read as a plain static from
/// ~80 view bodies, and SwiftUI's observation tracking registers a dependency on any `@Observable`
/// property touched during `body` — however deep the accessor sits. So changing the accent re-renders
/// everything that draws with the tint, with no environment plumbing and, crucially, without an
/// `.id()` reset that would pop the user out of the picker they just used.
///
/// Deliberately *not* `@MainActor`: `Palette.tint` is a nonisolated static and has to stay callable
/// from anywhere. Writes only ever come from the settings UI.
@Observable
final class AppTheme {
    static let shared = AppTheme()

    var accent: AccentOption {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: SettingsKey.accent) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: SettingsKey.accent) ?? ""
        accent = AccentOption(rawValue: stored) ?? .violet
    }
}
