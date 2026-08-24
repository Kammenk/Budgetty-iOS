//
//  PlannedBillsSplitTest.swift
//  BudgettyTests
//
//  `splitPlannedBills` is the only new logic behind the Insights planned-bills overlay: it
//  de-duplicates a recurring bill against the period's receipts so a bill the user both planned and
//  logged/scanned is counted once (in spend), not twice. A bill matches a charge only when the names
//  align AND the amount is close; it is otherwise kept visible (conservative). A faithful port of
//  Android's `PlannedBillsSplitTest.kt` — same cases, same expectations.
//

import Testing
import Foundation
@testable import Budgetty

struct PlannedBillsSplitTest {

    private func bill(_ label: String, _ amount: String, match: String? = nil) -> PlannedBillLine {
        PlannedBillLine(label: label, category: "",
                        amount: Decimal(string: amount)!,
                        matchAmount: Decimal(string: match ?? amount)!)
    }

    private func charge(_ merchant: String, _ amount: String, date: Double = 1000) -> ReceiptCharge {
        ReceiptCharge(merchant: merchant, amount: Decimal(string: amount)!,
                      date: Date(timeIntervalSince1970: date))
    }

    @Test func unmatchedBillStaysVisible() {
        let split = splitPlannedBills(bills: [bill("Rent", "780")], charges: [])
        #expect(split.visible.map(\.label) == ["Rent"])
        #expect(split.matched.isEmpty)
    }

    @Test func matchedByNameAndCloseAmountIsHiddenAndCarriesReceiptFigure() {
        let split = splitPlannedBills(bills: [bill("Water", "18.40")],
                                      charges: [charge("Water", "18.40", date: 42)])
        #expect(split.visible.isEmpty)
        #expect(split.matched.map(\.label) == ["Water"])
        #expect(split.matched.first?.amount == Decimal(string: "18.40"))
        #expect(split.matched.first?.date == Date(timeIntervalSince1970: 42))
    }

    @Test func amountOutsideToleranceIsNotMatched() {
        // €50 bill vs €80 charge: diff €30 > max(€2, 15% = €7.50) → no match.
        let split = splitPlannedBills(bills: [bill("Gym", "50")], charges: [charge("Gym", "80")])
        #expect(split.visible.map(\.label) == ["Gym"])
        #expect(split.matched.isEmpty)
    }

    @Test func differentMerchantIsNotMatched() {
        let split = splitPlannedBills(bills: [bill("Netflix", "13")], charges: [charge("Lidl", "13")])
        #expect(split.visible.map(\.label) == ["Netflix"])
        #expect(split.matched.isEmpty)
    }

    @Test func merchantNameMatchIsCaseInsensitive() {
        let split = splitPlannedBills(bills: [bill("Netflix", "13")], charges: [charge("NETFLIX", "13")])
        #expect(split.visible.isEmpty)
        #expect(split.matched.count == 1)
    }

    @Test func oneChargeMatchesOnlyOneOfTwoSameNamedBills() {
        let split = splitPlannedBills(bills: [bill("Spotify", "10.99"), bill("Spotify", "10.99")],
                                      charges: [charge("Spotify", "10.99")])
        #expect(split.visible.count == 1)
        #expect(split.matched.count == 1)
    }

    @Test func billWithZeroWindowAmountIsDroppedEntirely() {
        let split = splitPlannedBills(bills: [bill("Rent", "0", match: "780")], charges: [])
        #expect(split.visible.isEmpty)
        #expect(split.matched.isEmpty)
    }

    @Test func dedupMatchesPerOccurrenceAmountNotMultiMonthWindowSum() {
        // A quarter view projects 3× rent (2340) but a single receipt is one month (780): still matches.
        let split = splitPlannedBills(bills: [bill("Rent", "2340", match: "780")],
                                      charges: [charge("Rent", "780")])
        #expect(split.visible.isEmpty)
        #expect(split.matched.count == 1)
    }

    @Test func variableBillWithin15PercentToleranceMatches() {
        // €200 bill, €215 charge: diff €15 <= 15% (€30) → match (a variable utility).
        let split = splitPlannedBills(bills: [bill("Electric", "200")], charges: [charge("Electric", "215")])
        #expect(split.visible.isEmpty)
        #expect(split.matched.count == 1)
    }

    @Test func theClosestEligibleChargeByAmountWins() {
        let split = splitPlannedBills(
            bills: [bill("Rent", "780")],
            charges: [charge("Rent", "800", date: 1), charge("Rent", "775", date: 2)])
        #expect(split.matched.count == 1)
        #expect(split.matched.first?.amount == Decimal(string: "775"))
    }
}
