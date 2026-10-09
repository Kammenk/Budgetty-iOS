//
//  AndroidBackup.swift
//  Budgetty
//
//  Reads a backup written by the ANDROID app and converts it to the iOS `BackupFile`, so a user moving
//  phones can restore on iOS (device-test bug 7: it used to fail with "That file isn't a valid Budgetty
//  backup."). Android's file is a plain Gson dump of `BackupData` (app/…/data/backup/BackupData.kt):
//
//   • flat `transactions` (one row per line item) linked to `receipts` by `receiptId` = the receipt's
//     `timestamp` primary key (its upload moment); a transaction's own `timestamp` is the printed date;
//   • every date is epoch MILLIseconds, every BigDecimal a JSON number, null fields omitted;
//   • lists stored newline-joined in one string (buying-limit keywords, envelope categories);
//   • tags as a catalog plus `transactionTags` {transactionId, tagName} links;
//   • preferences as Kotlin enum NAMES (`SYSTEM`, `GERMAN`, `DAY_MONTH_YEAR`, `DEFAULT`, …).
//
//  The converter maps all of that onto the iOS DTOs and vocabulary. A value with no iOS equivalent maps
//  to `nil` — never an Android enum name written into UserDefaults — so `SettingsDTO.apply` leaves the
//  device's own preference in place. Everything here is pure (no SwiftData), so it unit-tests directly.
//
//  The reverse direction is Android's job: it recognises an iOS file by `"app": "Budgetty iOS"`, which
//  `BackupFile` always writes.
//

import Foundation

enum AndroidBackup {

    /// True when `data` is a JSON object shaped like an Android export: no iOS `app` marker and a
    /// top-level `transactions` array (Android always writes it, even empty).
    static func looksLikeAndroid(_ data: Data) -> Bool {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return obj["app"] == nil && obj["transactions"] is [Any]
    }

    /// Decodes an Android backup and converts it to an iOS `BackupFile`. Throws on malformed JSON.
    static func convert(_ data: Data) throws -> BackupFile {
        try convert(JSONDecoder().decode(AndroidBackupData.self, from: data))
    }

    // MARK: - Conversion

    static func convert(_ a: AndroidBackupData) -> BackupFile {
        var file = BackupFile()
        file.app = "Budgetty Android"
        file.receipts = receipts(a)
        file.budgets = (a.budgets ?? []).compactMap { b in
            guard let key = b.budgetKey, !key.isEmpty, let amount = b.amount?.value else { return nil }
            return BudgetDTO(key: key, amount: amount)
        }
        file.recurring = (a.recurring ?? []).compactMap(recurring)
        file.rules = (a.rules ?? []).compactMap { r in
            guard let name = r.name, !name.isEmpty, let category = r.category else { return nil }
            return RuleDTO(name: name, category: category)
        }
        // Android exports EVERY category row (built-ins too). Only user-created ones become iOS custom
        // categories; a built-in's parent / bucket override rides along as a `CategoryOverrideDTO`.
        let cats = a.categories ?? []
        file.categories = cats.filter { $0.isCustom == true }.compactMap { c in
            guard let name = c.name, !name.isEmpty else { return nil }
            return CategoryDTO(name: name, colorArgb: argb(c.colorArgb), icon: c.icon ?? "",
                               createdAt: date(c.createdAt), parent: c.parent, bucket: bucket(c.bucket))
        }
        file.categoryOverrides = a.categories == nil ? nil : cats
            .filter { $0.isCustom != true && ($0.parent != nil || bucket($0.bucket) != nil) }
            .compactMap { c in
                guard let name = c.name, !name.isEmpty else { return nil }
                return CategoryOverrideDTO(name: name, parent: c.parent, bucket: bucket(c.bucket))
            }
        file.savingsGoals = savingsGoals(a)
        file.buyingLimits = (a.buyingLimits ?? []).map { l in
            BuyingLimitDTO(emoji: l.emoji ?? "", label: l.label ?? "", keywords: l.keywords?.values ?? [],
                           timeframeRaw: BuyingLimitTimeframe(rawValue: l.timeframe ?? "")?.rawValue
                               ?? BuyingLimitTimeframe.monthly.rawValue,
                           count: max(l.count ?? 1, 1), createdAt: date(l.createdAt))
        }
        file.wellbeingScores = (a.wellbeingScores ?? []).compactMap { s in
            guard let periodId = s.periodId, let score = s.score else { return nil }
            return WellbeingScoreDTO(periodId: periodId, score: score, band: s.band ?? "",
                                     componentsJson: s.componentsJson ?? "{}", computedAt: date(s.computedAt))
        }
        file.trips = (a.trips ?? []).compactMap { t in
            guard let name = t.name, let tag = t.tag else { return nil }
            return TripDTO(name: name, tag: tag, startDate: optionalDate(t.startDate),
                           endDate: optionalDate(t.endDate), budgetAmount: t.budgetAmount?.value,
                           active: t.active ?? false, createdAt: date(t.createdAt),
                           endedAt: optionalDate(t.endedAt))
        }
        file.templates = (a.templates ?? []).map { t in
            TemplateDTO(emoji: t.emoji ?? "", name: t.name ?? "", amount: t.amount?.value ?? 0,
                        category: t.category ?? "", store: t.store ?? "", askAmount: t.askAmount ?? false,
                        createdAt: date(t.createdAt))
        }
        file.warranties = (a.warranties ?? []).compactMap { w in
            guard let name = w.name, let purchase = w.purchaseDate, let months = w.durationMonths else { return nil }
            // iOS links a warranty to `Receipt.createdAt` in epoch SECONDS; Android stores the receipt's
            // epoch-millis PK — and the converted receipt keeps that same moment as its `createdAt`.
            return WarrantyDTO(name: name, emoji: w.emoji ?? "🛡️", store: w.store ?? "",
                               category: w.category ?? "", purchaseDate: date(purchase),
                               durationMonths: months, coverageNote: w.coverageNote ?? "",
                               receiptId: Double(w.receiptId ?? 0) / 1000, createdAt: date(w.createdAt))
        }
        file.budgetEnvelopes = (a.budgetEnvelopes ?? []).compactMap { e in
            guard let name = e.name, let limit = e.limitAmount?.value,
                  let start = e.startDate, let end = e.endDate else { return nil }
            return BudgetEnvelopeDTO(name: name, emoji: e.emoji ?? "🧾", limitAmount: limit,
                                     startDate: date(start), endDate: date(end),
                                     categories: e.categories?.values ?? [], sortOrder: e.sortOrder ?? 0,
                                     createdAt: date(e.createdAt))
        }
        file.debts = (a.debts ?? []).map { d in
            DebtDTO(emoji: d.emoji ?? "", name: d.name ?? "", balance: d.balance?.value ?? 0,
                    aprPercent: d.aprPercent?.value ?? 0, minPayment: d.minPayment?.value ?? 0,
                    createdAt: date(d.createdAt))
        }
        file.ignoredSubscriptions = (a.ignoredSubscriptions ?? []).compactMap { s in
            guard let merchant = s.merchant, !merchant.isEmpty else { return nil }
            return IgnoredSubscriptionDTO(merchant: merchant, ignoredAt: date(s.ignoredAt))
        }
        file.tags = (a.tags ?? []).compactMap { t in
            guard let name = t.name, !name.isEmpty else { return nil }
            return TagDTO(name: name, createdAt: date(t.createdAt))
        }
        file.settings = a.settings.map(settings)
        return file
    }

    /// Re-nests the flat transactions under their receipts. A receipt keeps Android's upload moment as
    /// `createdAt` (its line items share it, as on iOS) and its printed `date`. Transactions whose
    /// receipt row is missing become manual receipts dated by the transaction: one per orphaned upload
    /// id (Android shows those as one receipt too), or one per transaction for legacy id-0 rows.
    private static func receipts(_ a: AndroidBackupData) -> [ReceiptDTO] {
        var tagsByTxn: [Int64: [String]] = [:]
        for link in a.transactionTags ?? [] {
            guard let id = link.transactionId, let name = link.tagName, !name.isEmpty else { continue }
            tagsByTxn[id, default: []].append(name)
        }
        func item(_ t: AndroidTransaction, stamp: Date) -> LineItemDTO {
            let category = (t.category ?? "").trimmingCharacters(in: .whitespaces)
            return LineItemDTO(name: t.name ?? "", createdAt: stamp, price: t.price?.value ?? 0,
                               quantity: max(t.quantity ?? 1, 1),
                               category: category.isEmpty ? Categories.defaultName : category,
                               tags: t.id.flatMap { tagsByTxn[$0] })
        }

        let txns = a.transactions ?? []
        let receiptRows = a.receipts ?? []
        let known = Set(receiptRows.compactMap(\.timestamp))
        let byReceipt = Dictionary(grouping: txns.filter { ($0.receiptId ?? 0) != 0 }, by: { $0.receiptId ?? 0 })

        var out: [ReceiptDTO] = receiptRows.compactMap { r in
            guard let ts = r.timestamp else { return nil }
            let stamp = date(ts)
            return ReceiptDTO(createdAt: stamp, store: r.store ?? "", date: date(r.date ?? ts),
                              discount: r.discount?.value ?? 0, isManual: r.isManual ?? false,
                              tax: r.tax?.value ?? 0, taxOnTop: r.taxOnTop ?? false,
                              extraCharges: r.extraCharges?.value ?? 0,
                              items: (byReceipt[ts] ?? []).map { item($0, stamp: stamp) })
        }

        // Orphans: an upload id with no receipt row → one manual receipt for the group.
        for (rid, group) in byReceipt where !known.contains(rid) {
            let stamp = date(rid)
            let printed = group.first?.timestamp.map { date($0) } ?? stamp
            out.append(ReceiptDTO(createdAt: stamp, store: "", date: printed, discount: 0, isManual: true,
                                  tax: 0, taxOnTop: false, extraCharges: 0,
                                  items: group.map { item($0, stamp: stamp) }))
        }
        // Legacy rows with no upload id at all → one manual receipt each, dated by the transaction.
        for t in txns where (t.receiptId ?? 0) == 0 {
            let printed = date(t.timestamp ?? 0)
            out.append(ReceiptDTO(createdAt: printed, store: "", date: printed, discount: 0, isManual: true,
                                  tax: 0, taxOnTop: false, extraCharges: 0, items: [item(t, stamp: printed)]))
        }
        return out.sorted { $0.createdAt < $1.createdAt }
    }

    private static func recurring(_ r: AndroidRecurring) -> RecurringDTO? {
        guard let label = r.label, let amount = r.amount?.value else { return nil }
        let cadence = Cadence(rawValue: r.cadence ?? "") ?? .monthly
        return RecurringDTO(label: label, amount: amount, isIncome: r.isIncome ?? false,
                            category: r.category ?? "", cadenceRaw: cadence.rawValue, dueDay: r.dueDay ?? 1,
                            createdAt: date(r.createdAt), active: r.active ?? true, autoPay: r.autoPay ?? false,
                            lastPosted: optionalDate(r.lastPosted), nextDue: optionalDate(r.nextDue))
    }

    /// Goals with their contributions re-attached by `goalId`; a contribution whose goal isn't in the
    /// file is dropped (Android's restore does the same).
    private static func savingsGoals(_ a: AndroidBackupData) -> [SavingsGoalDTO] {
        let byGoal = Dictionary(grouping: a.savingsContributions ?? [], by: { $0.goalId ?? -1 })
        return (a.savingsGoals ?? []).compactMap { g in
            guard let name = g.name, let target = g.targetAmount?.value else { return nil }
            let contributions = (g.id.flatMap { byGoal[$0] } ?? []).compactMap { c -> SavingsContributionDTO? in
                guard let amount = c.amount?.value else { return nil }
                return SavingsContributionDTO(amount: amount, note: c.note ?? "", date: date(c.date))
            }
            return SavingsGoalDTO(name: name, emoji: g.emoji ?? "", targetAmount: target,
                                  targetDate: optionalDate(g.targetDate), createdAt: date(g.createdAt),
                                  contributions: contributions)
        }
    }

    // MARK: - Settings vocabulary (Android enum names → iOS stored values)

    static func settings(_ s: AndroidSettings) -> SettingsDTO {
        SettingsDTO(
            currency: s.currency.flatMap { code in CurrencyOption.all.contains { $0.code == code } ? code : nil },
            dateFormat: s.dateFormat.flatMap { dateFormats[$0]?.rawValue },
            language: s.language.flatMap { languages[$0] },
            themeMode: s.themeMode.flatMap { AppearancePref(rawValue: $0.lowercased())?.rawValue },
            accent: s.accent.flatMap { $0 == "DEFAULT" ? AccentOption.violet.rawValue : AccentOption(rawValue: $0.lowercased())?.rawValue },
            monthStartDay: s.monthStartDay.flatMap { (1...31).contains($0) ? $0 : nil },
            budgetRolloverEnabled: s.budgetRolloverEnabled,
            hiddenHomeSections: sections(s.hiddenHomeSections, homeSections),
            hiddenInsightsSections: sections(s.hiddenInsightsSections, insightsSections),
            homeSectionOrder: sections(s.homeSectionOrder, homeSections),
            insightsSectionOrder: sections(s.insightsSectionOrder, insightsSections),
            recapEnabled: s.recapEnabled,
            recapFrequency: s.recapFrequency.flatMap { RecapFrequency(rawValue: $0)?.rawValue },
            hideAmounts: s.hideAmounts,
            hideAmountsOnBackground: s.hideAmountsOnBackground,
            budgetCadence: s.budgetCadence.flatMap { cadences.contains($0) ? $0 : nil },
            fortnightAnchor: s.fortnightAnchorEpochDay.flatMap { $0 > 0 ? Int($0) : nil },
            customInsightsSections: sections(s.customInsightsSections, insightsSections)
        )
    }

    /// Android `DateFormatOption` → the nearest iOS `DateFormatOption`. iOS has no ISO (year-first)
    /// option; the all-numeric `numeric` (05.06.2026) is the closest in spirit.
    private static let dateFormats: [String: DateFormatOption] = [
        "DAY_MONTH_YEAR": .dayMonthYear,   // 5 Jun 2026 → 5 Jun 2026
        "DMY_SLASH": .numeric,             // 05/06/2026 → 05.06.2026
        "MDY_SLASH": .monthDayYear,        // 06/05/2026 → Jun 5, 2026
        "ISO": .numeric,                   // 2026-06-05 → 05.06.2026
    ]

    /// Android `Language` enum names → the iOS `LanguageOption` codes (validated against that list).
    private static let languages: [String: String] = {
        let map = ["SYSTEM": "system", "ENGLISH": "en", "SPANISH": "es", "FRENCH": "fr", "GERMAN": "de",
                   "ITALIAN": "it", "PORTUGUESE": "pt", "RUSSIAN": "ru", "SWEDISH": "sv", "DUTCH": "nl",
                   "NORWEGIAN": "nb", "DANISH": "da", "FINNISH": "fi", "POLISH": "pl", "CZECH": "cs",
                   "BULGARIAN": "bg", "ROMANIAN": "ro", "HUNGARIAN": "hu"]
        let supported = Set(LanguageOption.all.map(\.code))
        return map.filter { supported.contains($0.value) }
    }()

    private static let cadences: Set<String> = [Budget.weeklyKey, Budget.fortnightlyKey, Budget.monthlyKey]

    /// Android `HomeSection.key` → iOS `HomeSection` raw value.
    private static let homeSections: [String: String] = [
        "total_spent": HomeSection.totalSpent.rawValue, "budgets": HomeSection.budgets.rawValue,
        "upcoming_bills": HomeSection.upcomingBills.rawValue, "wellbeing": HomeSection.wellbeing.rawValue,
        "receipts": HomeSection.receipts.rawValue,
    ]

    /// Android `InsightsSection.key` → iOS `InsightSection` raw value. Android-only sections (wellbeing,
    /// savings rate, income by source) have no iOS section and are dropped.
    private static let insightsSections: [String: String] = [
        "trend": InsightSection.trend.rawValue, "breakdown": InsightSection.breakdown.rawValue,
        "summary": InsightSection.stats.rawValue, "needs_wants_savings": InsightSection.needsWantsSavings.rawValue,
        "highlights": InsightSection.highlights.rawValue, "period_comparison": InsightSection.comparison.rawValue,
        "top_categories": InsightSection.topCategories.rawValue, "top_stores": InsightSection.topStores.rawValue,
        "biggest_purchases": InsightSection.biggestPurchases.rawValue, "by_tag": InsightSection.byTag.rawValue,
        "income_spending": InsightSection.income.rawValue, "subscriptions": InsightSection.subscriptions.rawValue,
    ]

    /// Maps a section-key list, dropping keys iOS doesn't have. An empty list stays empty (Android's
    /// "nothing hidden" / "default order"); a non-empty list where nothing maps becomes `nil` so the
    /// device keeps its own layout rather than having it wiped by an untranslatable one.
    private static func sections(_ keys: [String]?, _ map: [String: String]) -> [String]? {
        guard let keys else { return nil }
        var seen = Set<String>()
        let mapped = keys.compactMap { map[$0] }.filter { seen.insert($0).inserted }
        return keys.isEmpty || !mapped.isEmpty ? mapped : nil
    }

    // MARK: - Primitive helpers

    private static func date(_ millis: Int64?) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis ?? 0) / 1000)
    }
    /// Android writes 0 for "never" on non-null long columns (`lastPosted`, `nextDue`) and omits a
    /// null one; both mean no date on iOS.
    private static func optionalDate(_ millis: Int64?) -> Date? {
        guard let millis, millis > 0 else { return nil }
        return date(millis)
    }
    /// Android's colour is a signed 32-bit Int; iOS stores the same bits as a positive 0xAARRGGBB.
    private static func argb(_ v: Int64?) -> Int { Int(UInt32(truncatingIfNeeded: v ?? 0)) }
    private static func bucket(_ raw: String?) -> String? { raw.flatMap { CategoryBucket(rawValue: $0)?.rawValue } }
}

// MARK: - Android on-disk shapes (Gson field names; every field optional — Gson omits nulls)

struct AndroidBackupData: Decodable {
    var transactions: [AndroidTransaction]?
    var categories: [AndroidCategory]?
    var budgets: [AndroidBudget]?
    var receipts: [AndroidReceipt]?
    var rules: [AndroidRule]?
    var recurring: [AndroidRecurring]?
    var savingsGoals: [AndroidSavingsGoal]?
    var savingsContributions: [AndroidSavingsContribution]?
    var buyingLimits: [AndroidBuyingLimit]?
    var wellbeingScores: [AndroidWellbeingScore]?
    var tags: [AndroidTag]?
    var transactionTags: [AndroidTransactionTag]?
    var debts: [AndroidDebt]?
    var templates: [AndroidTemplate]?
    var warranties: [AndroidWarranty]?
    var budgetEnvelopes: [AndroidBudgetEnvelope]?
    var trips: [AndroidTrip]?
    var ignoredSubscriptions: [AndroidIgnoredSubscription]?
    var settings: AndroidSettings?
}

struct AndroidTransaction: Decodable {
    var id: Int64?
    var name: String?
    var timestamp: Int64?
    var price: AndroidDecimal?
    var quantity: Int?
    var category: String?
    var receiptId: Int64?
}

struct AndroidReceipt: Decodable {
    var timestamp: Int64?
    var store: String?
    var date: Int64?
    var discount: AndroidDecimal?
    var isManual: Bool?
    var tax: AndroidDecimal?
    var taxOnTop: Bool?
    var extraCharges: AndroidDecimal?
}

struct AndroidCategory: Decodable {
    var name: String?
    var colorArgb: Int64?
    var icon: String?
    var isCustom: Bool?
    var createdAt: Int64?
    var parent: String?
    var bucket: String?
}

struct AndroidBudget: Decodable {
    var budgetKey: String?
    var amount: AndroidDecimal?
}

struct AndroidRule: Decodable {
    var name: String?
    var category: String?
}

struct AndroidRecurring: Decodable {
    var label: String?
    var amount: AndroidDecimal?
    var isIncome: Bool?
    var category: String?
    var cadence: String?
    var dueDay: Int?
    var createdAt: Int64?
    var autoPay: Bool?
    var nextDue: Int64?
    var lastPosted: Int64?
    var active: Bool?
}

struct AndroidSavingsGoal: Decodable {
    var id: Int64?
    var name: String?
    var emoji: String?
    var targetAmount: AndroidDecimal?
    var targetDate: Int64?
    var createdAt: Int64?
}

struct AndroidSavingsContribution: Decodable {
    var goalId: Int64?
    var amount: AndroidDecimal?
    var note: String?
    var date: Int64?
}

struct AndroidBuyingLimit: Decodable {
    var emoji: String?
    var label: String?
    var keywords: AndroidStringList?
    var timeframe: String?
    var count: Int?
    var createdAt: Int64?
}

struct AndroidWellbeingScore: Decodable {
    var periodId: String?
    var score: Int?
    var band: String?
    var componentsJson: String?
    var computedAt: Int64?
}

struct AndroidTag: Decodable {
    var name: String?
    var createdAt: Int64?
}

struct AndroidTransactionTag: Decodable {
    var transactionId: Int64?
    var tagName: String?
}

struct AndroidDebt: Decodable {
    var emoji: String?
    var name: String?
    var balance: AndroidDecimal?
    var aprPercent: AndroidDecimal?
    var minPayment: AndroidDecimal?
    var createdAt: Int64?
}

struct AndroidTemplate: Decodable {
    var emoji: String?
    var name: String?
    var amount: AndroidDecimal?
    var category: String?
    var store: String?
    var askAmount: Bool?
    var createdAt: Int64?
}

struct AndroidWarranty: Decodable {
    var name: String?
    var emoji: String?
    var store: String?
    var category: String?
    var purchaseDate: Int64?
    var durationMonths: Int?
    var coverageNote: String?
    var receiptId: Int64?
    var createdAt: Int64?
}

struct AndroidBudgetEnvelope: Decodable {
    var name: String?
    var emoji: String?
    var limitAmount: AndroidDecimal?
    var startDate: Int64?
    var endDate: Int64?
    var categories: AndroidStringList?
    var sortOrder: Int?
    var createdAt: Int64?
}

struct AndroidTrip: Decodable {
    var name: String?
    var tag: String?
    var startDate: Int64?
    var endDate: Int64?
    var budgetAmount: AndroidDecimal?
    var active: Bool?
    var createdAt: Int64?
    var endedAt: Int64?
}

struct AndroidIgnoredSubscription: Decodable {
    var merchant: String?
    var ignoredAt: Int64?
}

struct AndroidSettings: Decodable {
    var currency: String?
    var dateFormat: String?
    var language: String?
    var themeMode: String?
    var accent: String?
    var monthStartDay: Int?
    var budgetRolloverEnabled: Bool?
    var budgetCadence: String?
    var fortnightAnchorEpochDay: Int64?
    var hiddenHomeSections: [String]?
    var hiddenInsightsSections: [String]?
    var homeSectionOrder: [String]?
    var insightsSectionOrder: [String]?
    var customInsightsSections: [String]?
    var recapEnabled: Bool?
    var recapFrequency: String?
    var hideAmounts: Bool?
    var hideAmountsOnBackground: Bool?
}

/// A Kotlin `BigDecimal` as Gson writes it — a JSON number — read straight into `Decimal` (the decoder
/// parses the literal, so 1.84 stays exactly 1.84). Also accepts a numeric string, defensively.
struct AndroidDecimal: Decodable {
    let value: Decimal
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Decimal.self) {
            value = d
        } else if let s = try? c.decode(String.self), let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) {
            value = d
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a decimal")
        }
    }
}

/// A list Android stores newline-joined in one TEXT column (buying-limit keywords, envelope category
/// names). Accepts a JSON array too, defensively. Blank entries are dropped.
struct AndroidStringList: Decodable {
    let values: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw: [String]
        if let joined = try? c.decode(String.self) {
            raw = joined.components(separatedBy: "\n")
        } else {
            raw = try c.decode([String].self)
        }
        values = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
