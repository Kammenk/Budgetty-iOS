//
//  ExtractionGuardTests.swift
//  BudgettyTests
//
//  The scan guards decide whether a basket reaches review at all, and they are 100% client-side — a
//  wrong threshold can only be loosened by shipping an app release, never by a deploy. That makes
//  false rejections the expensive failure, so these tests lean on the cases that must NOT be
//  rejected: notably the multi-buy receipt Android's first version turned away (`1d12a44`).
//

import Foundation
import Testing
@testable import Budgetty

struct ExtractionGuardTests {
    /// Builds a response/items pair; `items` is (quantity, price) per line.
    private func fixture(
        printedItemCount: Int?, total: Double?, discount: Double? = nil, items: [(Int, Double)]
    ) -> (ExtractResponse, [ExtractedDraftItem]) {
        let drafts = items.enumerated().map { index, pair in
            ExtractedDraftItem(
                name: "Item \(index)",
                quantity: pair.0,
                price: Decimal.fromDouble(pair.1),
                category: Categories.defaultName
            )
        }
        // Memberwise init: arguments must follow declaration order (discount before total,
        // readable before printedItemCount); the other optionals default to nil.
        let response = ExtractResponse(
            discount: discount, total: total, readable: true, printedItemCount: printedItemCount
        )
        return (response, drafts)
    }

    private func accepts(_ pair: (ExtractResponse, [ExtractedDraftItem])) -> Bool {
        do { try APIReceiptExtractor.validate(pair.0, items: pair.1); return true }
        catch { return false }
    }

    // MARK: - Article count

    /// The regression Android shipped and had to fix: a receipt whose printed count is UNITS, not
    /// lines. Three lines totalling twelve units against a printed 12 must pass on the unit reading.
    @Test func multiBuyReceiptIsAccepted() {
        #expect(accepts(fixture(printedItemCount: 12, total: 20,
                                items: [(6, 1.42), (4, 1.10), (2, 3.00)])))
    }

    /// The other valid reading: the printed count matches the number of lines.
    @Test func lineCountReadingIsAccepted() {
        #expect(accepts(fixture(printedItemCount: 4, total: 20,
                                items: [(1, 5.0), (1, 5.0), (1, 5.0), (1, 5.0)])))
    }

    /// Matching neither reading is a genuine misread — half the lines were dropped.
    @Test func countMatchingNeitherReadingIsRejected() {
        #expect(!accepts(fixture(printedItemCount: 12, total: 20, items: [(1, 5.0), (1, 5.0)])))
    }

    /// A small printed count is too weak a signal to reject on.
    @Test func smallPrintedCountIsNotChecked() {
        #expect(accepts(fixture(printedItemCount: 2, total: 20, items: [(1, 5.0)])))
        #expect(accepts(fixture(printedItemCount: nil, total: 20, items: [(1, 5.0)])))
    }

    // MARK: - Money sanity

    /// Lines overshooting the printed total by a wide margin mean invented or duplicated rows.
    @Test func wildOvershootIsRejected() {
        #expect(!accepts(fixture(printedItemCount: nil, total: 10, items: [(1, 40.0)])))
    }

    /// The discount the model itself reported is netted off first, so a couponed basket that looks
    /// like an overshoot on paper still passes.
    @Test func discountIsNettedBeforeJudgingOvershoot() {
        #expect(accepts(fixture(printedItemCount: nil, total: 10, discount: 30, items: [(1, 40.0)])))
    }

    /// Deposits and fees only ever raise a total, so undershooting is never a rejection — that case
    /// is the review screen's job, not the guard's.
    @Test func undershootIsNeverRejected() {
        #expect(accepts(fixture(printedItemCount: nil, total: 100, items: [(1, 5.0)])))
    }

    /// No printed total means nothing to compare against.
    @Test func missingTotalSkipsTheMoneyCheck() {
        #expect(accepts(fixture(printedItemCount: nil, total: nil, items: [(1, 999.0)])))
    }
}
