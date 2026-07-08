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

        let discount = Decimal.fromDouble(resp.discount)
        let tax = Decimal.fromDouble(resp.tax)
        let taxOnTop = tax > 0
        let itemsSum = items.reduce(Decimal.zero) { $0 + $1.price * Decimal($1.quantity) }

        // Anchor on the printed grand total: any gap the items+discount+on-top-tax don't explain
        // becomes extraCharges (delivery/service/tip), so paid-total == printed total.
        var extraCharges = Decimal.zero
        let printedTotal = Decimal.fromDouble(resp.total)
        if printedTotal > 0 {
            let reconciled = itemsSum - discount + (taxOnTop ? tax : .zero)
            let gap = printedTotal - reconciled
            if gap > 0 { extraCharges = gap }
        }

        return ExtractionResult(
            store: resp.storeName ?? "",
            date: Self.parseDate(resp.date),
            discount: discount, tax: tax, taxOnTop: taxOnTop, extraCharges: extraCharges,
            items: items, readable: true
        )
    }

    private static func normalizedCategory(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return Categories.defaultName }
        return Categories.isPredefined(raw) ? raw : Categories.defaultName
    }

    private static func parseDate(_ raw: String?) -> Date {
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
