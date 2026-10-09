//
//  PeriodBucketingTests.swift
//  BudgettyTests
//
//  Periods bucket a receipt by its PRINTED date (`Receipt.date`, and `LineItem.purchaseDate` for its
//  items), never by the upload moment (`createdAt`) — device-test bug 6: two receipts dated June /
//  September but scanned in October counted in October on iOS (1,424.81 €) and not on Android
//  (1,416.25 €). Android buckets by `TransactionEntity.timestamp`, the receipt's made-date. These pin
//  the shared accessor plus the pure call sites that can be driven without a view: the CSV/PDF export
//  window, its all-time bound, and the Travel-mode back-fill.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct PeriodBucketingTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private let cal = Calendar.current

    /// Noon local time, so the day never straddles a window boundary.
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func month(_ y: Int, _ m: Int) -> DateInterval {
        cal.dateInterval(of: .month, for: day(y, m, 15))!
    }

    @discardableResult
    private func receipt(_ ctx: ModelContext, store: String = "Lidl", uploaded: Date, dated: Date,
                         price: Decimal = Decimal(string: "8.56")!) -> Receipt {
        let r = Receipt(createdAt: uploaded, store: store, date: dated)
        ctx.insert(r)
        ctx.insert(LineItem(name: "Item", createdAt: uploaded, price: price, quantity: 1,
                            category: "Groceries", receipt: r))
        return r
    }

    @Test func lineItemPurchaseDateFollowsTheReceiptsPrintedDate() throws {
        let ctx = try makeContext()
        let r = receipt(ctx, uploaded: day(2026, 10, 2), dated: day(2026, 6, 15))
        try ctx.save()
        let item = try #require(r.items.first)
        #expect(item.purchaseDate == day(2026, 6, 15))
        #expect(item.createdAt == day(2026, 10, 2))   // the upload moment is kept for recency only

        // Editing the receipt's date moves its items with it.
        r.date = day(2026, 9, 1)
        #expect(item.purchaseDate == day(2026, 9, 1))
    }

    @Test func orphanLineItemFallsBackToItsUploadMoment() {
        let item = LineItem(name: "Loose", createdAt: day(2026, 10, 2), price: 1, quantity: 1)
        #expect(item.purchaseDate == day(2026, 10, 2))
    }

    @Test func exportCountsALateScannedReceiptInTheMonthItWasMade() throws {
        let ctx = try makeContext()
        let late = receipt(ctx, uploaded: day(2026, 10, 2), dated: day(2026, 6, 15))
        receipt(ctx, store: "Billa", uploaded: day(2026, 10, 3), dated: day(2026, 10, 3), price: 20)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Receipt>())

        func rows(_ window: DateInterval) -> [ExportRow] {
            ExportBuilder.buildData(receipts: all, income: [], interval: window, currencySymbol: "€",
                                    periodLabel: "", generatedLabel: "", totalRowLabel: "").rows
        }
        let june = rows(month(2026, 6))
        #expect(june.count == 1)
        #expect(june.first?.date == late.date)
        #expect(june.first?.amount == Decimal(string: "8.56"))
        let october = rows(month(2026, 10))
        #expect(october.count == 1)
        #expect(october.allSatisfy { $0.date != late.date })
    }

    @Test func allTimeStartsAtTheEarliestPrintedDate() throws {
        let ctx = try makeContext()
        receipt(ctx, uploaded: day(2026, 10, 2), dated: day(2026, 6, 15))
        receipt(ctx, uploaded: day(2026, 7, 1), dated: day(2026, 7, 1))
        try ctx.save()
        let iv = ExportPeriod.allTime.interval(startDay: 1, receipts: try ctx.fetch(FetchDescriptor<Receipt>()))
        #expect(iv.start == cal.startOfDay(for: day(2026, 6, 15)))
    }

    @Test func allTimeNeverTrapsOnAFutureDatedReceipt() throws {
        let ctx = try makeContext()
        let future = cal.date(byAdding: .day, value: 40, to: .now)!
        receipt(ctx, uploaded: .now, dated: future)   // a misread year/month lands in the future
        try ctx.save()
        let iv = ExportPeriod.allTime.interval(startDay: 1, receipts: try ctx.fetch(FetchDescriptor<Receipt>()))
        #expect(iv.start <= .now && iv.end > .now)
    }

    @Test func tripBackfillCatchesExpensesByPurchaseDateNotUploadTime() throws {
        let ctx = try makeContext()
        let floor = cal.startOfDay(for: day(2026, 9, 10))
        // Bought on the trip, scanned later — in.
        let onTrip = receipt(ctx, store: "Pastelaria", uploaded: day(2026, 9, 25), dated: day(2026, 9, 12))
        // Bought before the trip, but only scanned during it — out.
        receipt(ctx, store: "Home", uploaded: day(2026, 9, 14), dated: day(2026, 9, 1))
        try ctx.save()

        let items = TripOps.itemsSince(ctx, floor)
        #expect(items.count == 1)
        #expect(items.first?.receipt?.store == onTrip.store)
    }
}
