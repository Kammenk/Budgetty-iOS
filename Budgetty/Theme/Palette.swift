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

    /// Brand accent, dynamic: violet in light (#6B50A8), lightened in dark (#C4AEFF) — matches the
    /// Liquid Glass v2 material-system `--tint`. Use as the app tint and for selected/active states.
    /// Per the spec this is used *only* on the primary action, active tab, and links — never as a
    /// chrome fill (chrome stays system-adaptive glass and defers to content).
    static let tint = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xC4/255, green: 0xAE/255, blue: 1.0, alpha: 1)
            : UIColor(red: 0x6B/255, green: 0x50/255, blue: 0xA8/255, alpha: 1)
    })

    /// Faint brand wash behind selected sidebar rows / chips / secondary buttons (`--tint-bg`:
    /// light rgba(107,80,168,.10) · dark rgba(196,174,255,.14)).
    static let tintSoft = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xC4/255, green: 0xAE/255, blue: 1.0, alpha: 0.14)
            : UIColor(red: 0x6B/255, green: 0x50/255, blue: 0xA8/255, alpha: 0.10)
    })

    /// Hero "Total spent" card gradient — CSS-exact from the v2 mockup:
    /// `linear-gradient(140deg, #5E4CAB, #7B5AC8, #9A6FE0)` = deep violet entering at the top-left,
    /// brightening toward the bottom-right. The *bright top edge* the mockup shows is NOT the
    /// gradient — it's a separate `inset 0 1px 0 rgba(255,255,255,.18)` highlight (see `heroCard`).
    static let heroGradient = LinearGradient(
        colors: [Color(argb: 0xFF5E4CAB), Color(argb: 0xFF7B5AC8), Color(argb: 0xFF9A6FE0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Full-bleed page canvas: the grouped background plus the mockup's THREE ambient glows —
    /// CSS-exact from `iOS Home.dc.html`:
    ///   `radial-gradient(52% 40% at -8% 4%,   violet, transparent 62%)`
    ///   `radial-gradient(46% 36% at 110% 26%, orange, transparent 62%)`
    ///   `radial-gradient(52% 42% at 46% 110%, green,  transparent 62%)`
    /// Shared by every full-screen tab page (see `View.screenCanvas()`).
    static var canvas: some View {
        GeometryReader { geo in
            ZStack {
                groupedBackground
                // dark rgba(140,105,230,.2) · light rgba(110,80,190,.16)
                ambientGlow(dynamic(light: 0x296E50BE, dark: 0x338C69E6),
                            cx: -0.08, cy: 0.04, rx: 0.52, ry: 0.40, in: geo.size)
                // dark rgba(226,120,88,.12) · light rgba(214,110,80,.11)
                ambientGlow(dynamic(light: 0x1CD66E50, dark: 0x1FE27858),
                            cx: 1.10, cy: 0.26, rx: 0.46, ry: 0.36, in: geo.size)
                // dark rgba(72,190,110,.1) · light rgba(70,150,86,.11)
                ambientGlow(dynamic(light: 0x1C469656, dark: 0x1A48BE6E),
                            cx: 0.46, cy: 1.10, rx: 0.52, ry: 0.42, in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    /// One elliptical ambient glow: colour at the centre fading to clear at 62% of the radius
    /// (mirroring the mockup's `transparent 62%` stop). `cx`/`cy` are the centre as fractions of the
    /// canvas; `rx` is the horizontal radius as a fraction of the width, `ry` vertical of the height.
    private static func ambientGlow(
        _ color: Color, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, in size: CGSize
    ) -> some View {
        let radiusX = max(size.width * rx, 1)
        let radiusY = max(size.height * ry, 1)
        return RadialGradient(
            stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: 0.62)],
            center: .center, startRadius: 0, endRadius: radiusX
        )
        .frame(width: radiusX * 2, height: radiusX * 2)
        .scaleEffect(y: radiusY / radiusX)
        .position(x: size.width * cx, y: size.height * cy)
        .allowsHitTesting(false)
    }

    // MARK: - Surfaces (Liquid Glass v2 warm/violet-tinted neutrals, NOT plain iOS system grays)
    //
    // The v2 mockups derive their signature violet cast from tinted neutrals — the dark canvas is a
    // near-black violet (#0B0A0F), surfaces lean toward violet-grey, and separators carry a violet
    // hue. We pin these explicitly (dynamic light/dark) so every screen picks up the tint that the
    // system grouped-background grays were washing out.

    /// `--bg`: content canvas / full-bleed background.
    static let groupedBackground = dynamic(light: 0xFFF4F3F0, dark: 0xFF0B0A0F)
    /// `--bg2`: cards, grouped lists.
    static let card = dynamic(light: 0xFFFFFFFF, dark: 0xFF1E1C28)
    /// `--bg3`: nested fills inside cards.
    static let tertiaryBackground = dynamic(light: 0xFFF2F1F6, dark: 0xFF2C2A3A)
    /// `--fill`: search fields, inline chips, progress tracks (translucent overlay).
    static let fill = dynamic(light: 0x1F787880, dark: 0x47787880)
    /// `--sep`: hairline dividers inside cards.
    static let separator = dynamic(light: 0x1A3C3C43, dark: 0x4C545458)
    /// `--sep2`: the stronger, violet-tinted hairline used for card / control borders.
    static let separatorStrong = dynamic(light: 0x8CC8C6D2, dark: 0x8058546E)

    // MARK: - Liquid Glass v2 content-card material (CSS-exact from the Home mockup)
    //
    // The v2 mockups render content cards as GLASS, not opaque panels:
    //   `background: var(--glass)` (light rgba(255,255,255,.44) · dark rgba(38,33,56,.42))
    //   `backdrop-filter: blur(18px) saturate(180%)`
    //   `border: .5px solid var(--glass-b)` (light rgba(255,255,255,.62) · dark rgba(255,255,255,.14))
    //   `box-shadow: 0 10px 28px rgba(25,12,60,.1)`
    // The white-alpha border is what makes the card rims read crisp on the dark canvas.

    /// `--glass`: the tinted translucent card fill, layered over a system blur material.
    static let glassFill = dynamic(light: 0x70FFFFFF, dark: 0x6B262138)
    /// `--glass-b`: the white-alpha card rim.
    static let glassBorder = dynamic(light: 0x9EFFFFFF, dark: 0x24FFFFFF)

    // MARK: - Text

    static let label = dynamic(light: 0xFF1A1A1E, dark: 0xFFF2F1F8)
    static let secondaryLabel = dynamic(light: 0x943C3C43, dark: 0x8CEBEBF5)          // --label2
    static let tertiaryLabel = dynamic(light: 0x403C3C43, dark: 0x40EBEBF5)           // --label3

    // MARK: - Signature glass CTA (Scan)

    /// The prominent Scan button stays a rich violet in *both* themes (mockup `--lg-cta`), so it never
    /// washes out to the pale dark-mode tint. White label on top.
    static let scanCTA = dynamic(light: 0xFF6B50A8, dark: 0xFF7E60E0)

    /// Build a dynamic (light/dark) Color from two packed 0xAARRGGBB integers.
    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
    }
    private static func uiColor(_ argb: Int) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
    }

    // MARK: - Budget status "traffic light" (iOS system semantics)

    static let good = Color(uiColor: .systemGreen)
    static let warn = Color(uiColor: .systemOrange)
    static let bad = Color(uiColor: .systemRed)

    /// Soft violet-tinted drop shadow that lifts content cards off the canvas (mockup:
    /// `0 10px 28px rgba(25,12,60,.1)`).
    static let cardShadow = Color(argb: 0x1A190C3C)
}

// MARK: - Page canvas

extension View {
    /// The app's page canvas: the grouped background with a soft violet corner glow bleeding in from
    /// the top-left (the v2 mockup's ambient light), plus a bottom fade that dims content as it
    /// scrolls under the tab bar. The system's Liquid Glass tab bar can't be made denser (it ignores
    /// `UITabBarAppearance` — verified), so we darken what it *samples* instead: with the content
    /// fading to the canvas color beneath it, the glass pill reads as the mockup's near-opaque bar.
    func screenCanvas() -> some View {
        background(Palette.canvas)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: Palette.groupedBackground.opacity(0), location: 0),
                        .init(color: Palette.groupedBackground.opacity(0.55), location: 0.35),
                        .init(color: Palette.groupedBackground.opacity(0.92), location: 0.7),
                        .init(color: Palette.groupedBackground.opacity(0.92), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                // The overlay anchors to the safe-area bottom (the tab bar's top edge), and
                // `ignoresSafeArea` doesn't reach from inside a nested overlay — so push the gradient
                // past the edge with negative padding to cover the glass bar's sampling region too.
                .frame(height: 310)
                .padding(.bottom, -120)
                .allowsHitTesting(false)
            }
    }
}

// MARK: - Content card

extension View {
    /// The Liquid Glass v2 content-card treatment, CSS-exact from the Home mockup: a translucent
    /// tinted fill over a blur material (so the canvas's ambient glows shimmer through), a crisp
    /// white-alpha rim, and a soft violet drop shadow.
    func contentCard(cornerRadius: CGFloat = Dimens.cardCorner) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Palette.glassFill, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 1))
            .shadow(color: Palette.cardShadow, radius: 14, y: 10)
    }

    /// Input-field treatment: same tinted fill + hairline border as a card, but *no* drop shadow —
    /// text fields, pickers and inline inputs should read as inset wells, not float like cards.
    func inputField(cornerRadius: CGFloat = Dimens.cornerM) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(Palette.separatorStrong, lineWidth: 0.5))
    }
}
