//
//  AndroidBackupImportTests.swift
//  BudgettyTests
//
//  iOS must restore a backup written by the Android app (device-test bug 7 — it used to fail with
//  "That file isn't a valid Budgetty backup."). The fixture below is hand-built from Android's entity
//  shapes as Gson writes them (BackupData.kt + data/local/*Entity.kt): flat transactions linked to
//  receipts by the upload-moment `receiptId`, epoch-millis numbers, BigDecimal as JSON numbers, null
//  fields omitted, newline-joined lists, a tag link table, and Kotlin enum NAMES in `settings`. The
//  tests pin the converted `BackupFile` field by field, then run it through a real `.replace` restore.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct AndroidBackupImportTests {

    // Epoch-millis anchors used by the fixture.
    private let pingoUpload: Int64 = 1_791_531_548_465     // receipt PK = upload moment
    private let pingoPrinted: Int64 = 1_781_222_400_000    // the receipt's printed date (June)
    private let haircutUpload: Int64 = 1_790_850_000_000
    private let haircutPrinted: Int64 = 1_790_812_800_000
    private let orphanUpload: Int64 = 1_789_100_000_000    // no receipt row in the file
    private let orphanPrinted: Int64 = 1_789_000_000_000
    private let legacyPrinted: Int64 = 1_770_000_000_000   // receiptId 0 (pre-receipt-id row)

    private func ms(_ v: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(v) / 1000) }

    private var fixture: Data {
        Data("""
        {
          "transactions": [
            {"id": 101, "name": "Milk 1L", "timestamp": \(pingoPrinted), "price": 1.84, "quantity": 2, "category": "Dairy", "receiptId": \(pingoUpload)},
            {"id": 102, "name": "Bread", "timestamp": \(pingoPrinted), "price": 0.71, "quantity": 1, "category": "Bakery", "receiptId": \(pingoUpload)},
            {"id": 103, "name": "Pastel de nata", "timestamp": \(pingoPrinted), "price": 1.5, "quantity": 3, "category": "Restaurant & Dining", "receiptId": \(pingoUpload)},
            {"id": 201, "name": "Haircut", "timestamp": \(haircutPrinted), "price": 25, "quantity": 1, "category": "Beauty", "receiptId": \(haircutUpload)},
            {"id": 301, "name": "Taxi", "timestamp": \(orphanPrinted), "price": 12.4, "quantity": 1, "category": "Transportation", "receiptId": \(orphanUpload)},
            {"id": 302, "name": "Tip", "timestamp": \(orphanPrinted), "price": 2, "quantity": 1, "category": "Transportation", "receiptId": \(orphanUpload)},
            {"id": 401, "name": "Legacy coffee", "timestamp": \(legacyPrinted), "price": 2.2, "quantity": 1, "category": "", "receiptId": 0}
          ],
          "categories": [
            {"name": "Groceries", "colorArgb": -11751600, "icon": "🧺", "isCustom": false, "createdAt": 0, "bucket": "WANT"},
            {"name": "Beauty", "colorArgb": -1499549, "icon": "💇", "isCustom": false, "createdAt": 0, "parent": "Health & Wellness"},
            {"name": "Dairy", "colorArgb": -16121, "icon": "🧀", "isCustom": false, "createdAt": 0},
            {"name": "Loan", "colorArgb": -14575885, "icon": "🏦", "isCustom": true, "createdAt": 1786000000000, "parent": "Services & Subscriptions", "bucket": "NEED"}
          ],
          "budgets": [{"budgetKey": "MONTHLY", "amount": 650}, {"budgetKey": "CAT:Groceries", "amount": 300.5}],
          "receipts": [
            {"timestamp": \(pingoUpload), "store": "Pingo Doce", "date": \(pingoPrinted), "discount": 0.5, "isManual": false, "tax": 1.2, "taxOnTop": false, "extraCharges": 0},
            {"timestamp": \(haircutUpload), "store": "", "date": \(haircutPrinted), "discount": 0.0, "isManual": true}
          ],
          "rules": [{"name": "milk 1l", "category": "Dairy"}],
          "recurring": [
            {"id": 1, "label": "Salary", "amount": 3200, "isIncome": true, "category": "", "cadence": "MONTHLY", "dueDay": 1, "createdAt": 1784355775514, "autoPay": false, "nextDue": 0, "lastPosted": 0, "active": true},
            {"id": 2, "label": "Car Loan", "amount": 679.58, "isIncome": false, "category": "Transportation", "cadence": "MONTHLY", "dueDay": 5, "createdAt": 1784355775600, "autoPay": true, "nextDue": 0, "lastPosted": 0, "active": true},
            {"id": 3, "label": "Netflix", "amount": 13.99, "isIncome": false, "category": "Services & Subscriptions", "cadence": "MONTHLY", "dueDay": 12, "createdAt": 1784355775700, "autoPay": false, "nextDue": 0, "lastPosted": 1790446519308, "active": true},
            {"id": 4, "label": "Insurance", "amount": 420, "isIncome": false, "category": "Services & Subscriptions", "cadence": "YEARLY", "dueDay": 3, "createdAt": 1784355775800, "autoPay": false, "nextDue": 0, "lastPosted": 0, "active": true},
            {"id": 5, "label": "Bonus", "amount": 500, "isIncome": true, "category": "", "cadence": "ONCE", "dueDay": 1, "createdAt": 1784355775900, "autoPay": false, "nextDue": 0, "lastPosted": 0, "active": true}
          ],
          "savingsGoals": [{"id": 7, "name": "Japan trip", "emoji": "🗾", "targetAmount": 6400.0, "targetDate": 1798761600000, "createdAt": 1786545349612}],
          "savingsContributions": [
            {"id": 1, "goalId": 7, "amount": 250.5, "note": "Bonus", "date": 1787000000000},
            {"id": 2, "goalId": 99, "amount": 10, "note": "", "date": 1787000000000}
          ],
          "buyingLimits": [{"id": 1, "emoji": "🥤", "label": "", "keywords": "coke\\ncola", "timeframe": "WEEKLY", "count": 2, "createdAt": 1787684447797}],
          "wellbeingScores": [{"periodId": "2026-08", "score": 60, "band": "HEALTHY", "componentsJson": "{\\"budget\\":80}", "computedAt": 1787764781441}],
          "tags": [{"name": "lisbon-2026", "createdAt": 1781000000000}, {"name": "unused", "createdAt": 1780000000000}],
          "transactionTags": [{"transactionId": 103, "tagName": "lisbon-2026"}],
          "debts": [{"id": 1, "emoji": "💳", "name": "Visa", "balance": 1200.55, "aprPercent": 19.9, "minPayment": 45, "createdAt": 1785000000000}],
          "templates": [{"id": 1, "emoji": "☕", "name": "Coffee", "amount": 2.2, "category": "Restaurant & Dining", "store": "Café", "askAmount": false, "createdAt": 1785000000000}],
          "warranties": [{"id": 1, "name": "Headphones", "emoji": "🎧", "store": "Worten", "category": "Electronics", "purchaseDate": \(pingoPrinted), "durationMonths": 24, "coverageNote": "", "receiptId": \(pingoUpload), "createdAt": 1791531600000}],
          "budgetEnvelopes": [
            {"id": 1, "name": "Holiday", "emoji": "🏖️", "limitAmount": 800, "startDate": \(pingoPrinted), "endDate": 1782000000000, "categories": "Restaurant & Dining\\nTransportation", "sortOrder": 0, "createdAt": 1781000000000},
            {"id": 2, "name": "Everything", "emoji": "🧾", "limitAmount": 2000, "startDate": \(pingoPrinted), "endDate": 1782000000000, "categories": "", "sortOrder": 1, "createdAt": 1781000000001}
          ],
          "trips": [{"id": 1, "name": "Lisbon", "tag": "lisbon-2026", "startDate": \(pingoPrinted), "endDate": 1781827200000, "budgetAmount": 900, "active": true, "createdAt": 1781000000000}],
          "ignoredSubscriptions": [{"merchant": "spotify", "ignoredAt": 1787000000000}],
          "settings": {
            "currency": "CHF", "dateFormat": "DMY_SLASH", "language": "GERMAN", "themeMode": "DARK", "accent": "DEFAULT",
            "monthStartDay": 25, "budgetRolloverEnabled": true, "budgetCadence": "FORTNIGHTLY", "fortnightAnchorEpochDay": 20600,
            "hiddenHomeSections": [], "hiddenInsightsSections": ["income_by_source", "top_stores"],
            "homeSectionOrder": ["receipts", "total_spent"], "insightsSectionOrder": [],
            "customInsightsSections": ["breakdown", "summary", "savings_rate"],
            "recapEnabled": true, "recapFrequency": "MONTHLY", "hideAmounts": false
          }
        }
        """.utf8)
    }

    private func converted() throws -> BackupFile { try BackupService.decode(fixture) }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "AndroidBackupImportTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (d, name)
    }

    // MARK: - Detection

    @Test func decodeAcceptsAnAndroidBackupAndStillRejectsJunk() throws {
        #expect(AndroidBackup.looksLikeAndroid(fixture))
        let file = try converted()
        #expect(file.app == "Budgetty Android")
        #expect(throws: BackupService.BackupError.self) { try BackupService.decode(Data("{\"hello\": 1}".utf8)) }
        #expect(throws: BackupService.BackupError.self) { try BackupService.decode(Data("not json".utf8)) }
    }

    @Test func anIOSBackupIsNeverMistakenForAndroid() throws {
        let ctx = try makeContext()
        let data = try BackupService.export(from: ctx)
        #expect(!AndroidBackup.looksLikeAndroid(data))
        #expect(try BackupService.decode(data).app == "Budgetty iOS")
    }

    // MARK: - Receipts + line items

    @Test func transactionsAreNestedUnderTheirReceipts() throws {
        let file = try converted()
        #expect(file.receipts.count == 4)
        #expect(file.itemCount == 7)

        let pingo = try #require(file.receipts.first { $0.store == "Pingo Doce" })
        #expect(pingo.createdAt == ms(pingoUpload))            // upload moment = Android PK
        #expect(pingo.date == ms(pingoPrinted))                // printed date
        #expect(pingo.discount == Decimal(string: "0.5"))
        #expect(pingo.tax == Decimal(string: "1.2"))
        #expect(!pingo.isManual)
        #expect(pingo.items.map(\.name) == ["Milk 1L", "Bread", "Pastel de nata"])
        #expect(pingo.items.allSatisfy { $0.createdAt == ms(pingoUpload) })
        let milk = try #require(pingo.items.first)
        #expect(milk.price == Decimal(string: "1.84"))         // exact — no binary-float drift
        #expect(milk.quantity == 2)
        #expect(milk.category == "Dairy")

        // A pre-v15 receipt row without tax / extraCharges keys still converts (zeros).
        let haircut = try #require(file.receipts.first { $0.createdAt == ms(haircutUpload) })
        #expect(haircut.isManual && haircut.tax == 0 && haircut.extraCharges == 0)
        #expect(haircut.items.map(\.name) == ["Haircut"])
    }

    @Test func orphanTransactionsBecomeManualReceipts() throws {
        let file = try converted()
        // An upload id with no receipt row → one manual receipt for its group, dated by the transaction.
        let orphan = try #require(file.receipts.first { $0.createdAt == ms(orphanUpload) })
        #expect(orphan.isManual && orphan.store.isEmpty)
        #expect(orphan.date == ms(orphanPrinted))
        #expect(orphan.items.map(\.name) == ["Taxi", "Tip"])
        // receiptId 0 → its own manual receipt; a blank category falls back to the default.
        let legacy = try #require(file.receipts.first { $0.items.first?.name == "Legacy coffee" })
        #expect(legacy.isManual && legacy.store.isEmpty)
        #expect(legacy.date == ms(legacyPrinted))
        #expect(legacy.items.first?.category == Categories.defaultName)
    }

    @Test func tagLinksLandOnTheirLineItemAndTheCatalogComesAlong() throws {
        let file = try converted()
        let items = file.receipts.flatMap(\.items)
        #expect(items.first { $0.name == "Pastel de nata" }?.tags == ["lisbon-2026"])
        #expect(items.filter { !($0.tags ?? []).isEmpty }.count == 1)
        #expect(file.tags?.map(\.name) == ["lisbon-2026", "unused"])
    }

    // MARK: - Everything else

    @Test func budgetsRulesAndCategoriesConvert() throws {
        let file = try converted()
        #expect(file.budgets.map(\.key) == ["MONTHLY", "CAT:Groceries"])
        #expect(file.budgets.last?.amount == Decimal(string: "300.5"))
        #expect(file.rules.map(\.name) == ["milk 1l"])

        // Only the custom category becomes an iOS custom category; colour bits re-packed unsigned.
        #expect(file.categories.map(\.name) == ["Loan"])
        let loan = try #require(file.categories.first)
        #expect(loan.colorArgb == Int(UInt32(truncatingIfNeeded: -14575885)))
        #expect(loan.parent == "Services & Subscriptions" && loan.bucket == "NEED")
        // Built-ins carry only their overrides; an untouched built-in (Dairy) isn't listed.
        let overrides = try #require(file.categoryOverrides)
        #expect(overrides.contains(CategoryOverrideDTO(name: "Groceries", parent: nil, bucket: "WANT")))
        #expect(overrides.contains(CategoryOverrideDTO(name: "Beauty", parent: "Health & Wellness", bucket: nil)))
        #expect(overrides.count == 2)
    }

    @Test func recurringCarriesCadenceAutopayAndPaidStamp() throws {
        let byLabel = Dictionary(uniqueKeysWithValues: try converted().recurring.map { ($0.label, $0) })
        #expect(byLabel.count == 5)
        #expect(byLabel["Car Loan"]?.autoPay == true)
        #expect(byLabel["Car Loan"]?.amount == Decimal(string: "679.58"))
        #expect(byLabel["Car Loan"]?.lastPosted == nil)        // 0 = never
        #expect(byLabel["Netflix"]?.lastPosted == ms(1_790_446_519_308))
        #expect(byLabel["Insurance"]?.cadenceRaw == Cadence.yearly.rawValue)
        #expect(byLabel["Bonus"]?.cadenceRaw == Cadence.once.rawValue)
        #expect(byLabel["Salary"]?.isIncome == true && byLabel["Salary"]?.dueDay == 1)
    }

    @Test func savingsLimitsEnvelopesAndTheRest() throws {
        let file = try converted()
        let goal = try #require(file.savingsGoals.first)
        #expect(goal.targetAmount == 6400 && goal.targetDate == ms(1_798_761_600_000))
        #expect(goal.contributions.map(\.amount) == [Decimal(string: "250.5")!])   // goalId 99 dropped

        let limit = try #require(file.buyingLimits?.first)
        #expect(limit.keywords == ["coke", "cola"])
        #expect(limit.timeframeRaw == "WEEKLY" && limit.count == 2)

        #expect(file.budgetEnvelopes?.map(\.categories) == [["Restaurant & Dining", "Transportation"], []])
        #expect(file.wellbeingScores?.first?.periodId == "2026-08")
        #expect(file.debts?.first?.aprPercent == Decimal(string: "19.9"))
        #expect(file.templates?.first?.amount == Decimal(string: "2.2"))
        #expect(file.trips?.first?.budgetAmount == 900 && file.trips?.first?.endedAt == nil)
        #expect(file.ignoredSubscriptions == [IgnoredSubscriptionDTO(merchant: "spotify", ignoredAt: ms(1_787_000_000_000))])

        // The warranty → receipt link survives the ms → s change: it equals the receipt's createdAt.
        let warranty = try #require(file.warranties?.first)
        let pingo = try #require(file.receipts.first { $0.store == "Pingo Doce" })
        #expect(warranty.receiptId == pingo.createdAt.timeIntervalSince1970)
    }

    // MARK: - Settings vocabulary

    @Test func settingsMapAndroidEnumNamesToIOSValues() throws {
        let s = try #require(try converted().settings)
        #expect(s.currency == "CHF")
        #expect(s.dateFormat == DateFormatOption.numeric.rawValue)
        #expect(s.language == "de")
        #expect(s.themeMode == AppearancePref.dark.rawValue)
        #expect(s.accent == AccentOption.violet.rawValue)
        #expect(s.monthStartDay == 25 && s.budgetRolloverEnabled == true)
        #expect(s.budgetCadence == "FORTNIGHTLY" && s.fortnightAnchor == 20600)
        #expect(s.recapFrequency == RecapFrequency.monthly.rawValue && s.recapEnabled == true)
        #expect(s.hiddenHomeSections == [])
        #expect(s.homeSectionOrder == ["receipts", "totalSpent"])
        #expect(s.hiddenInsightsSections == ["topStores"])          // Android-only key dropped
        #expect(s.customInsightsSections == ["breakdown", "stats"])
        #expect(s.hideAmounts == false && s.hideAmountsOnBackground == nil)
    }

    @Test func unmappableSettingsBecomeNilAndNeverReachDefaults() throws {
        let json = Data("""
        {"transactions": [], "settings": {"currency": "USD", "dateFormat": "JULIAN", "language": "KLINGON",
          "themeMode": "SEPIA", "accent": "NEON", "recapFrequency": "DAILY", "budgetCadence": "QUARTERLY",
          "monthStartDay": 40, "hiddenInsightsSections": ["wellbeing", "savings_rate"]}}
        """.utf8)
        let s = try #require(try BackupService.decode(json).settings)
        #expect(s.currency == nil && s.dateFormat == nil && s.language == nil && s.themeMode == nil)
        #expect(s.accent == nil && s.recapFrequency == nil && s.budgetCadence == nil && s.monthStartDay == nil)
        #expect(s.hiddenInsightsSections == nil)                       // nothing mapped → keep device layout

        let (d, name) = isolatedDefaults()
        defer { d.removePersistentDomain(forName: name) }
        d.set("fr", forKey: SettingsKey.language)
        d.set("light", forKey: SettingsKey.appearance)
        s.apply(into: d)
        #expect(d.string(forKey: SettingsKey.language) == "fr")
        #expect(d.string(forKey: SettingsKey.appearance) == "light")
    }

    @Test func systemLanguageMapsToTheIOSSystemValue() throws {
        let json = Data(#"{"transactions": [], "settings": {"language": "SYSTEM", "themeMode": "SYSTEM"}}"#.utf8)
        let s = try #require(try BackupService.decode(json).settings)
        #expect(s.language == "system" && s.themeMode == "system")
        let (d, name) = isolatedDefaults()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["de"], forKey: "AppleLanguages")
        s.apply(into: d)
        #expect(d.string(forKey: SettingsKey.language) == "system")    // never "SYSTEM"
        #expect(d.object(forKey: "AppleLanguages") as? [String] != ["de"])
    }

    // MARK: - End to end

    @Test func replaceRestoreOfAnAndroidBackupRebuildsTheAccount() throws {
        let ctx = try makeContext()
        // Built-ins as the seed leaves them, so the overrides have rows to land on.
        for name in ["Groceries", "Beauty", "Dairy"] { ctx.insert(Budgetty.Category(name: name, colorArgb: 1)) }
        ctx.insert(BudgetRollover(key: "MONTHLY", carried: 1200, periodKey: "2026-10"))
        try ctx.save()

        let (d, name) = isolatedDefaults()
        defer { d.removePersistentDomain(forName: name) }
        try BackupService.restore(try converted(), into: ctx, mode: .replace, defaults: d)

        let receipts = try ctx.fetch(FetchDescriptor<Receipt>())
        #expect(receipts.count == 4)
        #expect(receipts.flatMap(\.items).count == 7)
        let nata = try #require(receipts.flatMap(\.items).first { $0.name == "Pastel de nata" })
        #expect(nata.tags.map(\.name) == ["lisbon-2026"])
        #expect(nata.purchaseDate == ms(pingoPrinted))

        let loan = try #require(try ctx.fetch(FetchDescriptor<Recurring>()).first { $0.label == "Car Loan" })
        #expect(loan.isAutoPayActive)
        #expect(try ctx.fetch(FetchDescriptor<SavingsContribution>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<IgnoredSubscription>()).map(\.merchant) == ["spotify"])
        #expect(try ctx.fetch(FetchDescriptor<BudgetRollover>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Budgetty.Tag>()).count == 2)

        let cats = Dictionary(uniqueKeysWithValues: try ctx.fetch(FetchDescriptor<Budgetty.Category>()).map { ($0.name, $0) })
        #expect(cats["Groceries"]?.bucket == "WANT")
        #expect(cats["Beauty"]?.parent == "Health & Wellness")
        #expect(cats["Loan"]?.isCustom == true)

        // Settings landed as iOS values.
        #expect(d.string(forKey: SettingsKey.language) == "de")
        #expect(d.object(forKey: "AppleLanguages") as? [String] == ["de"])
        #expect(d.string(forKey: SettingsKey.appearance) == "dark")
        #expect(d.string(forKey: SettingsKey.dateFormat) == "dots")
        #expect(d.string(forKey: SettingsKey.budgetCadence) == "FORTNIGHTLY")
        #expect(d.integer(forKey: SettingsKey.fortnightAnchor) == 20600)
        #expect(d.string(forKey: InsightsLayoutStore.hiddenKey) == "topStores")
        #expect(d.string(forKey: SettingsKey.insightsCustomSections) == "breakdown,stats")
    }
}
