//
//  PlannedOverlaySheet.swift
//  Budgetty
//
//  The read-only explainer opened by a section's quiet "Planned" badge when the recurring-bills
//  overlay is on. One sheet per section (mockup 3a): a shared spine — hatch swatch, "Bills · planned",
//  the section + period, Done, then the Spent/Planned pair — with a section-specific body. Purely
//  explanatory; the layer is switched off in Customize, so Done is the only action. Android parity:
//  `PlannedOverlayDialog` (the Breakdown / Trend dialog bodies). No Summary case: the iOS stat grid
//  ships with no header row to hang a badge on, and nothing in it changes when the layer is on.
//

import SwiftUI

/// Which section's explainer the badge opens. (No `.summary`: see the file header.)
enum PlannedDialog: String, Identifiable {
    case breakdown, trend
    var id: String { rawValue }
    var sectionName: LocalizedStringKey { self == .breakdown ? "Breakdown" : "Trend" }
}

struct PlannedOverlaySheet: View {
    let dialog: PlannedDialog
    let overlay: PlannedOverlay
    /// The period's actual spend — the €950 the Spent tile shows and the % denominator.
    let spent: Decimal
    /// "June 2026" (Breakdown) or "Dec 2025 – Jun 2026" (Trend) for the header subtitle.
    let periodLabel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                spentPlannedPair
                switch dialog {
                case .breakdown: breakdownBody
                case .trend: trendBody
                }
            }
            .padding(20)
        }
        .background(Palette.groupedBackground)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .presentationDetents(dialog == .breakdown ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .coversFloatingDock()
    }

    // MARK: - Header (shared spine)

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                PlannedHatchSwatch(size: 16, corner: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bills · planned").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
                    HStack(spacing: 4) {
                        Text(dialog.sectionName)
                        Text("·"); Text(periodLabel)
                    }
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Text("Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            Divider()
        }
        .background(Palette.groupedBackground)
    }

    /// "Spent €950  ·  Planned €967" — two tiles, the planned one hatched.
    private var spentPlannedPair: some View {
        HStack(spacing: 10) {
            pairTile(label: "Spent", amount: spent, hatched: false)
            pairTile(label: "Planned", amount: overlay.plannedTotal, hatched: true)
        }
    }

    private func pairTile(label: LocalizedStringKey, amount: Decimal, hatched: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Palette.secondaryLabel)
            Text(amount.formatMoney()).font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tertiaryBackground, in: shape)
        .modifier(HatchTile(shape: shape, on: hatched))
    }

    // MARK: - Breakdown body

    @ViewBuilder
    private var breakdownBody: some View {
        sectionLabel("The hatched wedge")
        groupedCard {
            let bills = overlay.bills
            ForEach(Array(bills.enumerated()), id: \.offset) { idx, bill in
                HStack {
                    Text(bill.label).foregroundStyle(Palette.label)
                    Spacer(minLength: 8)
                    Text(bill.amount.formatMoney()).fontWeight(.semibold).foregroundStyle(Palette.label)
                }
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 11)
                if idx < bills.count - 1 { Divider().padding(.leading, 14) }
            }
        }
        Text("Category shares stay a percentage of the \(spent.formatMoney()) you spent — planned bills are never in that total.")
            .font(.footnote).foregroundStyle(Palette.secondaryLabel)
        if !overlay.matched.isEmpty { dedupNote }
    }

    /// The dedup note: bills hidden as already-matched to a receipt (counted once, in spend).
    private var dedupNote: some View {
        let matched = overlay.matched
        let title = String(format: NSLocalizedString(
            matched.count == 1
                ? "%lld bill hidden — already matched to a receipt"
                : "%lld bills hidden — already matched to a receipt", comment: ""), matched.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle").font(.system(size: 15))
                    .foregroundStyle(Palette.secondaryLabel)
                Text(title).font(.footnote).foregroundStyle(Palette.secondaryLabel)
            }
            Divider()
            ForEach(Array(matched.enumerated()), id: \.offset) { _, m in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.label).font(.subheadline).foregroundStyle(Palette.label)
                        Text("matched · \(m.date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                    Spacer(minLength: 8)
                    Text(m.amount.formatMoney()).font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Palette.label)
                }
            }
            Text("Counted once, in spend.").font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Trend body

    @ViewBuilder
    private var trendBody: some View {
        sectionLabel("Reading the hatched caps")
        groupedCard {
            explainRow(mark: AnyView(flatCapMark),
                       title: "Every cap is the same",
                       body: Text("Your bills are a flat \(overlay.plannedTotal.formatMoney()) a month, so the hatched part doesn't vary. Only the solid part — what you actually spent — moves."))
            Divider().padding(.leading, 14)
            explainRow(mark: AnyView(caplessMark),
                       title: "Early months have none",
                       body: Text("Bills aren't projected backwards, so months before you added them show spend only."))
            Divider().padding(.leading, 14)
            explainRow(mark: AnyView(arrowMark),
                       title: "The bars got shorter",
                       body: Text("The chart now fits spend plus bills, so the scale changed. The amounts didn't."))
        }
        if !overlay.matched.isEmpty {
            let key = overlay.matched.count == 1
                ? "The %1$@ excludes %2$lld bill already matched to a receipt this period. Open Breakdown to see which."
                : "The %1$@ excludes %2$lld bills already matched to a receipt this period. Open Breakdown to see which."
            Text(String(format: NSLocalizedString(key, comment: ""),
                        overlay.plannedTotal.formatMoney(), overlay.matched.count))
                .font(.footnote).foregroundStyle(Palette.secondaryLabel)
        }
    }

    private func explainRow(mark: AnyView, title: LocalizedStringKey, body: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            mark.frame(width: 22, height: 26, alignment: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                body.font(.footnote).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    /// A flat hatched cap over a solid tint bar — "every cap is the same".
    private var flatCapMark: some View {
        let cap = UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
        return VStack(spacing: 0) {
            cap.fill(Palette.plan.opacity(0.12))
                .overlay(HatchStripes(step: 4).stroke(Palette.plan, lineWidth: 1.1).clipShape(cap))
                .overlay(cap.strokeBorder(Palette.plan, lineWidth: 1))
                .frame(height: 13)
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(Palette.tint).frame(height: 13)
        }
        .frame(width: 16)
    }

    /// A plain solid bar, no cap — "early months have none".
    private var caplessMark: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.fill).frame(width: 16, height: 22)
    }

    /// An up arrow — "the bars got shorter" (rescaled axis).
    private var arrowMark: some View {
        Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Palette.secondaryLabel)
    }

    // MARK: - Building blocks

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
    }

    private func groupedCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Adds the planned hatch + `--plan` rim to the "Planned" pair tile, only when `on`.
private struct HatchTile<S: InsettableShape>: ViewModifier {
    let shape: S
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.plannedHatchOverlay(in: shape) } else { content }
    }
}
