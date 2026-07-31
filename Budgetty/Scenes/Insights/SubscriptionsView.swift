//
//  SubscriptionsView.swift
//  Budgetty
//
//  Subscription detection (Android's SubscriptionsUi / SubscriptionsScreen). The Insights entry card
//  (Premium summary or free teaser), the full list pushed from it, and the per-merchant detail with
//  charge history, a price-hike callout, and Track as bill / Ignore. On-device only — it reads the
//  receipts already in the app; nothing leaves the phone.
//

import SwiftUI
import SwiftData

// MARK: - Insights entry card

struct SubscriptionsCard: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var ignoredRows: [IgnoredSubscription]
    @AppStorage(SettingsKey.premium) private var premium = false
    @State private var showPaywall = false

    private var scan: SubscriptionScan {
        SubscriptionScan.run(receipts: receipts, ignored: Set(ignoredRows.map(\.merchant)))
    }

    var body: some View {
        let scan = scan
        if !scan.detected.isEmpty {
            if premium {
                NavigationLink { SubscriptionsListView() } label: { premiumCard(scan) }
                    .buttonStyle(.plain)
            } else {
                teaserCard(scan)
                    .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
            }
        }
    }

    private func premiumCard(_ scan: SubscriptionScan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscriptions").font(.headline).foregroundStyle(Palette.label)
                    Text("\(scan.detected.count) found in your receipts")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryLabel)
            }
            HStack(spacing: 10) {
                subStatTile("Per month", scan.monthlyTotal.formatMoney())
                subStatTile("Per year", scan.yearlyTotal.formatMoney())
            }
            ForEach(scan.detected.prefix(3)) { SubPreviewRow(sub: $0) }
            Text("See all \(scan.detected.count) ›").font(.subheadline).fontWeight(.bold)
                .foregroundStyle(Palette.tint)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private func teaserCard(_ scan: SubscriptionScan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Subscriptions").font(.headline).foregroundStyle(Palette.label)
                Spacer()
                SubLockBadge()
            }
            Text("We found \(scan.detected.count) recurring charges")
                .font(.headline).padding(.top, 8)
            Text("About \(scan.monthlyTotal.formatMoney()) a month, spotted in your own receipts on this phone — no bank connection.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.top, 2)
            VStack(spacing: 10) {
                ForEach(Array(scan.detected.prefix(3).enumerated()), id: \.offset) { _, sub in
                    SubRedactedRow(emoji: sub.emoji)
                }
            }
            .padding(.vertical, 14)
            Button { showPaywall = true } label: {
                Text("Unlock with Premium").font(.subheadline).fontWeight(.bold).ctaPill(height: 48)
            }
            Text("Unlocks the full list, price-hike alerts and Track as bill.")
                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
        }
        .padding(18)
        .contentCard(cornerRadius: 16)
    }

    private func subStatTile(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryLabel)
            Text(value).font(.title3).fontWeight(.bold).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - List

struct SubscriptionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var ignoredRows: [IgnoredSubscription]

    private var scan: SubscriptionScan {
        SubscriptionScan.run(receipts: receipts, ignored: Set(ignoredRows.map(\.merchant)))
    }

    var body: some View {
        let scan = scan
        ScrollView {
            VStack(spacing: 16) {
                if scan.detected.isEmpty && scan.ignored.isEmpty {
                    emptyContent(scan)
                } else {
                    listContent(scan)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .adaptiveReadableWidth(Dimens.contentMaxWidth)
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Subscriptions").navigationBarTitleDisplayMode(.inline)
        .coversFloatingDock()
    }

    @ViewBuilder
    private func listContent(_ scan: SubscriptionScan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Detected subscriptions").font(.caption).foregroundStyle(Palette.secondaryLabel)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(scan.monthlyTotal.formatMoney()).font(.title).fontWeight(.bold)
                Text("/ month").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            }
            Text("\(scan.detected.count) subscriptions · \(scan.yearlyTotal.formatMoney()) a year")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            Text("Found on this phone by matching repeat charges in your receipts. Yearly items count as one twelfth per month.")
                .font(.caption2).foregroundStyle(Palette.secondaryLabel).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .contentCard(cornerRadius: 16)

        VStack(spacing: 0) {
            ForEach(Array(scan.detected.enumerated()), id: \.element.id) { idx, sub in
                NavigationLink { SubscriptionDetailView(sub: sub) } label: {
                    SubPreviewRow(sub: sub).padding(14)
                }
                .buttonStyle(.plain)
                if idx < scan.detected.count - 1 { Divider().padding(.leading, 60) }
            }
        }
        .contentCard(cornerRadius: 16)

        if !scan.ignored.isEmpty {
            HStack(spacing: 8) {
                Text("Ignored").font(.subheadline).fontWeight(.bold)
                Text("Hidden from the list and the totals").font(.caption2).foregroundStyle(Palette.secondaryLabel)
                Spacer()
            }
            VStack(spacing: 12) {
                ForEach(scan.ignored) { sub in
                    VStack(spacing: 8) {
                        SubPreviewRow(sub: sub)
                        HStack {
                            Text("Detection still sees it — it just stays out of your way.")
                                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                            Spacer()
                            Button("Restore") { restore(sub.merchant) }
                                .font(.caption).fontWeight(.bold).foregroundStyle(Palette.tint)
                        }
                    }
                }
            }
            .padding(14)
            .contentCard(cornerRadius: 16)
        }

        Text("Detection runs on your device. Nothing leaves the phone, and no bank is connected.")
            .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func emptyContent(_ scan: SubscriptionScan) -> some View {
        VStack(spacing: 8) {
            EmojiChip("🔁", size: 46)
            Text("Nothing repeating yet").font(.subheadline).fontWeight(.bold)
            Text("We'll spot recurring charges as you add more receipts. It usually takes about three charges from the same merchant.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(18)
        .contentCard(cornerRadius: 16)

        if let miss = scan.nearestMiss {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Receipts so far").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Text("\(scan.receiptCount)").font(.subheadline).fontWeight(.bold)
                }
                Text("Closest so far: \(miss.count) charges from \(miss.merchant) — one more and we'll flag it.")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(14).contentCard(cornerRadius: 16)
        }
        Text("Detection runs on your device. Nothing leaves the phone, and no bank is connected.")
            .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func restore(_ merchant: String) {
        if let row = ignoredRows.first(where: { $0.merchant == merchant }) {
            context.delete(row); try? context.save()
        }
    }
}

// MARK: - Detail

struct SubscriptionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let sub: DetectedSubscription
    @State private var showTrack = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let hike = sub.priceHike { hikeCard(hike) }
                historyCard
                Button { showTrack = true } label: {
                    Label("Track as bill", systemImage: "plus").font(.subheadline).fontWeight(.bold)
                        .ctaPill(height: 50)
                }
                Text("Creates a recurring bill — it then counts in Safe to spend and upcoming bills.")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Button { ignore() } label: {
                    Label("Ignore this merchant", systemImage: "minus")
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.tint)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Palette.tintSoft, in: Capsule())
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .adaptiveReadableWidth(Dimens.contentMaxWidth)
        }
        .background(Palette.groupedBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) { EmojiChip(sub.emoji, size: 24); Text(sub.merchant).font(.headline).lineLimit(1) }
            }
        }
        .coversFloatingDock()
        .sheet(isPresented: $showTrack) {
            TrackAsBillSheet(sub: sub) { dismiss() }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                EmojiChip(sub.emoji, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.merchant).font(.headline).lineLimit(1)
                    Text(cadenceLabel(sub.cadence)).font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
                Text(sub.amount.formatMoney()).font(.headline)
            }
            HStack(spacing: 0) {
                subStat("Last", Self.dayMonth(sub.lastCharge))
                subVDivider
                subStat("Next ~", Self.dayMonth(sub.nextExpected))
                subVDivider
                subStat("Charges", "\(sub.chargeCount)")
            }
        }
        .padding(18).frame(maxWidth: .infinity).contentCard(cornerRadius: 16)
    }

    private func hikeCard(_ hike: PriceHike) -> some View {
        let delta = hike.newAmount - hike.oldAmount
        let annual = delta * 12
        return VStack(alignment: .leading, spacing: 4) {
            Text("↑ \(delta.formatMoney()) since \(Self.dayMonth(hike.since))")
                .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.warn)
            Text("\(hike.oldAmount.formatMoney()) → \(hike.newAmount.formatMoney()) from that charge onward. About \(annual.formatMoney()) more over a year.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).contentCard(cornerRadius: 16)
    }

    private var historyCard: some View {
        VStack(spacing: 0) {
            let charges = Array(sub.charges.prefix(6))
            ForEach(Array(charges.enumerated()), id: \.offset) { idx, c in
                HStack {
                    Text(Self.dayMonth(c.date)).font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    if sub.priceHike?.since == c.date {
                        Text("price up").font(.caption2).fontWeight(.bold).foregroundStyle(Palette.warn)
                            .padding(.trailing, 8)
                    }
                    Text(c.amount.formatMoney()).font(.subheadline).fontWeight(.bold)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if idx < charges.count - 1 { Divider().padding(.horizontal, 16) }
            }
        }
        .contentCard(cornerRadius: 16)
    }

    private func subStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryLabel)
            Text(value).font(.subheadline).fontWeight(.bold).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    private var subVDivider: some View { Rectangle().fill(Palette.separator).frame(width: 1, height: 30) }

    private func ignore() {
        context.insert(IgnoredSubscription(merchant: sub.merchant))
        try? context.save()
        dismiss()
    }

    static func dayMonth(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f.string(from: date)
    }
}

// MARK: - Track as bill sheet

struct TrackAsBillSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let sub: DetectedSubscription
    /// Called after the bill is saved, so the detail can pop back to the list.
    var onSaved: () -> Void

    @State private var amount: Decimal = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        EmojiChip(sub.emoji, size: 32)
                        Text(sub.merchant).font(.body).fontWeight(.semibold)
                    }
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Prefilled from what we detected. Change anything before you save.")
                        .textCase(nil)
                }
                Section {
                    Text("\(cadenceLabel(sub.cadence)) · next \(SubscriptionDetailView.dayMonth(sub.nextExpected))")
                        .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                } footer: {
                    Text("Saved bills show up in upcoming bills and count against Safe to spend until you mark them paid.")
                }
            }
            .navigationTitle("Track as recurring bill").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add bill") { save() }.disabled(amount <= 0)
                }
            }
            .onAppear { amount = sub.amount }
        }
    }

    private func save() {
        let bill = Recurring(label: sub.merchant, amount: amount, isIncome: false,
                             category: "Subscriptions",
                             cadence: sub.cadence == .yearly ? .yearly : .monthly, dueDay: sub.dueDay)
        context.insert(bill)
        try? context.save()
        dismiss()
        onSaved()
    }
}

// MARK: - Shared bits

func cadenceLabel(_ c: SubscriptionCadence) -> String {
    String(localized: c == .yearly ? "Yearly" : "Monthly")
}

/// A merchant row: emoji + name (+ price-hike pill), cadence/next line, amount.
struct SubPreviewRow: View {
    let sub: DetectedSubscription
    var body: some View {
        HStack(spacing: 12) {
            EmojiChip(sub.emoji, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sub.merchant).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    if let hike = sub.priceHike { PriceHikePill(hike: hike) }
                }
                Text("\(cadenceLabel(sub.cadence)) · next ~\(SubscriptionDetailView.dayMonth(sub.nextExpected))")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(sub.amount.formatMoney()).font(.subheadline).fontWeight(.bold)
        }
    }
}

struct PriceHikePill: View {
    let hike: PriceHike
    var body: some View {
        Text("↑ \((hike.newAmount - hike.oldAmount).formatMoney())")
            .font(.caption2).fontWeight(.bold).foregroundStyle(Palette.warn)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Palette.warn, lineWidth: 1))
    }
}

struct SubLockBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("Premium").font(.caption2).fontWeight(.bold)
        }
        .foregroundStyle(Palette.secondaryLabel)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(Palette.separatorStrong, lineWidth: 1))
    }
}

private struct SubRedactedRow: View {
    let emoji: String
    var body: some View {
        HStack(spacing: 12) {
            EmojiChip(emoji, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                redactBar(0.55, 11)
                redactBar(0.4, 8)
            }
            Spacer(minLength: 8)
            Capsule().fill(Palette.separator).frame(width: 44, height: 11)
        }
    }
    private func redactBar(_ fraction: CGFloat, _ height: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule().fill(Palette.separator).frame(width: geo.size.width * fraction, height: height)
        }
        .frame(height: height)
    }
}
