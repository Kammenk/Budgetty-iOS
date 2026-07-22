//
//  ReceiptExtractor.swift
//  Budgetty
//
//  Turns a receipt image into an editable draft. `APIReceiptExtractor` calls the real Cloud Function;
//  `StubReceiptExtractor` returns canned data so the review/edit UI is exercisable on the Simulator
//  (which has no camera and, until the plist lands, no Firebase token).
//

import Foundation
import UIKit

/// One extracted line, ready to seed an editable draft.
struct ExtractedDraftItem {
    var name: String
    var quantity: Int
    var price: Decimal
    var category: String
}

/// The whole extracted receipt, with the money add-ons resolved so paid-total anchors on the printed
/// grand total (mirrors the Android extractor's total-anchor logic, see receipt-total memory).
struct ExtractionResult {
    var store: String
    var date: Date
    var discount: Decimal
    var tax: Decimal
    var taxOnTop: Bool
    var extraCharges: Decimal
    var items: [ExtractedDraftItem]
    var readable: Bool
    /// The receipt's printed subtotal lifted by the materialized charge rows — the clean anchor the
    /// review screen's dropped-line check compares the item sum against. nil when nothing was printed.
    var printedSubtotal: Decimal?
}

enum ExtractError: LocalizedError {
    case unreadable
    var errorDescription: String? {
        "This image was too hard to read. Try again with a clearer, flat, well-lit photo."
    }
}

protocol ReceiptExtractor {
    func extract(_ image: UIImage) async throws -> ExtractionResult
}

// MARK: - Real, backend-backed extractor

struct APIReceiptExtractor: ReceiptExtractor {
    var api = ReceiptAPI()
    var tokens: TokenProvider

    func extract(_ image: UIImage) async throws -> ExtractionResult {
        guard let data = image.jpegData(compressionQuality: 0.7) else { throw ExtractError.unreadable }
        let token = try await tokens.idToken()
        let resp = try await api.extract(imageData: data, mimeType: "image/jpeg", token: token)

        if resp.readable == false { throw ExtractError.unreadable }

        let items = resp.items.map { raw in
            ExtractedDraftItem(
                name: raw.name,
                quantity: max(1, Int((raw.quantity ?? 1).rounded())),
                price: Decimal.fromDouble(raw.price),
                category: Self.normalizedCategory(raw.category)
            )
        }
        if items.isEmpty { throw ExtractError.unreadable }
        try Self.validate(resp, items: items)

        let discount = Decimal.fromDouble(resp.discount)
        let tax = Decimal.fromDouble(resp.tax)
        let taxOnTop = tax > 0
        let itemsSum = items.reduce(Decimal.zero) { $0 + $1.price * Decimal($1.quantity) }

        // Delivery/service/bag fees and a tip, each materialized as its own visible line item (in the
        // Delivery / Tips categories) instead of vanishing into the invisible total-gap. Driven by the
        // model's explicit amounts, so they're captured even when the printed grand total is misread.
        var chargeItems: [ExtractedDraftItem] = []
        if let fee = Self.chargeAmount(resp.deliveryAndFees) {
            chargeItems.append(ExtractedDraftItem(name: String(localized: "Delivery & fees"), quantity: 1, price: fee, category: "Delivery"))
        }
        if let tip = Self.chargeAmount(resp.tip) {
            chargeItems.append(ExtractedDraftItem(name: String(localized: "Tip"), quantity: 1, price: tip, category: "Tips"))
        }
        let chargesTotal = chargeItems.reduce(Decimal.zero) { $0 + $1.price }

        let printedTotal = Decimal.fromDouble(resp.total)
        let extraCharges = Self.resolveExtraCharges(printedTotal: printedTotal, itemsSum: itemsSum,
                                                    discount: discount, tax: tax, taxOnTop: taxOnTop,
                                                    chargesTotal: chargesTotal)

        // The printed subtotal describes the PRODUCT rows; the review screen sums all rows (products
        // + charges), so lift the anchor by the charges to keep the dropped-line check aligned.
        let printedSubtotal = Decimal.fromDouble(resp.subtotal)

        return ExtractionResult(
            store: resp.storeName ?? "",
            date: Self.parseDate(resp.date),
            discount: discount, tax: tax, taxOnTop: taxOnTop, extraCharges: extraCharges,
            items: items + chargeItems, readable: true,
            printedSubtotal: printedSubtotal > 0 ? printedSubtotal + chargesTotal : nil
        )
    }

    // MARK: - Extraction guards (Android `HaikuReceiptExtractor.validateExtraction`)

    /// Rejects an extraction that demonstrably misread the receipt, so a wrong basket never reaches
    /// review. Client-side by necessity — the server returns its best effort and only the client knows
    /// what a plausible basket looks like — which also means loosening these ships in an app release,
    /// not a deploy.
    /// `internal` rather than `private` so the guard tests can drive it directly — `@testable`
    /// reaches internal, not private.
    static func validate(_ resp: ExtractResponse, items: [ExtractedDraftItem]) throws {
        // Article-count cross-check: capturing far fewer or more lines than the receipt itself prints
        // ("N АРТИКУЛА") means we misread it.
        //
        // The printed count is EITHER product lines OR units, depending on the receipt format — Greek
        // "ΣΥΝΟΛΟ ΕΙΔΩΝ" counts units, so a basket with multi-buy lines ("6 X 1,42") prints many more
        // articles than it has lines. Accept whichever reading lands in band; only a count matching
        // NEITHER is a genuine misread. Android learned this the hard way — its first version checked
        // the line count alone and rejected legitimate multi-buy receipts (`1d12a44`).
        let printedCount = resp.printedItemCount ?? 0
        if printedCount >= Guards.minPrintedCountToCheck {
            let units = items.reduce(0) { $0 + $1.quantity }
            let inBand = { (n: Int) -> Bool in
                Double(n) >= Double(printedCount) * Guards.minCountRatio
                    && Double(n) <= Double(printedCount) * Guards.maxCountRatio
            }
            if !inBand(items.count) && !inBand(units) { throw ExtractError.unreadable }
        }

        // Money sanity: the lines, net of the discount the model itself reported, shouldn't overshoot
        // the printed grand total by a wide margin. Deposits and fees only ever RAISE a total, so they
        // can't trip this — a large overshoot means invented or duplicated lines.
        let printedTotal = Decimal.fromDouble(resp.total)
        guard printedTotal > 0 else { return }
        let gross = items.reduce(Decimal.zero) { $0 + $1.price * Decimal($1.quantity) }
        let overshoot = gross - Decimal.fromDouble(resp.discount) - printedTotal
        if overshoot > max(printedTotal * Guards.maxOvershootRatio, Guards.maxOvershootAbs) {
            throw ExtractError.unreadable
        }
    }

    /// Thresholds mirror Android's, so a receipt is judged identically on both platforms.
    private enum Guards {
        /// Below this, the printed count is too small to be a reliable signal.
        static let minPrintedCountToCheck = 3
        static let minCountRatio = 0.6
        static let maxCountRatio = 1.5
        /// Lines may exceed the printed total by this fraction, or `maxOvershootAbs` — whichever is larger.
        static let maxOvershootRatio = Decimal(string: "0.35")!
        static let maxOvershootAbs = Decimal(string: "1.5")!
    }

    /// A charge amount worth materializing: rounded to cents, nil when missing or below the 5-cent
    /// noise threshold.
    private static func chargeAmount(_ raw: Double?) -> Decimal? {
        let value = Decimal.fromDouble(raw)
        return value >= extraChargesMin ? value : nil
    }

    /// Ignore a sub-5-cent gap between the printed total and the reconciled items as rounding.
    private static let extraChargesMin = Decimal(string: "0.05")!

    /// Anchor the paid total on the printed grand total: whatever gap the items+discount+on-top-tax
    /// don't explain becomes `extraCharges`, minus the already-materialized charge rows (so the
    /// delivery/tip lines aren't double-counted). A sub-5-cent gap is cent-rounding and yields zero.
    /// Pure (no I/O) so it can be unit-tested — mirrors Android's total-anchor logic.
    static func resolveExtraCharges(printedTotal: Decimal, itemsSum: Decimal, discount: Decimal,
                                    tax: Decimal, taxOnTop: Bool, chargesTotal: Decimal) -> Decimal {
        guard printedTotal > 0 else { return .zero }
        let reconciled = itemsSum - discount + (taxOnTop ? tax : .zero)
        let gap = printedTotal - reconciled
        guard gap >= extraChargesMin else { return .zero }
        return max(.zero, gap - chargesTotal)
    }

    /// An extracted category string, falling back to the default when missing or not a built-in.
    static func normalizedCategory(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return Categories.defaultName }
        return Categories.isPredefined(raw) ? raw : Categories.defaultName
    }

    static func parseDate(_ raw: String?) -> Date {
        guard let raw, !raw.isEmpty else { return .now }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        for fmt in ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "MM/dd/yyyy"] {
            let f = DateFormatter(); f.dateFormat = fmt
            if let d = f.date(from: raw) { return d }
        }
        return .now
    }
}

// MARK: - Stub extractor (DEBUG / Simulator)

#if DEBUG
struct StubReceiptExtractor: ReceiptExtractor {
    func extract(_ image: UIImage) async throws -> ExtractionResult {
        try? await Task.sleep(for: .seconds(1.4)) // mimic the "reading…" round-trip
        return ExtractionResult(
            store: "Kaufland",
            date: .now,
            discount: 3.20, tax: .zero, taxOnTop: false, extraCharges: .zero,
            items: [
                ExtractedDraftItem(name: "Wholegrain bread", quantity: 1, price: 1.29, category: "Bakery"),
                ExtractedDraftItem(name: "Gouda cheese 400g", quantity: 1, price: 3.49, category: "Dairy"),
                ExtractedDraftItem(name: "Chicken breast", quantity: 1, price: 6.49, category: "Meat & Poultry"),
                ExtractedDraftItem(name: "Bananas 1kg", quantity: 2, price: 1.05, category: "Fruits & Vegetables"),
                ExtractedDraftItem(name: "Sparkling water 6×", quantity: 1, price: 2.70, category: "Beverages"),
            ],
            readable: true
        )
    }
}
#endif
