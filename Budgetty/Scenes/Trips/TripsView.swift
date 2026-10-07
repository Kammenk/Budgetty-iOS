//
//  TripsView.swift
//  Budgetty
//
//  Account → Trips (Travel mode). A trip is metadata over a tag; its spend is summed live from the
//  line items carrying that tag (same basis as the Insights "By tag" card), so nothing is denormalised
//  and ending a trip leaves every figure intact. At most one trip is active; the rest are past.
//  Android parity: `ui/trips/TripsScreen.kt` + `TripsViewModel`. Visuals from `iOS Travel Mode.dc.html`.
//

import SwiftUI
import SwiftData

struct TripsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var trips: [Trip]

    @State private var showStart = false
    @State private var endTarget: Trip?
    @State private var tagSheet: String?

    private var allItems: [LineItem] { receipts.flatMap(\.items) }
    private var activeTrip: Trip? { trips.filter { $0.active }.max { $0.createdAt < $1.createdAt } }
    private var pastTrips: [Trip] {
        trips.filter { !$0.active }
            .sorted { ($0.endedAt ?? $0.createdAt) > ($1.endedAt ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let active = activeTrip {
                    TripSummaryCard(trip: active, items: items(for: active), spent: spend(for: active),
                                    topCategories: topCategories(for: active),
                                    onShowInHistory: { tagSheet = active.tag },
                                    onEnd: { endTarget = active })
                }
                if !pastTrips.isEmpty { pastSection }
                if activeTrip == nil && pastTrips.isEmpty { emptyState }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Trips").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showStart = true } label: { Image(systemName: "plus") }
                    .disabled(activeTrip != nil)
            }
        }
        .sheet(isPresented: $showStart) { StartTripSheet() }
        .sheet(item: Binding(get: { tagSheet.map(TagSel.init) }, set: { tagSheet = $0?.tag })) { sel in
            TagTransactionsSheet(tag: sel.tag, items: allItems)
        }
        .alert("End \(endTarget?.name ?? "")?", isPresented: Binding(
            get: { endTarget != nil }, set: { if !$0 { endTarget = nil } }), presenting: endTarget) { _ in
            Button("Keep going", role: .cancel) {}
            Button("End trip", role: .destructive) { TripOps.endActive(context) }
        } message: { trip in
            Text("New expenses will stop being tagged. The \(items(for: trip).count) expenses already tagged stay, and you can find the trip any time under Account → Trips.")
        }
    }

    private struct TagSel: Identifiable { let tag: String; var id: String { tag } }

    // MARK: - Past trips

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAST TRIPS").font(.caption2).fontWeight(.semibold)
                .foregroundStyle(Palette.secondaryLabel).padding(.leading, 16)
            VStack(spacing: 0) {
                ForEach(Array(pastTrips.enumerated()), id: \.element.persistentModelID) { idx, trip in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    pastRow(trip)
                }
            }
            .contentCard(cornerRadius: 18)
            Text("Ended trips keep their tag, so they still filter History and appear in Insights → By tag.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.leading, 16).padding(.top, 2)
        }
    }

    private func pastRow(_ trip: Trip) -> some View {
        let s = spend(for: trip)
        let stats = TripStats.compute(trip, spent: s)
        return Button { tagSheet = trip.tag } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trip.name).font(.body).foregroundStyle(Palette.label)
                    Spacer()
                    Text(s.formatMoney()).font(.body).fontWeight(.semibold).foregroundStyle(Palette.label)
                }
                HStack(spacing: 6) {
                    Text("\(TripDates.span(trip)) · \(stats.perDay.formatMoney())/day")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    Spacer()
                    if let result = budgetResult(trip, spent: s) {
                        Text(result.text).font(.caption).fontWeight(.semibold).foregroundStyle(result.color)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { TripOps.resume(context, trip) } label: { Label("Resume trip", systemImage: "play.circle") }
                .disabled(activeTrip != nil)
            Button(role: .destructive) { TripOps.delete(context, trip) } label: { Label("Delete trip", systemImage: "trash") }
        }
    }

    /// "€54 under" / "€20 over" for a past trip with a budget, else nil.
    private func budgetResult(_ trip: Trip, spent: Decimal) -> (text: String, color: Color)? {
        guard let budget = trip.budgetAmount, budget > 0 else { return nil }
        let diff = budget - spent
        if diff >= 0 { return ("\(diff.formatMoney()) under", Palette.good) }
        return ("\((-diff).formatMoney()) over", Palette.bad)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure").font(.system(size: 36))
                .foregroundStyle(Palette.tint)
                .frame(width: 64, height: 64)
                .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("No trips yet").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
            Text("Start a trip and every expense you add is totalled for it automatically.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
            Button { showStart = true } label: { Text("Start a trip").font(.body).fontWeight(.semibold).ctaPill(height: 48) }
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 18)
        .contentCard(cornerRadius: 18)
    }

    // MARK: - Derivations

    private func items(for trip: Trip) -> [LineItem] {
        allItems.filter { li in li.tags.contains { $0.name == trip.tag } }
    }
    private func spend(for trip: Trip) -> Decimal {
        items(for: trip).reduce(.zero) { $0 + $1.lineTotal }
    }
    private func topCategories(for trip: Trip) -> [(name: String, amount: Decimal)] {
        var sums: [String: Decimal] = [:]
        for it in items(for: trip) { sums[it.category, default: .zero] += it.lineTotal }
        return sums.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(4)
            .map { (name: $0.key, amount: $0.value) }
    }
}

// MARK: - Active trip summary card

private struct TripSummaryCard: View {
    let trip: Trip
    let items: [LineItem]
    let spent: Decimal
    let topCategories: [(name: String, amount: Decimal)]
    let onShowInHistory: () -> Void
    let onEnd: () -> Void

    private var stats: TripStatsResult { TripStats.compute(trip, spent: spent) }

    var body: some View {
        VStack(spacing: 14) {
            hero
            if let pace = stats.pace, let budget = trip.budgetAmount { paceSection(pace, budget) }
            if !topCategories.isEmpty { topCategoriesSection }
            showInHistory
            endButton
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("✈️ \(TripDates.spanWithStatus(trip))").font(.caption).foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Text("\(items.count) expense\(items.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Text(spent.formatMoney()).font(.system(size: 40, weight: .bold)).foregroundStyle(Palette.label)
            Text("\(stats.perDay.formatMoney()) a day").font(.headline).foregroundStyle(Palette.label)
            if !stats.dayStrip.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(stats.dayStrip.enumerated()), id: \.offset) { _, elapsed in
                        Capsule().fill(elapsed ? Palette.tint : Palette.fill).frame(height: 6)
                    }
                }
                .padding(.top, 12)
                HStack {
                    if let total = stats.totalDays { Text("Day \(stats.daysElapsed) of \(total)") }
                    Spacer()
                    if let left = stats.daysLeft { Text("\(left) days left") }
                }
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.glassBorder, lineWidth: 1))
    }

    private func paceSection(_ pace: TripPace, _ budget: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TRIP BUDGET")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(spent.formatMoney()) of \(budget.formatMoney())")
                        .font(.body).foregroundStyle(Palette.label)
                    Spacer()
                    Text(paceLabel(pace.state)).font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(paceColor(pace.state))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.fill)
                        Capsule().fill(paceColor(pace.state)).frame(width: geo.size.width * pace.fill)
                        // The even-pace tick: where you'd be if spending matched time elapsed.
                        Rectangle().fill(Palette.label).frame(width: 2, height: 14)
                            .offset(x: geo.size.width * pace.tickFraction - 1, y: -3)
                    }
                }
                .frame(height: 8)
                Text(paceHint(pace)).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(16)
            .contentCard(cornerRadius: 18)
        }
    }

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TOP CATEGORIES")
            VStack(spacing: 0) {
                ForEach(Array(topCategories.enumerated()), id: \.element.name) { idx, c in
                    if idx > 0 { Divider().padding(.leading, 60) }
                    HStack(spacing: 12) {
                        CategoryTile(category: c.name, size: 32)
                        Text(Categories.displayName(c.name)).font(.body).foregroundStyle(Palette.label)
                        Spacer()
                        Text(c.amount.formatMoney()).font(.body).foregroundStyle(Palette.secondaryLabel)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .contentCard(cornerRadius: 18)
        }
    }

    private var showInHistory: some View {
        Button(action: onShowInHistory) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("✈️").font(.caption)
                    Text("#\(trip.tag)").font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).frame(height: 24).background(Palette.tint, in: Capsule())
                Text("Show expenses").font(.body).foregroundStyle(Palette.label)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentCard(cornerRadius: 18)
    }

    private var endButton: some View {
        Button(action: onEnd) {
            Text("End trip").font(.body).foregroundStyle(Palette.bad)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .contentCard(cornerRadius: 18)
    }

    private func sectionLabel(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel).padding(.leading, 16)
    }

    private func paceLabel(_ s: TripPaceState) -> String {
        switch s {
        case .underPace: String(localized: "On track")
        case .overPace: String(localized: "Ahead of pace")
        case .overBudget: String(localized: "Over budget")
        }
    }
    private func paceColor(_ s: TripPaceState) -> Color {
        switch s {
        case .underPace: Palette.good
        case .overPace: Palette.warn
        case .overBudget: Palette.bad
        }
    }
    private func paceHint(_ pace: TripPace) -> String {
        if pace.remaining > 0 {
            return String(format: String(localized: "%@/day keeps you on budget"), pace.suggestedDaily.formatMoney())
        }
        return String(format: String(localized: "%@ over budget"), (-pace.remaining).formatMoney())
    }
}

// MARK: - Trip date formatting

enum TripDates {
    /// "12–20 Oct" / "28 Dec – 3 Jan" / "Open-ended".
    static func span(_ trip: Trip) -> String {
        guard let s = trip.startDate, let e = trip.endDate else { return String(localized: "Open-ended") }
        let cal = Calendar.current
        let sameMonth = cal.isDate(s, equalTo: e, toGranularity: .month)
        let d = DateFormatter(); d.setLocalizedDateFormatFromTemplate("d")
        let dMMM = DateFormatter(); dMMM.setLocalizedDateFormatFromTemplate("d MMM")
        if sameMonth {
            let mmm = DateFormatter(); mmm.setLocalizedDateFormatFromTemplate("MMM")
            return "\(d.string(from: s))–\(d.string(from: e)) \(mmm.string(from: e))"
        }
        return "\(dMMM.string(from: s)) – \(dMMM.string(from: e))"
    }

    /// "12–20 Oct · Active" for the active trip hero (the mockup's status line).
    static func spanWithStatus(_ trip: Trip) -> String {
        let base = trip.hasDates ? span(trip) : String(localized: "Open-ended")
        return "\(base) · \(String(localized: "Active"))"
    }
}
