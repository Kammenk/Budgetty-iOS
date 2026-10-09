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
//
// Each DTO's `init(_ model)` lives in an extension so Swift keeps synthesizing the memberwise init —
// the Android-backup adapter (`AndroidBackup.swift`) and the tests build DTOs field by field.

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
    /// Travel-mode trips (metadata over a tag). Optional for forward-compat; the tag links ride on the
    /// line items, so a restored trip reconnects to its expenses through the tag.
    var trips: [TripDTO]? = []
    /// Saved transaction templates. Optional for forward-compat; additive on restore.
    var templates: [TemplateDTO]? = []
    /// Tracked product warranties. Optional for forward-compat; additive on restore. Expiry is derived
    /// from purchaseDate + durationMonths, so nothing date-stale carries over.
    var warranties: [WarrantyDTO]? = []
    /// Named budget envelopes (multiple budgets). Optional for forward-compat; additive on restore.
    var budgetEnvelopes: [BudgetEnvelopeDTO]? = []
    /// Debt-payoff planner debts. Optional for forward-compat; additive on restore.
    var debts: [DebtDTO]? = []
    /// Merchants the user dismissed from subscription detection. Optional for forward-compat; upserted
    /// by merchant on restore (a merge never duplicates). Same key + shape Android writes
    /// (`ignoredSubscriptions: [{merchant, ignoredAt}]`).
    var ignoredSubscriptions: [IgnoredSubscriptionDTO]? = []
    /// The tag catalog (name + first-seen time). Line items carry their tag NAMES, so this only adds
    /// what those can't: tags nothing carries yet, and each tag's original `createdAt`. Optional for
    /// forward-compat; fetch-or-create by name on restore. Same key Android writes (`tags`).
    var tags: [TagDTO]? = []
    /// The user's overrides on BUILT-IN categories — a re-homed `parent` and/or an explicit
    /// needs/wants/savings `bucket`. Custom categories carry these on `CategoryDTO`; built-ins aren't
    /// exported as rows (they're seeded), so without this a restore silently reset every built-in the
    /// user had nested or bucket-tagged. Optional: `nil` (an older backup) leaves the device's built-ins
    /// untouched; a present list on `.replace` resets built-ins to their defaults first.
    var categoryOverrides: [CategoryOverrideDTO]? = nil
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
}
extension ReceiptDTO {
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
    /// The line item's free-form tags (normalized names). Optional so a pre-tags backup still decodes;
    /// read with `?? []` on restore.
    var tags: [String]? = nil
}
extension LineItemDTO {
    init(_ i: LineItem) {
        name = i.name; createdAt = i.createdAt; price = i.price
        quantity = i.quantity; category = i.category
        tags = i.tags.map(\.name)
    }
}

struct BudgetDTO: Codable {
    var key: String
    var amount: Decimal
}
extension BudgetDTO {
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
    /// Bills only: auto-mark paid once the due day passes. Optional so a pre-autopay backup still
    /// decodes (read as `false`) — without it every restore silently switched Autopay off.
    var autoPay: Bool? = nil
    /// The mark-as-paid stamp (see `RecurringMath`): a bill marked paid this cycle stays paid after a
    /// restore. Optional / `nil` = never marked.
    var lastPosted: Date? = nil
    /// Reserved for the auto-posting phase; carried so the row round-trips whole.
    var nextDue: Date? = nil
}
extension RecurringDTO {
    init(_ r: Recurring) {
        label = r.label; amount = r.amount; isIncome = r.isIncome; category = r.category
        cadenceRaw = r.cadenceRaw; dueDay = r.dueDay; createdAt = r.createdAt; active = r.active
        autoPay = r.autoPay; lastPosted = r.lastPosted; nextDue = r.nextDue
    }
}

struct RuleDTO: Codable {
    var name: String
    var category: String
}
extension RuleDTO {
    init(_ r: CategoryRule) { name = r.name; category = r.category }
}

struct CategoryDTO: Codable {
    var name: String
    var colorArgb: Int
    var icon: String
    var createdAt: Date
    var parent: String?   // optional so older backups (no key) still decode as top-level
    /// Explicit needs/wants/savings bucket (`CategoryBucket` raw value); `nil` = derive the default.
    /// Optional so a pre-bucket backup still decodes.
    var bucket: String? = nil
}
extension CategoryDTO {
    init(_ c: Category) {
        name = c.name; colorArgb = c.colorArgb; icon = c.icon; createdAt = c.createdAt
        parent = c.parent; bucket = c.bucket
    }
}

/// A user override on a BUILT-IN category (see `BackupFile.categoryOverrides`).
struct CategoryOverrideDTO: Codable, Equatable {
    var name: String
    var parent: String?
    var bucket: String?
}
extension CategoryOverrideDTO {
    init(_ c: Category) { name = c.name; parent = c.parent; bucket = c.bucket }
}

/// A merchant dismissed from subscription detection — Android's `IgnoredSubscriptionEntity` shape.
struct IgnoredSubscriptionDTO: Codable, Equatable {
    var merchant: String
    var ignoredAt: Date
}
extension IgnoredSubscriptionDTO {
    init(_ s: IgnoredSubscription) { merchant = s.merchant; ignoredAt = s.ignoredAt }
}

/// One tag-catalog row — Android's `TagEntity` shape.
struct TagDTO: Codable, Equatable {
    var name: String
    var createdAt: Date
}
extension TagDTO {
    init(_ t: Tag) { name = t.name; createdAt = t.createdAt }
}

struct SavingsGoalDTO: Codable {
    var name: String
    var emoji: String
    var targetAmount: Decimal
    var targetDate: Date?
    var createdAt: Date
    var contributions: [SavingsContributionDTO]
}
extension SavingsGoalDTO {
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
}
extension SavingsContributionDTO {
    init(_ c: SavingsContribution) { amount = c.amount; note = c.note; date = c.date }
}

struct BuyingLimitDTO: Codable {
    var emoji: String
    var label: String
    var keywords: [String]
    var timeframeRaw: String
    var count: Int
    var createdAt: Date
}
extension BuyingLimitDTO {
    init(_ l: BuyingLimit) {
        emoji = l.emoji; label = l.label; keywords = l.keywords
        timeframeRaw = l.timeframeRaw; count = l.count; createdAt = l.createdAt
    }
}

struct TemplateDTO: Codable {
    var emoji: String
    var name: String
    var amount: Decimal
    var category: String
    var store: String
    var askAmount: Bool
    var createdAt: Date
}
extension TemplateDTO {
    init(_ t: Template) {
        emoji = t.emoji; name = t.name; amount = t.amount; category = t.category
        store = t.store; askAmount = t.askAmount; createdAt = t.createdAt
    }
}

struct WarrantyDTO: Codable {
    var name: String
    var emoji: String
    var store: String
    var category: String
    var purchaseDate: Date
    var durationMonths: Int
    var coverageNote: String
    var receiptId: Double
    var createdAt: Date
}
extension WarrantyDTO {
    init(_ w: Warranty) {
        name = w.name; emoji = w.emoji; store = w.store; category = w.category
        purchaseDate = w.purchaseDate; durationMonths = w.durationMonths
        coverageNote = w.coverageNote; receiptId = w.receiptId; createdAt = w.createdAt
    }
}

struct BudgetEnvelopeDTO: Codable {
    var name: String
    var emoji: String
    var limitAmount: Decimal
    var startDate: Date
    var endDate: Date
    var categories: [String]
    var sortOrder: Int
    var createdAt: Date
}
extension BudgetEnvelopeDTO {
    init(_ e: BudgetEnvelope) {
        name = e.name; emoji = e.emoji; limitAmount = e.limitAmount
        startDate = e.startDate; endDate = e.endDate; categories = e.categories
        sortOrder = e.sortOrder; createdAt = e.createdAt
    }
}

struct DebtDTO: Codable {
    var emoji: String
    var name: String
    var balance: Decimal
    var aprPercent: Decimal
    var minPayment: Decimal
    var createdAt: Date
}
extension DebtDTO {
    init(_ d: Debt) {
        emoji = d.emoji; name = d.name; balance = d.balance
        aprPercent = d.aprPercent; minPayment = d.minPayment; createdAt = d.createdAt
    }
}

struct TripDTO: Codable {
    var name: String
    var tag: String
    var startDate: Date?
    var endDate: Date?
    var budgetAmount: Decimal?
    var active: Bool
    var createdAt: Date
    var endedAt: Date?
}
extension TripDTO {
    init(_ t: Trip) {
        name = t.name; tag = t.tag; startDate = t.startDate; endDate = t.endDate
        budgetAmount = t.budgetAmount; active = t.active; createdAt = t.createdAt; endedAt = t.endedAt
    }
}

struct WellbeingScoreDTO: Codable {
    var periodId: String
    var score: Int
    var band: String
    var componentsJson: String
    var computedAt: Date
}
extension WellbeingScoreDTO {
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
/// JSON KEYS mirror the Android backup (`currency, dateFormat, language, themeMode, accent,
/// monthStartDay, budgetRolloverEnabled, hiddenHomeSections, hiddenInsightsSections, homeSectionOrder,
/// insightsSectionOrder, customInsightsSections, recapEnabled, recapFrequency, …`; `themeMode` is the
/// on-disk name for the iOS `pref.appearance` key), but most VALUES are each platform's own vocabulary
/// (iOS `system` / `dmy` / `de` vs Android `SYSTEM` / `DAY_MONTH_YEAR` / `GERMAN`, camelCase vs
/// snake_case section keys). An Android file is therefore never applied as-is: `AndroidBackup` maps it
/// onto these iOS values first, dropping anything without an iOS equivalent.
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
    var hideAmounts: Bool? = nil
    var hideAmountsOnBackground: Bool? = nil
    var budgetCadence: String? = nil
    var fortnightAnchor: Int? = nil
    /// The Insights Custom tab's membership (`InsightSection` raw values, in order); `[]` = cleared.
    var customInsightsSections: [String]? = nil

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
            recapFrequency: d.string(forKey: SettingsKey.recapFrequency) ?? RecapFrequency.both.rawValue,
            hideAmounts: flag(SettingsKey.hideAmounts, false),
            hideAmountsOnBackground: flag(SettingsKey.hideAmountsOnBackground, false),
            budgetCadence: d.string(forKey: SettingsKey.budgetCadence) ?? "",
            fortnightAnchor: int(SettingsKey.fortnightAnchor, 0),
            customInsightsSections: list(d.string(forKey: SettingsKey.insightsCustomSections) ?? InsightsCustomStore.seedCSV)
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
        if let hideAmounts { d.set(hideAmounts, forKey: SettingsKey.hideAmounts) }
        if let hideAmountsOnBackground { d.set(hideAmountsOnBackground, forKey: SettingsKey.hideAmountsOnBackground) }
        if let budgetCadence { d.set(budgetCadence, forKey: SettingsKey.budgetCadence) }
        if let fortnightAnchor { d.set(fortnightAnchor, forKey: SettingsKey.fortnightAnchor) }
        if let customInsightsSections {
            d.set(customInsightsSections.joined(separator: ","), forKey: SettingsKey.insightsCustomSections)
        }
        if d === UserDefaults.standard, let accent, let option = AccentOption(rawValue: accent) {
            AppTheme.shared.accent = option
        }
        // The live money-mask flag mirrors UserDefaults — nudge it after a restore writes the key.
        if d === UserDefaults.standard { MoneyVisibility.shared.refreshFromDefaults() }
    }
}

// MARK: - Service

enum BackupService {
    enum ImportMode { case merge, replace }

    enum BackupError: LocalizedError {
        case invalidFile
        var errorDescription: String? {
            switch self {
            case .invalidFile: String(localized: "That file isn't a valid Budgetty backup.")
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

    /// Snapshot the whole store to JSON. Main-actor: it reads SwiftData `@Model` objects (and their
    /// relationships), which are main-actor-isolated; every caller is a SwiftUI view method already.
    @MainActor
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
            trips: try context.fetch(FetchDescriptor<Trip>()).map(TripDTO.init),
            templates: try context.fetch(FetchDescriptor<Template>()).map(TemplateDTO.init),
            warranties: try context.fetch(FetchDescriptor<Warranty>()).map(WarrantyDTO.init),
            budgetEnvelopes: try context.fetch(FetchDescriptor<BudgetEnvelope>()).map(BudgetEnvelopeDTO.init),
            debts: try context.fetch(FetchDescriptor<Debt>()).map(DebtDTO.init),
            ignoredSubscriptions: try context.fetch(FetchDescriptor<IgnoredSubscription>())
                .map(IgnoredSubscriptionDTO.init),
            tags: try context.fetch(FetchDescriptor<Tag>()).map(TagDTO.init),
            categoryOverrides: try context.fetch(FetchDescriptor<Category>())
                .filter { !$0.isCustom && ($0.parent != nil || $0.bucket != nil) }
                .map(CategoryOverrideDTO.init),
            settings: SettingsDTO.current()
        )
        return try encoder().encode(file)
    }

    /// Decodes an iOS backup — or, failing that, an ANDROID backup (flat `transactions`, epoch-millis
    /// numbers, Kotlin enum names), converted to the iOS shape by `AndroidBackup` so a user switching
    /// platforms can restore. Anything else is `invalidFile`.
    static func decode(_ data: Data) throws -> BackupFile {
        if let file = try? decoder().decode(BackupFile.self, from: data) { return file }
        if AndroidBackup.looksLikeAndroid(data), let file = try? AndroidBackup.convert(data) { return file }
        throw BackupError.invalidFile
    }

    /// Restore a decoded backup. `.replace` wipes existing user data first; `.merge` keeps it,
    /// upserting keyed rows (budgets/rules/custom categories) and appending receipts + recurring.
    ///
    /// Display / interpretation preferences (`file.settings`) are applied on `.replace` ONLY — a merge is
    /// additive and must never clobber the current device's currency, theme, layout, etc. `defaults` is
    /// injectable so tests can exercise the apply against an isolated store instead of `.standard`.
    @MainActor
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
            for t in try context.fetch(FetchDescriptor<Tag>()) { context.delete(t) }
            for t in try context.fetch(FetchDescriptor<Trip>()) { context.delete(t) }
            for t in try context.fetch(FetchDescriptor<Template>()) { context.delete(t) }
            for w in try context.fetch(FetchDescriptor<Warranty>()) { context.delete(w) }
            for e in try context.fetch(FetchDescriptor<BudgetEnvelope>()) { context.delete(e) }
            for d in try context.fetch(FetchDescriptor<Debt>()) { context.delete(d) }
            // Budget carry-over is derived state that isn't backed up: a stale pre-restore leftover
            // (e.g. last month's 1,200 € under MONTHLY) must not survive onto the restored budgets —
            // rollover restarts from zero for the restored data.
            for r in try context.fetch(FetchDescriptor<BudgetRollover>()) { context.delete(r) }
            for s in try context.fetch(FetchDescriptor<IgnoredSubscription>()) { context.delete(s) }
            // Built-in category overrides: a backup that carries the list reproduces the account's
            // nesting / bucket choices exactly, so reset every built-in to its code default first. An
            // older backup (`nil`) leaves the device's built-ins as they are.
            if file.categoryOverrides != nil {
                for c in try context.fetch(FetchDescriptor<Category>()) where !c.isCustom {
                    c.parent = nil; c.bucket = nil
                }
            }
            try context.save() // flush deletes before re-inserting unique-keyed rows
        }

        // Tag catalog, keyed by normalized name — fetch-or-create as line items reference them, so a
        // merge reuses the device's existing rows and never duplicates. `Tag.name` is unique.
        var tagsByName = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Tag>()).map { ($0.name, $0) })
        func tag(_ rawName: String, createdAt: Date = .now) -> Tag? {
            let key = Tag.normalize(rawName)
            guard !key.isEmpty else { return nil }
            if let existing = tagsByName[key] { return existing }
            let created = Tag(name: key, createdAt: createdAt)
            context.insert(created); tagsByName[key] = created
            return created
        }
        // The backed-up catalog first, so each tag keeps its original `createdAt` and a tag nothing
        // carries yet still comes back. An existing device row wins (merge).
        for dto in file.tags ?? [] { _ = tag(dto.name, createdAt: dto.createdAt) }

        // Receipts (+ their line items, with their tags). Always additive.
        for dto in file.receipts {
            let receipt = Receipt(createdAt: dto.createdAt, store: dto.store, date: dto.date,
                                  discount: dto.discount, isManual: dto.isManual,
                                  tax: dto.tax, taxOnTop: dto.taxOnTop, extraCharges: dto.extraCharges)
            context.insert(receipt)
            for i in dto.items {
                let item = LineItem(name: i.name, createdAt: i.createdAt, price: i.price,
                                    quantity: i.quantity, category: i.category, receipt: receipt)
                context.insert(item)
                var seen = Set<String>()
                item.tags = (i.tags ?? []).compactMap { tag($0) }.filter { seen.insert($0.name).inserted }
            }
        }

        // Recurring — no unique key; additive. Autopay goes through `autoPayEligible` (as the edit sheet
        // does) so a yearly / one-off / income row can never restore with a stuck flag.
        for dto in file.recurring {
            let r = Recurring(label: dto.label, amount: dto.amount, isIncome: dto.isIncome,
                              category: dto.category, cadence: Cadence(rawValue: dto.cadenceRaw) ?? .monthly,
                              dueDay: dto.dueDay, createdAt: dto.createdAt, active: dto.active)
            r.autoPay = (dto.autoPay ?? false) && r.autoPayEligible
            r.lastPosted = dto.lastPosted
            r.nextDue = dto.nextDue
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
                e.bucket = dto.bucket
            } else {
                context.insert(Category(name: dto.name, colorArgb: dto.colorArgb, icon: dto.icon,
                                        isCustom: true, createdAt: dto.createdAt, parent: dto.parent,
                                        bucket: dto.bucket))
            }
        }

        // Built-in category overrides (nesting / bucket). Only fills what the device hasn't set: on
        // `.replace` the built-ins were reset above, so this reproduces the backup exactly; on `.merge`
        // it's additive and never overrides the device's own choices. A name the device doesn't know as
        // a built-in is skipped (built-ins are seeded, never created by a restore).
        for dto in file.categoryOverrides ?? [] {
            guard let e = cats.first(where: { $0.name == dto.name && !$0.isCustom }) else { continue }
            if e.parent == nil { e.parent = dto.parent }
            if e.bucket == nil { e.bucket = dto.bucket }
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

        // Trips — additive metadata over a tag. Make sure the trip's tag is in the catalog even if
        // nothing carries it yet (an open trip with no expenses), so auto-tagging works on resume.
        for dto in file.trips ?? [] {
            let normalized = Tag.normalize(dto.tag)
            _ = tag(normalized)
            context.insert(Trip(name: dto.name, tag: normalized, startDate: dto.startDate,
                                endDate: dto.endDate, budgetAmount: dto.budgetAmount, active: dto.active,
                                createdAt: dto.createdAt, endedAt: dto.endedAt))
        }

        // Templates — additive with fresh rows.
        for dto in file.templates ?? [] {
            context.insert(Template(emoji: dto.emoji, name: dto.name, amount: dto.amount,
                                    category: dto.category, store: dto.store, askAmount: dto.askAmount,
                                    createdAt: dto.createdAt))
        }

        // Warranties — additive with fresh rows.
        for dto in file.warranties ?? [] {
            context.insert(Warranty(name: dto.name, emoji: dto.emoji, store: dto.store,
                                    category: dto.category, purchaseDate: dto.purchaseDate,
                                    durationMonths: dto.durationMonths, coverageNote: dto.coverageNote,
                                    receiptId: dto.receiptId, createdAt: dto.createdAt))
        }

        // Budget envelopes — additive with fresh rows.
        for dto in file.budgetEnvelopes ?? [] {
            context.insert(BudgetEnvelope(name: dto.name, emoji: dto.emoji, limitAmount: dto.limitAmount,
                                          startDate: dto.startDate, endDate: dto.endDate,
                                          categories: dto.categories, sortOrder: dto.sortOrder,
                                          createdAt: dto.createdAt))
        }

        // Debts (debt-payoff planner) — additive with fresh rows.
        for dto in file.debts ?? [] {
            context.insert(Debt(emoji: dto.emoji, name: dto.name, balance: dto.balance,
                                aprPercent: dto.aprPercent, minPayment: dto.minPayment, createdAt: dto.createdAt))
        }

        // Ignored subscriptions — unique `merchant`; upsert, so a merge never duplicates a dismissal.
        let ignored = try context.fetch(FetchDescriptor<IgnoredSubscription>())
        var ignoredByMerchant = Dictionary(ignored.map { ($0.merchant, $0) }, uniquingKeysWith: { a, _ in a })
        for dto in file.ignoredSubscriptions ?? [] where !dto.merchant.isEmpty {
            if let e = ignoredByMerchant[dto.merchant] { e.ignoredAt = dto.ignoredAt; continue }
            let row = IgnoredSubscription(merchant: dto.merchant, ignoredAt: dto.ignoredAt)
            context.insert(row); ignoredByMerchant[dto.merchant] = row
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
