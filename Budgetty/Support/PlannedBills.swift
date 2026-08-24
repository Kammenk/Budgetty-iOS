//
//  PlannedBills.swift
//  Budgetty
//
//  Projects recurring bills onto an Insights period as a distinct "planned" layer, and de-duplicates
//  a bill the user also logged/scanned so it's never double-counted. A direct port of the planned-
//  bills half of Android's `RecurringMath.kt` (`splitPlannedBills` + the dedup matcher) — pure value
//  types with no SwiftUI deps, so the dedup rule is unit-testable (see PlannedBillsSplitTest).
//

import Foundation

/// One recurring bill projected onto the selected Insights window, for the planned overlay.
struct PlannedBillLine: Equatable {
    let label: String
    let category: String
    /// The bill's contribution to the whole selected window (`windowAmount`) — what the overlay draws
    /// and sums (e.g. one month's rent for a month view).
    let amount: Decimal
    /// The bill's single-occurrence amount (`Recurring.amount`) — what one real receipt for it would
    /// show, used only for dedup matching (never for display).
    let matchAmount: Decimal
}

/// The receipt-side signal the dedup matcher compares bills against: one per receipt in the window —
/// its normalized `merchant`, paid `amount` (total) and `date`.
struct ReceiptCharge {
    let merchant: String
    let amount: Decimal
    let date: Date
}

/// A planned bill excluded from the overlay because it already matches a real receipt in the window —
/// so it's counted once, in spend, not twice. Surfaced in the Breakdown sheet's dedup note.
struct MatchedBillLine: Equatable {
    let label: String
    let amount: Decimal
    let date: Date
}

/// The split of a period's recurring bills into the `visible` planned layer (largest first) and the
/// `matched` bills hidden as already-counted-in-spend.
struct PlannedBillsSplit: Equatable {
    let visible: [PlannedBillLine]
    let matched: [MatchedBillLine]
}

/// Shortest normalized name length that may match, so 1–2 char noise can't false-match.
private let MIN_MATCH_NAME_LEN = 3

/// Lowercased, brand-canonicalized merchant/label for comparison (so "Netflix" ↔ a Netflix receipt).
private func normalizeMerchant(_ raw: String) -> String {
    StoreNormalizer.normalize(raw).lowercased().trimmingCharacters(in: .whitespaces)
}

/// Whether two normalized names refer to the same merchant: equal, or one contains the other where
/// the shorter is at least `MIN_MATCH_NAME_LEN` chars (so "spotify" ↔ "spotify premium" match).
private func namesAlign(_ a: String, _ b: String) -> Bool {
    if a.count < MIN_MATCH_NAME_LEN || b.count < MIN_MATCH_NAME_LEN { return a == b && !a.isEmpty }
    return a == b || a.contains(b) || b.contains(a)
}

/// Whether a receipt total is close enough to a bill's occurrence amount to be the same payment:
/// within the greater of €2 or 15% of the bill (covers variable utilities without over-matching).
private func amountsClose(_ chargeTotal: Decimal, _ billAmount: Decimal) -> Bool {
    let tolerance = max(abs(billAmount) * Decimal(string: "0.15")!, Decimal(string: "2.00")!)
    return abs(chargeTotal - billAmount) <= tolerance
}

/// Splits `bills` into the planned layer the overlay draws and the bills already represented by a real
/// receipt in the same window (`matched`) — so a bill the user both *planned* and *logged/scanned* is
/// counted once (in spend), never twice.
///
/// A bill matches a `charge` when **both** hold: their names align (each `normalizeMerchant`-d, one
/// containing the other by ≥ `MIN_MATCH_NAME_LEN` chars) and the charge total is within tolerance of
/// the bill's single-occurrence `matchAmount`. Each charge is consumed by at most one bill (the closest
/// by amount), so two same-name bills can't both claim one receipt. Deliberately conservative: an
/// unmatched bill stays *visible* rather than risk hiding a genuinely unpaid plan. Bills with a
/// non-positive window `amount` (e.g. a plan not yet created for this window — no back-projection) are
/// dropped entirely. Android parity: `RecurringMath.splitPlannedBills`.
func splitPlannedBills(bills: [PlannedBillLine], charges: [ReceiptCharge]) -> PlannedBillsSplit {
    let present = bills.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    var visible: [PlannedBillLine] = []
    var matched: [MatchedBillLine] = []
    var available = charges

    for bill in present {
        let billName = normalizeMerchant(bill.label)
        var bestIdx: Int?
        var bestDelta: Decimal = 0
        for (i, charge) in available.enumerated()
        where namesAlign(billName, normalizeMerchant(charge.merchant))
            && amountsClose(charge.amount, bill.matchAmount) {
            let delta = abs(charge.amount - bill.matchAmount)
            if bestIdx == nil || delta < bestDelta { bestIdx = i; bestDelta = delta }
        }
        if let bi = bestIdx {
            let hit = available.remove(at: bi)
            matched.append(MatchedBillLine(label: bill.label, amount: hit.amount, date: hit.date))
        } else {
            visible.append(bill)
        }
    }
    return PlannedBillsSplit(
        visible: visible.sorted { $0.amount > $1.amount },
        matched: matched.sorted { $0.date > $1.date }
    )
}

/// The planned recurring-bills overlay for the selected Insights period — the "planned" layer drawn
/// alongside (never merged into) actual receipt spend. `plannedTotal` and `bills` are already
/// de-duplicated: a bill matching a real receipt in the window is moved to `matched` (counted once, in
/// spend) and excluded here. Android parity: `InsightsViewModel.PlannedOverlay`.
struct PlannedOverlay: Equatable {
    var plannedTotal: Decimal = 0
    /// Visible planned bills for the window, largest first — the donut wedge's makeup and the
    /// Breakdown sheet's per-bill list.
    var bills: [PlannedBillLine] = []
    /// Bills hidden because they already match a receipt this period — the dedup note's list.
    var matched: [MatchedBillLine] = []

    var hasPlanned: Bool { plannedTotal > 0 }
    static let empty = PlannedOverlay()

    /// Builds the overlay for `window`: each bill projected onto the window (`windowAmount`, so no
    /// back-projection), de-duplicated against the window's `receipts`. Android parity:
    /// `InsightsViewModel.computePlannedOverlay`.
    static func build(bills recurringBills: [Recurring],
                      window: DateInterval,
                      receipts: [Receipt],
                      calendar cal: Calendar = .current) -> PlannedOverlay {
        let billLines = recurringBills.map { b in
            PlannedBillLine(label: b.label, category: b.category,
                            amount: b.windowAmount(window, calendar: cal), matchAmount: b.amount)
        }
        // One charge per receipt (normalized store, paid total, date) — the same primitive the
        // subscription detector builds, so bill↔receipt matching stays consistent.
        let charges = receipts.compactMap { r -> ReceiptCharge? in
            let merchant = StoreNormalizer.normalize(r.store)
            guard !merchant.isEmpty, r.paidTotal > 0 else { return nil }
            return ReceiptCharge(merchant: merchant, amount: r.paidTotal, date: r.createdAt)
        }
        let split = splitPlannedBills(bills: billLines, charges: charges)
        let total = split.visible.reduce(Decimal.zero) { $0 + $1.amount }
        return PlannedOverlay(plannedTotal: total, bills: split.visible, matched: split.matched)
    }
}
