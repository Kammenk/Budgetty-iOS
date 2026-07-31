//
//  SubscriptionDetector.swift
//  Budgetty
//
//  On-device recurring-charge detection (Android's SubscriptionDetector + SubscriptionsViewModel).
//  Groups the app's own receipts by normalized merchant and keeps those that repeat at a regular
//  monthly or yearly cadence with a stable amount (≥ minCharges). No network, no bank — it only ever
//  sees receipts already on the device.
//

import Foundation

enum SubscriptionCadence { case monthly, yearly }

/// One charge from a merchant (one per receipt), fed into the detector.
struct MerchantCharge {
    let merchant: String
    let emoji: String
    let amount: Decimal
    let date: Date
}

/// A single charge inside a detected subscription's history.
struct SubCharge: Hashable { let amount: Decimal; let date: Date }

/// A detected price increase: oldAmount → newAmount starting on `since`.
struct PriceHike { let oldAmount: Decimal; let newAmount: Decimal; let since: Date }

/// A recurring merchant found by clustering its charges — never a bank feed, only the app's receipts.
struct DetectedSubscription: Identifiable {
    let merchant: String
    let emoji: String
    let cadence: SubscriptionCadence
    /// The current (most recent) charge amount.
    let amount: Decimal
    /// Amount normalized to a month (yearly ÷ 12), for the per-month total.
    let monthlyEquivalent: Decimal
    let lastCharge: Date
    let nextExpected: Date
    /// Day-of-month the charge tends to land, for prefilling a recurring bill.
    let dueDay: Int
    let charges: [SubCharge]
    let priceHike: PriceHike?

    var id: String { merchant }
    var chargeCount: Int { charges.count }
}

enum SubscriptionDetector {

    static let minCharges = 3
    private static let monthlyGap = 20...40   // days
    private static let yearlyGap = 300...430

    static func detect(_ charges: [MerchantCharge], today: Date = .now,
                       calendar cal: Calendar = .current) -> [DetectedSubscription] {
        Dictionary(grouping: charges, by: \.merchant)
            .compactMap { detectOne($0.value, today: today, cal: cal) }
            .sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
    }

    private static func detectOne(_ group: [MerchantCharge], today: Date,
                                  cal: Calendar) -> DetectedSubscription? {
        guard group.count >= minCharges else { return nil }
        let sorted = group.sorted { $0.date < $1.date }
        let dates = sorted.map { cal.startOfDay(for: $0.date) }
        let gaps = zip(dates, dates.dropFirst()).map { cal.dateComponents([.day], from: $0, to: $1).day ?? 0 }
        let cadence: SubscriptionCadence
        if gaps.allSatisfy({ monthlyGap.contains($0) }) { cadence = .monthly }
        else if gaps.allSatisfy({ yearlyGap.contains($0) }) { cadence = .yearly }
        else { return nil }

        // A subscription's price is stable (≤ 2 distinct amounts allows one hike/drop); a merchant
        // whose amount varies every time (groceries) is not one.
        let rounded = sorted.map { round2($0.amount) }
        let distinct = orderedUnique(rounded)
        guard distinct.count <= 2 else { return nil }

        let latest = sorted.last!
        let amount = round2(latest.amount)
        let monthly = cadence == .yearly ? round2(amount / 12) : amount
        let lastDate = latest.date
        let nextDate = cal.date(byAdding: cadence == .yearly ? .year : .month, value: 1, to: lastDate) ?? lastDate

        var hike: PriceHike?
        if distinct.count == 2 {
            let lower = distinct.min()!, higher = distinct.max()!
            if amount == higher, let since = sorted.first(where: { round2($0.amount) == higher })?.date {
                hike = PriceHike(oldAmount: lower, newAmount: higher, since: since)
            }
        }
        let emoji = mostCommon(group.map(\.emoji)) ?? latest.emoji

        return DetectedSubscription(
            merchant: latest.merchant, emoji: emoji, cadence: cadence, amount: amount,
            monthlyEquivalent: monthly, lastCharge: lastDate, nextExpected: nextDate,
            dueDay: cal.component(.day, from: lastDate),
            charges: sorted.reversed().map { SubCharge(amount: round2($0.amount), date: $0.date) },
            priceHike: hike)
    }

    static func round2(_ d: Decimal) -> Decimal {
        var v = d, r = Decimal()
        NSDecimalRound(&r, &v, 2, .plain)
        return r
    }
    private static func orderedUnique(_ xs: [Decimal]) -> [Decimal] {
        var seen = Set<Decimal>(); var out: [Decimal] = []
        for x in xs where seen.insert(x).inserted { out.append(x) }
        return out
    }
    private static func mostCommon<T: Hashable>(_ xs: [T]) -> T? {
        var counts: [T: Int] = [:]; for x in xs { counts[x, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }
}

/// A merchant close to detection (2..minCharges−1 charges), to nudge "one more and we'll flag it".
struct NearMiss { let merchant: String; let count: Int }

/// The whole detection snapshot for the entry card / list / detail — the iOS twin of Android's
/// SubscriptionsViewModel.uiState, computed from the receipts + the user's ignored set.
struct SubscriptionScan {
    var detected: [DetectedSubscription] = []
    var ignored: [DetectedSubscription] = []
    var monthlyTotal: Decimal = 0
    var yearlyTotal: Decimal = 0
    var receiptCount: Int = 0
    var nearestMiss: NearMiss?

    static func run(receipts: [Receipt], ignored ignoredMerchants: Set<String>,
                    today: Date = .now) -> SubscriptionScan {
        let charges = buildCharges(receipts)
        let all = SubscriptionDetector.detect(charges, today: today)
        let detected = all.filter { !ignoredMerchants.contains($0.merchant) }
        let ignored = all.filter { ignoredMerchants.contains($0.merchant) }
        let monthly = detected.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
        return SubscriptionScan(
            detected: detected, ignored: ignored,
            monthlyTotal: monthly, yearlyTotal: monthly * 12,
            receiptCount: charges.count,
            nearestMiss: nearestMiss(charges, detected: Set(all.map(\.merchant))))
    }

    /// One MerchantCharge per receipt: normalized store, the receipt's paid total, its date, and the
    /// dominant line-item category's emoji.
    private static func buildCharges(_ receipts: [Receipt]) -> [MerchantCharge] {
        receipts.compactMap { r in
            let merchant = StoreNormalizer.normalize(r.store)
            guard !merchant.isEmpty, r.paidTotal > 0 else { return nil }
            let cats = r.items.map(\.category)
            let dominant = mostCommon(cats) ?? cats.first ?? Categories.defaultName
            return MerchantCharge(merchant: merchant, emoji: Categories.emoji(for: dominant),
                                  amount: r.paidTotal, date: r.createdAt)
        }
    }

    private static func nearestMiss(_ charges: [MerchantCharge], detected: Set<String>) -> NearMiss? {
        Dictionary(grouping: charges, by: \.merchant)
            .filter { !detected.contains($0.key) }
            .mapValues(\.count)
            .filter { (2..<SubscriptionDetector.minCharges).contains($0.value) }
            .max { $0.value < $1.value }
            .map { NearMiss(merchant: $0.key, count: $0.value) }
    }

    private static func mostCommon<T: Hashable>(_ xs: [T]) -> T? {
        var counts: [T: Int] = [:]; for x in xs { counts[x, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }
}
