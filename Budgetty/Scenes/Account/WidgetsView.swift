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
    @AppStorage(SettingsKey.premium) private var premium = false

    /// Faces currently on a home screen, for the slots caption. Read on appear — iOS gives no
    /// change notification for placements, and this screen is short-lived enough not to need one.
    @State private var placed: [WidgetSlot] = []
    @State private var showPaywall = false

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
                slotsCard
                section("Small") {
                    HStack(spacing: 16) {
                        spendWidget.frame(width: 150, height: 150)
                        budgetWidget.frame(width: 150, height: 150)
                    }
                }
                section("Medium") { recentWidget.frame(height: 150) }
            }
            .padding(20)
            .adaptiveReadableWidth()
        }
        .underFloatingDock(reportingScroll: false)
        .screenCanvas()
        .navigationTitle("Widgets")
        .task { placed = await WidgetQuota.placedSlots() }
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
    }

    /// How many free slots are left.
    ///
    /// Informational only — iOS has no way to refuse a placement (the home-screen picker never runs
    /// our code), so the cap is enforced where it has to be: at render time, by the widget drawing
    /// `LockedWidgetView` instead of its data. This is the courtesy heads-up before that happens.
    @ViewBuilder
    private var slotsCard: some View {
        let remaining = WidgetQuota.remaining(placed: placed, isPremium: premium)
        HStack(spacing: 10) {
            Image(systemName: remaining == 0 ? "lock.fill" : "square.grid.2x2")
                .foregroundStyle(remaining == 0 ? Palette.warn : Palette.tint)
            if let remaining {
                if remaining == 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Free widget slots are full. Remove one from your home screen, or upgrade for unlimited widgets.")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                        Button("Unlock more widgets") { showPaywall = true }
                            .font(.caption).fontWeight(.semibold).foregroundStyle(Palette.tint)
                    }
                } else {
                    Text("\(Set(placed).count) of \(WidgetQuota.freeLimit) free widget slots used")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
            } else {
                Text("Premium · unlimited widgets")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 12)
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Palette.tint)
            Text("Touch & hold your Home Screen, tap ＋, and search “Budgetty” to add these.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 12)
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

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
