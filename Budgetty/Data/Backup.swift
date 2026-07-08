//
//  Backup.swift
//  Budgetty
//
//  Export / import of all user data as a single portable JSON file. Encodes receipts (with their
//  line items), budgets, recurring entries, learned category rules and custom categories into a
//  versioned `BackupFile`; restores them either by merging into or replacing the current store.
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - DTOs (the on-disk JSON shape; independent of the SwiftData @Model types)

struct BackupFile: Codable {
    var version = 1
    var app = "Budgetty iOS"
    var exportedAt = Date()
    var receipts: [ReceiptDTO] = []
    var budgets: [BudgetDTO] = []
    var recurring: [RecurringDTO] = []
    var rules: [RuleDTO] = []
    var categories: [CategoryDTO] = []   // custom categories only

    var itemCount: Int { receipts.reduce(0) { $0 + $1.items.count } }
}

struct ReceiptDTO: Codable {
    var createdAt: Date
    var store: String
    var date: Date
    var discount: Decimal
    var isManual: Bool
    var tax: Decimal
    var taxOnTop: Bool
    var extraCharges: Decimal
    var items: [LineItemDTO]

    init(_ r: Receipt) {
        createdAt = r.createdAt; store = r.store; date = r.date
        discount = r.discount; isManual = r.isManual
        tax = r.tax; taxOnTop = r.taxOnTop; extraCharges = r.extraCharges
        items = r.items.map(LineItemDTO.init)
    }
}

struct LineItemDTO: Codable {
    var name: String
    var createdAt: Date
    var price: Decimal
    var quantity: Int
    var category: String

    init(_ i: LineItem) {
        name = i.name; createdAt = i.createdAt; price = i.price
        quantity = i.quantity; category = i.category
    }
}

struct BudgetDTO: Codable {
    var key: String
    var amount: Decimal
    init(_ b: Budget) { key = b.key; amount = b.amount }
}

struct RecurringDTO: Codable {
    var label: String
    var amount: Decimal
    var isIncome: Bool
    var category: String
    var cadenceRaw: String
    var dueDay: Int
    var createdAt: Date
    var active: Bool
    init(_ r: Recurring) {
        label = r.label; amount = r.amount; isIncome = r.isIncome; category = r.category
        cadenceRaw = r.cadenceRaw; dueDay = r.dueDay; createdAt = r.createdAt; active = r.active
    }
}

struct RuleDTO: Codable {
    var name: String
    var category: String
    init(_ r: CategoryRule) { name = r.name; category = r.category }
}

struct CategoryDTO: Codable {
    var name: String
    var colorArgb: Int
    var icon: String
    var createdAt: Date
    init(_ c: Category) { name = c.name; colorArgb = c.colorArgb; icon = c.icon; createdAt = c.createdAt }
}

// MARK: - Service

enum BackupService {
    enum ImportMode { case merge, replace }

    enum BackupError: LocalizedError {
        case invalidFile
        var errorDescription: String? {
            switch self {
            case .invalidFile: "That file isn't a valid Budgetty backup."
            }
        }
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Snapshot the whole store to JSON.
    static func export(from context: ModelContext) throws -> Data {
        let file = BackupFile(
            receipts: try context.fetch(FetchDescriptor<Receipt>()).map(ReceiptDTO.init),
            budgets: try context.fetch(FetchDescriptor<Budget>()).map(BudgetDTO.init),
            recurring: try context.fetch(FetchDescriptor<Recurring>()).map(RecurringDTO.init),
            rules: try context.fetch(FetchDescriptor<CategoryRule>()).map(RuleDTO.init),
            categories: try context.fetch(FetchDescriptor<Category>()).filter(\.isCustom).map(CategoryDTO.init)
        )
        return try encoder().encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        guard let file = try? decoder().decode(BackupFile.self, from: data) else {
            throw BackupError.invalidFile
        }
        return file
    }

    /// Restore a decoded backup. `.replace` wipes existing user data first; `.merge` keeps it,
    /// upserting keyed rows (budgets/rules/custom categories) and appending receipts + recurring.
    static func restore(_ file: BackupFile, into context: ModelContext, mode: ImportMode) throws {
        if mode == .replace {
            for r in try context.fetch(FetchDescriptor<Receipt>()) { context.delete(r) }
            for b in try context.fetch(FetchDescriptor<Budget>()) { context.delete(b) }
            for r in try context.fetch(FetchDescriptor<Recurring>()) { context.delete(r) }
            for r in try context.fetch(FetchDescriptor<CategoryRule>()) { context.delete(r) }
            for c in try context.fetch(FetchDescriptor<Category>()) where c.isCustom { context.delete(c) }
            try context.save() // flush deletes before re-inserting unique-keyed rows
        }

        // Receipts (+ their line items). Always additive.
        for dto in file.receipts {
            let receipt = Receipt(createdAt: dto.createdAt, store: dto.store, date: dto.date,
                                  discount: dto.discount, isManual: dto.isManual,
                                  tax: dto.tax, taxOnTop: dto.taxOnTop, extraCharges: dto.extraCharges)
            context.insert(receipt)
            for i in dto.items {
                let item = LineItem(name: i.name, createdAt: i.createdAt, price: i.price,
                                    quantity: i.quantity, category: i.category, receipt: receipt)
                context.insert(item)
            }
        }

        // Recurring — no unique key; additive.
        for dto in file.recurring {
            let r = Recurring(label: dto.label, amount: dto.amount, isIncome: dto.isIncome,
                              category: dto.category, cadence: Cadence(rawValue: dto.cadenceRaw) ?? .monthly,
                              dueDay: dto.dueDay, createdAt: dto.createdAt, active: dto.active)
            context.insert(r)
        }

        // Budgets — unique `key`; upsert.
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        for dto in file.budgets {
            if let e = budgets.first(where: { $0.key == dto.key }) { e.amount = dto.amount }
            else { context.insert(Budget(key: dto.key, amount: dto.amount)) }
        }

        // Rules — unique `name`; upsert.
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        for dto in file.rules {
            if let e = rules.first(where: { $0.name == dto.name }) { e.category = dto.category }
            else { context.insert(CategoryRule(name: dto.name, category: dto.category)) }
        }

        // Custom categories — unique `name`; upsert.
        let cats = try context.fetch(FetchDescriptor<Category>())
        for dto in file.categories {
            if let e = cats.first(where: { $0.name == dto.name }) {
                e.colorArgb = dto.colorArgb; e.icon = dto.icon; e.isCustom = true
            } else {
                context.insert(Category(name: dto.name, colorArgb: dto.colorArgb, icon: dto.icon,
                                        isCustom: true, createdAt: dto.createdAt))
            }
        }

        try context.save()
    }
}

// MARK: - FileDocument for `.fileExporter`

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
