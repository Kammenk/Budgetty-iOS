//
//  WidgetsView.swift
//  Budgetty
//
//  In-app widget gallery (from Account → Widgets). Previews the widget faces with real data; the
//  actual WidgetKit extension target is added separately.
//

import SwiftUI
import SwiftData

struct WidgetsView: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]

    private var monthSpent: Decimal {
        let cal = Calendar.current
        return receipts.filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }
    private var monthlyBudget: Decimal? { budgets.first { $0.key == Budget.monthlyKey }?.amount }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                banner
                section("Small") {
                    HStack(spacing: 16) {
                        spendWidget.frame(width: 150, height: 150)
                        budgetWidget.frame(width: 150, height: 150)
                    }
                }
                section("Medium") { recentWidget.frame(height: 150) }
            }
            .padding(20)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Palette.tint)
            Text("Touch & hold your Home Screen, tap ＋, and search “Budgetty” to add these.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var spendWidget: some View {
        widgetCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("This month").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(monthSpent.formatMoney()).font(.title2).fontWeight(.bold).foregroundStyle(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("\(receipts.filter { Calendar.current.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }.count) receipts")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
            .background(Palette.heroGradient)
        }
    }

    private var budgetWidget: some View {
        let frac = monthlyBudget.map { HomeView.fraction(monthSpent, of: $0) } ?? 0
        return widgetCard {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Palette.fill, lineWidth: 10)
                    Circle().trim(from: 0, to: frac).stroke(Palette.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(frac * 100))%").font(.headline)
                }
                .frame(width: 78, height: 78)
                Text("of budget").font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(Palette.card)
        }
    }

    private var recentWidget: some View {
        widgetCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent receipts").font(.caption).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                ForEach(Array(receipts.prefix(3).enumerated()), id: \.element.persistentModelID) { _, r in
                    HStack(spacing: 10) {
                        StoreAvatar(store: r.store, size: 26)
                        Text(r.store).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(r.paidTotal.formatMoney()).font(.subheadline).fontWeight(.semibold)
                    }
                }
                if receipts.isEmpty { Text("No receipts yet").font(.caption).foregroundStyle(Palette.tertiaryLabel) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(16)
            .background(Palette.card)
        }
    }

    private func widgetCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
