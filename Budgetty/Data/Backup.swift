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
    var savingsGoals: [SavingsGoalDTO] = []
    /// Optional so a pre-buying-limits backup (no key) still decodes — Swift's synthesized `Decodable`
    /// throws on a missing non-optional key, so a later-added collection must be optional (same reason
    /// `CategoryDTO.parent` is). `BackupService.restore` reads it with `?? []`; buying limits carry no
    /// child rows → no id remap.
    var buyingLimits: [BuyingLimitDTO]? = []
    /// Wellbeing score history (§3.1). Optional for the same forward-compat reason. On restore a
    /// periodId clash keeps the on-device row (IGNORE), so a backup never overwrites the honest,
    /// first-computed snapshot — mirrors Android's `WellbeingScoreDao.insertAll(onConflict = IGNORE)`.
    var wellbeingScores: [WellbeingScoreDTO]? = []
    /// The user's DISPLAY / DATA-INTERPRETATION preferences (currency, month-start day, theme, …), so a
    /// full `.replace` restore reproduces the account faithfully on a new device — most importantly the
    /// currency (the app appends a symbol and never converts amounts, so the same numbers under the wrong
    /// symbol are simply wrong). Optional so a backup written before this change still decodes and leaves
    /// the current device's preferences untouched. Applied on `.replace` ONLY (see `SettingsDTO`).
    var settings: SettingsDTO? = nil

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
    var parent: String?   // optional so older backups (no key) still decode as top-level
    init(_ c: Category) {
        name = c.name; colorArgb = c.colorArgb; icon = c.icon; createdAt = c.createdAt; parent = c.parent
    }
}

struct SavingsGoalDTO: Codable {
    var name: String
    var emoji: String
    var targetAmount: Decimal
    var targetDate: Date?
    var createdAt: Date
    var contributions: [SavingsContributionDTO]
    init(_ g: SavingsGoal) {
        name = g.name; emoji = g.emoji; targetAmount = g.targetAmount
        targetDate = g.targetDate; createdAt = g.createdAt
        contributions = g.contributions.map(SavingsContributionDTO.init)
    }
}

struct SavingsContributionDTO: Codable {
    var amount: Decimal
    var note: String
    var date: Date
    init(_ c: SavingsContribution) { amount = c.amount; note = c.note; date = c.date }
}

struct BuyingLimitDTO: Codable {
    var emoji: String
    var label: String
    var keywords: [String]
    var timeframeRaw: String
    var count: Int
    var createdAt: Date
    init(_ l: BuyingLimit) {
        emoji = l.emoji; label = l.label; keywords = l.keywords
        timeframeRaw = l.timeframeRaw; count = l.count; createdAt = l.createdAt
    }
}

struct WellbeingScoreDTO: Codable {
    var periodId: String
    var score: Int
    var band: String
    var componentsJson: String
    var computedAt: Date
    init(_ e: WellbeingScoreEntity) {
        periodId = e.periodId; score = e.score; band = e.band
        componentsJson = e.componentsJson; computedAt = e.computedAt
    }
}

/// The user's DISPLAY / DATA-INTERPRETATION preferences, carried in the backup so a full `.replace`
/// restore reproduces the account faithfully on a new device.
///
/// Every field is optional so that (a) an OLD backup with no `settings` block still decodes and leaves
/// the current device's preferences untouched, and (b) a partially-populated block applies only the
/// fields it actually carries. Values are the exact strings the app persists in `UserDefaults` (the
/// enums' raw values, which are also their case names), so an iOS→iOS round-trip reads back cleanly and
/// an unrecognized value falls back to the on-device default on read.
///
/// JSON keys and string-case enum encoding mirror the Android backup for cross-platform parity:
/// `currency, dateFormat, language, themeMode, accent, monthStartDay, budgetRolloverEnabled,
/// hiddenHomeSections, hiddenInsightsSections, homeSectionOrder, insightsSectionOrder, recapEnabled,
/// recapFrequency`. (`themeMode` is the on-disk name for the iOS `pref.appearance` key.)
///
/// DELIBERATELY EXCLUDED — never written into a shareable, plaintext backup file:
///  • App lock — the PIN / its hash (Keychain, not UserDefaults), biometric-enabled, auto-lock minutes.
///    A passcode must never travel in a file the user can hand to anyone. (SECURITY.)
///  • Consent flags — crash-reporting and analytics opt-in. Device/person-scoped consent that is not the
///    account's to carry; an import must never silently flip a device's consent.
///  • Transient gate / timing state — recap "last shown" markers, onboarding-seen, insights-quiz-pending,
///    dismissed Wellbeing tips / limit suggestions, the overlay nudge-dismissed flag, scan-AI consent /
///    quota, and the premium / comp entitlement cache.
struct SettingsDTO: Codable, Equatable {
    var currency: String? = nil
    var dateFormat: String? = nil
    var language: String? = nil
    var themeMode: String? = nil            // iOS: SettingsKey.appearance (AppearancePref raw)
    var accent: String? = nil
    var monthStartDay: Int? = nil
    var budgetRolloverEnabled: Bool? = nil
    var hiddenHomeSections: [String]? = nil
    var hiddenInsightsSections: [String]? = nil
    var homeSectionOrder: [String]? = nil
    var insightsSectionOrder: [String]? = nil
    var recapEnabled: Bool? = nil
    var recapFrequency: String? = nil

    /// Snapshot the current effective preferences. Reads the same defaults the app's `@AppStorage`
    /// declarations use, so a user who never touched a setting still exports the value they actually see
    /// (e.g. `UserDefaults.integer` yields 0 for an absent `monthStartDay`, but the app treats it as 1).
    /// The accent is read from its persisted key rather than `AppTheme.shared` so this stays a pure,
    /// injectable read; `AppTheme` writes that same key on every change, and an absent key means the
    /// violet default.
    static func current(from d: UserDefaults = .standard) -> SettingsDTO {
        func int(_ key: String, _ fallback: Int) -> Int { d.object(forKey: key) == nil ? fallback : d.integer(forKey: key) }
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
        func list(_ raw: String) -> [String] { raw.split(separator: ",").map(String.init) }
        return SettingsDTO(
            currency: d.string(forKey: SettingsKey.currency) ?? "EUR",
            dateFormat: d.string(forKey: SettingsKey.dateFormat) ?? DateFormatOption.system.rawValue,
            language: d.string(forKey: SettingsKey.language) ?? "system",
            themeMode: d.string(forKey: SettingsKey.appearance) ?? AppearancePref.system.rawValue,
            accent: d.string(forKey: SettingsKey.accent) ?? AccentOption.violet.rawValue,
            monthStartDay: int(SettingsKey.monthStartDay, 1),
            budgetRolloverEnabled: flag(SettingsKey.budgetRolloverEnabled, false),
            hiddenHomeSections: list(d.string(forKey: HomeLayoutStore.hiddenKey) ?? HomeLayoutStore.defaultHidden),
            hiddenInsightsSections: list(d.string(forKey: InsightsLayoutStore.hiddenKey) ?? ""),
            homeSectionOrder: list(d.string(forKey: HomeLayoutStore.orderKey) ?? ""),
            insightsSectionOrder: list(d.string(forKey: InsightsLayoutStore.orderKey) ?? ""),
            recapEnabled: flag(SettingsKey.recapEnabled, true),
            recapFrequency: d.string(forKey: SettingsKey.recapFrequency) ?? RecapFrequency.both.rawValue
        )
    }

    /// Write back only the fields this block actually carries (a `nil` field is left as-is). The section
    /// order/hidden lists rejoin the CSV shape the layout stores keep in UserDefaults; `@AppStorage`-bound
    /// screens observe these keys and re-render live. Language mirrors the settings UI by also setting the
    /// `AppleLanguages` override (takes effect on next launch, exactly as picking a language does). The
    /// accent's cached live tint (`AppTheme`, read from ~80 view bodies) is nudged in step — but only for
    /// the real shared store, never a test's injected defaults.
    func apply(into d: UserDefaults = .standard) {
        if let currency { d.set(currency, forKey: SettingsKey.currency) }
        if let dateFormat { d.set(dateFormat, forKey: SettingsKey.dateFormat) }
        if let language {
            d.set(language, forKey: SettingsKey.language)
            if language == "system" { d.removeObject(forKey: "AppleLanguages") }
            else { d.set([language], forKey: "AppleLanguages") }
        }
        if let themeMode { d.set(themeMode, forKey: SettingsKey.appearance) }
        if let accent { d.set(accent, forKey: SettingsKey.accent) }
        if let monthStartDay { d.set(monthStartDay, forKey: SettingsKey.monthStartDay) }
        if let budgetRolloverEnabled { d.set(budgetRolloverEnabled, forKey: SettingsKey.budgetRolloverEnabled) }
        if let hiddenHomeSections { d.set(hiddenHomeSections.joined(separator: ","), forKey: HomeLayoutStore.hiddenKey) }
        if let homeSectionOrder { d.set(homeSectionOrder.joined(separator: ","), forKey: HomeLayoutStore.orderKey) }
        if let hiddenInsightsSections { d.set(hiddenInsightsSections.joined(separator: ","), forKey: InsightsLayoutStore.hiddenKey) }
        if let insightsSectionOrder { d.set(insightsSectionOrder.joined(separator: ","), forKey: InsightsLayoutStore.orderKey) }
        if let recapEnabled { d.set(recapEnabled, forKey: SettingsKey.recapEnabled) }
        if let recapFrequency { d.set(recapFrequency, forKey: SettingsKey.recapFrequency) }
        if d === UserDefaults.standard, let accent, let option = AccentOption(rawValue: accent) {
            AppTheme.shared.accent = option
        }
    }
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
            categories: try context.fetch(FetchDescriptor<Category>()).filter(\.isCustom).map(CategoryDTO.init),
            savingsGoals: try context.fetch(FetchDescriptor<SavingsGoal>()).map(SavingsGoalDTO.init),
            buyingLimits: try context.fetch(FetchDescriptor<BuyingLimit>()).map(BuyingLimitDTO.init),
            wellbeingScores: try context.fetch(FetchDescriptor<WellbeingScoreEntity>()).map(WellbeingScoreDTO.init),
            settings: SettingsDTO.current()
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
    ///
    /// Display / interpretation preferences (`file.settings`) are applied on `.replace` ONLY — a merge is
    /// additive and must never clobber the current device's currency, theme, layout, etc. `defaults` is
    /// injectable so tests can exercise the apply against an isolated store instead of `.standard`.
    static func restore(_ file: BackupFile, into context: ModelContext, mode: ImportMode,
                        defaults: UserDefaults = .standard) throws {
        if mode == .replace {
            for r in try context.fetch(FetchDescriptor<Receipt>()) { context.delete(r) }
            for b in try context.fetch(FetchDescriptor<Budget>()) { context.delete(b) }
            for r in try context.fetch(FetchDescriptor<Recurring>()) { context.delete(r) }
            for r in try context.fetch(FetchDescriptor<CategoryRule>()) { context.delete(r) }
            for c in try context.fetch(FetchDescriptor<Category>()) where c.isCustom { context.delete(c) }
            for g in try context.fetch(FetchDescriptor<SavingsGoal>()) { context.delete(g) } // cascades to contributions
            for l in try context.fetch(FetchDescriptor<BuyingLimit>()) { context.delete(l) }
            for s in try context.fetch(FetchDescriptor<WellbeingScoreEntity>()) { context.delete(s) }
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
                e.colorArgb = dto.colorArgb; e.icon = dto.icon; e.isCustom = true; e.parent = dto.parent
            } else {
                context.insert(Category(name: dto.name, colorArgb: dto.colorArgb, icon: dto.icon,
                                        isCustom: true, createdAt: dto.createdAt, parent: dto.parent))
            }
        }

        // Savings goals (+ their contributions). Additive; contributions attach to the fresh goal.
        for dto in file.savingsGoals {
            let goal = SavingsGoal(name: dto.name, emoji: dto.emoji, targetAmount: dto.targetAmount,
                                   targetDate: dto.targetDate, createdAt: dto.createdAt)
            context.insert(goal)
            for c in dto.contributions {
                context.insert(SavingsContribution(amount: c.amount, note: c.note, date: c.date, goal: goal))
            }
        }

        // Buying limits — no unique key, no child rows; additive with fresh ids. Keywords are
        // re-normalized on the way in so an older backup's raw values land canonical. `?? []` absorbs a
        // pre-buying-limits backup that omits the field entirely.
        for dto in file.buyingLimits ?? [] {
            context.insert(BuyingLimit(emoji: dto.emoji, label: dto.label,
                                       keywords: BuyingLimit.normalizedKeywords(dto.keywords),
                                       timeframe: BuyingLimitTimeframe(rawValue: dto.timeframeRaw) ?? .monthly,
                                       count: dto.count, createdAt: dto.createdAt))
        }

        // Wellbeing score history — unique `periodId`. IGNORE a clash: keep the on-device snapshot (the
        // honest, first-computed record) rather than letting a backup overwrite it — Android's
        // `insertAll(onConflict = IGNORE)`. On `.replace` the table was cleared above, so nothing clashes.
        // `?? []` absorbs a pre-history backup that omits the field entirely.
        var seenPeriods = Set(try context.fetch(FetchDescriptor<WellbeingScoreEntity>()).map(\.periodId))
        for dto in file.wellbeingScores ?? [] where seenPeriods.insert(dto.periodId).inserted {
            context.insert(WellbeingScoreEntity(periodId: dto.periodId, score: dto.score, band: dto.band,
                                                componentsJson: dto.componentsJson, computedAt: dto.computedAt))
        }

        try context.save()

        // Display / interpretation preferences ride along ONLY on a full replace, and apply only the
        // fields actually present. A pre-settings backup (`file.settings == nil`) or a merge leaves every
        // on-device preference untouched.
        if mode == .replace { file.settings?.apply(into: defaults) }
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
