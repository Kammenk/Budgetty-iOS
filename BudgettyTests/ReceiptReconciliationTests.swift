//
//  ReceiptReconciliationTests.swift
//  BudgettyTests
//
//  The total-anchor reconciliation lifted out of APIReceiptExtractor — the highest-value logic on
//  the scan path (mirrors Android's total-anchor). Verifies the paid total lands on the printed grand
//  total, that already-materialized charge rows are netted out (no double-counting), and that
//  cent-rounding noise is ignored.
//

import Testing
import Foundation
@testable import Budgetty

struct ReceiptReconciliationTests {
    private func resolve(printed: String, items: String, discount: String = "0", tax: String = "0",
                         taxOnTop: Bool = false, charges: String = "0") -> Decimal {
        APIReceiptExtractor.resolveExtraCharges(
            printedTotal: Decimal(string: printed)!, itemsSum: Decimal(string: items)!,
            discount: Decimal(string: discount)!, tax: Decimal(string: tax)!,
            taxOnTop: taxOnTop, chargesTotal: Decimal(string: charges)!)
    }

    @Test func noPrintedTotalMeansNoExtraCharges() {
        #expect(resolve(printed: "0", items: "10.00") == .zero)
    }

    @Test func unexplainedGapBecomesExtraCharges() {
        // items 10, nothing else, printed 12 → a 2.00 deposit/fee not itemised.
        #expect(resolve(printed: "12.00", items: "10.00") == Decimal(string: "2.00")!)
    }

    @Test func materialisedChargesAreNettedOutNotDoubleCounted() {
        // The 2.00 gap is fully explained by an already-added delivery row → no extra invisible add-on.
        #expect(resolve(printed: "12.00", items: "10.00", charges: "2.00") == .zero)
        // A partial: 3.00 gap, 2.00 already a row → 1.00 residual stays invisible.
        #expect(resolve(printed: "13.00", items: "10.00", charges: "2.00") == Decimal(string: "1.00")!)
    }

    @Test func subFiveCentGapIsRoundingNoise() {
        #expect(resolve(printed: "10.03", items: "10.00") == .zero)
        // Exactly 5 cents is the threshold and does count.
        #expect(resolve(printed: "10.05", items: "10.00") == Decimal(string: "0.05")!)
    }

    @Test func discountAndOnTopTaxFeedTheReconciliation() {
        // reconciled = 10 − 3 = 7, printed 8 → gap 1.
        #expect(resolve(printed: "8.00", items: "10.00", discount: "3.00") == Decimal(string: "1.00")!)
        // taxOnTop lifts reconciled: 10 + 2 = 12, printed 13 → gap 1.
        #expect(resolve(printed: "13.00", items: "10.00", tax: "2.00", taxOnTop: true) == Decimal(string: "1.00")!)
        // Same numbers but tax NOT on top: reconciled stays 10, printed 13 → gap 3.
        #expect(resolve(printed: "13.00", items: "10.00", tax: "2.00", taxOnTop: false) == Decimal(string: "3.00")!)
    }

    @Test func normalizedCategoryFallsBackToDefault() {
        #expect(APIReceiptExtractor.normalizedCategory(nil) == Categories.defaultName)
        #expect(APIReceiptExtractor.normalizedCategory("") == Categories.defaultName)
        #expect(APIReceiptExtractor.normalizedCategory("Bakery") == "Bakery")
        #expect(APIReceiptExtractor.normalizedCategory("not-a-real-category") == Categories.defaultName)
    }
}
