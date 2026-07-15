//
//  Components.swift
//  Budgetty
//
//  Small shared UI pieces used across screens: the colored store-initial avatar, a thin rounded
//  progress bar, and the glass capsule segmented control. Kept together so screens render them
//  consistently.
//

import SwiftUI

/// A rounded-square tile showing a store's first initial on a stable, per-store color — the receipt
/// row leading glyph from the mockups (Kaufland red, Lidl blue, …).
struct StoreAvatar: View {
    let store: String
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Self.color(for: store))
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var initial: String {
        String(store.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased() ?? "?")
    }

    /// Deterministic color for a store name, drawn from a fixed palette so the same store always
    /// gets the same tile color.
    static func color(for store: String) -> Color {
        let palette = [0xFFC0392B, 0xFF1F5FBF, 0xFF1C7C54, 0xFFC98A00, 0xFF7A3FB0,
                       0xFF2C7A7B, 0xFFB84A6B, 0xFF3B6FB0, 0xFF9A6FE0, 0xFFC0662B]
        let key = store.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
        return Color(argb: palette[key % palette.count])
    }
}

/// A rounded tile showing a category's emoji on its color — solid for item rows, or a soft tint
/// wash for budget rows.
struct CategoryTile: View {
    let category: String
    var size: CGFloat = 30
    var soft: Bool = false

    var body: some View {
        let color = Color(argb: Categories.color(for: category))
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(soft ? color.opacity(0.15) : color)
            .frame(width: size, height: size)
            .overlay(Text(Categories.emoji(for: category)).font(.system(size: size * 0.5)))
    }
}

/// A thin, fully-rounded progress bar with a tinted fill on a system-fill track.
struct ProgressBarView: View {
    /// 0...1.
    let fraction: Double
    var color: Color = Palette.tint
    var height: CGFloat = 6
    var track: Color = Palette.fill

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// The Liquid Glass v2 capsule segmented control: a recessed `segmentedTrack` capsule with the
/// selected segment floating as a glass pill (`matControl` over blur, soft drop shadow) — the
/// mockups' pill toggle, which the system `.segmented` picker style can't render.
struct GlassSegmentedControl<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> LocalizedStringKey
    @Namespace private var pillNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.footnote)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? Palette.label : Palette.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Palette.matControl)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().strokeBorder(
                                        LinearGradient(stops: [.init(color: Palette.glassSpecular, location: 0),
                                                               .init(color: .clear, location: 0.5)],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: 1))
                                    .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1.5)
                                    .matchedGeometryEffect(id: "pill", in: pillNS)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(Palette.segmentedTrack, in: Capsule())
    }
}
