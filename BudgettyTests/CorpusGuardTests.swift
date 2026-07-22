//
//  CorpusGuardTests.swift
//  BudgettyTests
//
//  Runs the extraction guards against the REAL labeled receipts in the Android repo's eval corpus
//  (`functions/eval/corpus`) — hand-verified ground truth from actual photos, not invented fixtures.
//
//  Every case below is a receipt the extractor read CORRECTLY, so the only acceptable outcome is
//  "accepted". That is the assertion that matters: these guards are 100% client-side, so a false
//  rejection reaches users as "Couldn't read that receipt" on a perfectly good photo and can only be
//  loosened by shipping a release. Android learned this from `gr-multibuy-units` — a tester hit it
//  five times over two days.
//
//  Baskets were reconstructed from each case's `lineTotals` by script, not transcribed by hand;
//  multi-buy quantities come from the case's own `_description` and reproduce its printed unit count.
//  Cases whose ground truth records no per-line detail can't be reconstructed and are absent.
//

import Foundation
import Testing
@testable import Budgetty

struct CorpusGuardTests {
    private struct Corpus {
        let name: String
        let printedItemCount: Int
        let total: Double
        let discount: Double
        /// (quantity, unit price) per line.
        let items: [(Int, Double)]
    }

    private static let cases: [Corpus] = [
        // bg-cooolbox-invoice: 1 lines / 1 units, printed count 0
        Corpus(name: "bg-cooolbox-invoice", printedItemCount: 0, total: 14.27,
               discount: 0, items: [(1, 11.89)]),
        // bg-hesburger-eur: 2 lines / 2 units, printed count 2
        Corpus(name: "bg-hesburger-eur", printedItemCount: 2, total: 12.93,
               discount: 0, items: [(1, 11.04), (1, 1.89)]),
        // bg-kaufland-interleaved: 9 lines / 9 units, printed count 0
        Corpus(name: "bg-kaufland-interleaved", printedItemCount: 0, total: 32.31,
               discount: 1.2, items: [(1, 8.68), (1, 3.09), (1, 2.19), (1, 1.99), (1, 1.63), (1, 8.38), (1, 3.32), (1, 3.98), (1, 0.25)]),
        // bg-stasi-produce: 10 lines / 10 units, printed count 10
        Corpus(name: "bg-stasi-produce", printedItemCount: 10, total: 13.82,
               discount: 0, items: [(1, 0.89), (1, 1.22), (1, 0.23), (1, 2.41), (1, 0.62), (1, 1.47), (1, 0.8), (1, 1.04), (1, 0.13), (1, 5.01)]),
        // eu-supermarket-multivat: 9 lines / 9 units, printed count 9
        Corpus(name: "eu-supermarket-multivat", printedItemCount: 9, total: 20,
               discount: 1.49, items: [(1, 1.1), (1, 0.89), (1, 2.35), (1, 2.19), (1, 1.95), (1, 2.64), (1, 1.89), (1, 3.49), (1, 4.99)]),
        // gr-multibuy-units: 9 lines / 18 units, printed count 18
        Corpus(name: "gr-multibuy-units", printedItemCount: 18, total: 17.49,
               discount: 0.78, items: [(1, 1.87), (1, 0.14), (1, 2.11), (4, 0.34), (1, 0.65), (1, 1.54), (6, 1.42), (2, 0.11), (1, 1.86)]),
    ]

    /// Not one correctly-read real receipt may be rejected.
    @Test func everyCorrectlyReadReceiptIsAccepted() {
        for c in Self.cases {
            let drafts = c.items.enumerated().map { index, pair in
                ExtractedDraftItem(name: "Item \(index)", quantity: pair.0,
                                   price: Decimal.fromDouble(pair.1), category: Categories.defaultName)
            }
            let response = ExtractResponse(discount: c.discount, total: c.total,
                                           readable: true, printedItemCount: c.printedItemCount)
            #expect(throws: Never.self, "\(c.name) was rejected — a false rejection on a real receipt") {
                try APIReceiptExtractor.validate(response, items: drafts)
            }
        }
    }

    /// The Greek receipt whose printed "ΣΥΝΟΛΟ ΕΙΔΩΝ 18" counts UNITS across 9 lines — the exact
    /// shape that made Android reject a readable photo. Pinned separately so a regression names it.
    @Test func greekMultiBuyUnitsCaseIsAccepted() throws {
        let c = try #require(Self.cases.first(where: { $0.name == "gr-multibuy-units" }))
        #expect(c.printedItemCount == 18)
        #expect(c.items.count == 9)
        #expect(c.items.reduce(0) { $0 + $1.0 } == 18)

        // Non-vacuity: the LINE reading is deliberately out of band (9 < 18 × 0.6), so this receipt
        // survives only because the guard also tries the UNIT reading. If this assertion ever fails,
        // the case has stopped exercising the bug it was written for and the acceptance above is
        // proving nothing.
        let lowerBound = Double(c.printedItemCount) * 0.6
        #expect(Double(c.items.count) < lowerBound)
        #expect(Double(c.items.reduce(0) { $0 + $1.0 }) >= lowerBound)
    }
}
