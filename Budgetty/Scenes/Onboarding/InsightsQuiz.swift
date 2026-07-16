//
//  InsightsQuiz.swift
//  Budgetty
//
//  The one-time post-signup Insights setup questionnaire — the fixed question set plus the
//  deterministic mapping from answers to the Insights customization (hidden sections / order) and
//  the optional currency / income / budget seeds. Ported from Android's `InsightsQuiz.kt`, adapted
//  to the coarser iOS `InsightSection` model. Everything it sets is reversible in-app (Customize
//  sections, Account currency, Budget tab), so nothing here is permanent.
//

import SwiftUI

/// One selectable answer of a quiz question. `id` is persisted, so existing values must stay stable.
struct QuizOption: Identifiable {
    let id: String
    let emoji: String
    let label: LocalizedStringKey
    /// When true, picking this option reveals an inline amount field + Continue instead of auto-advancing.
    var revealsAmount = false
}

/// The optional inline amount field on a question. The amount is always optional — Continue works
/// with the field left blank.
struct QuizAmountField {
    let label: LocalizedStringKey
    let helper: LocalizedStringKey
}

/// One question step. `id` keys the answer map and is persisted; must stay stable.
struct QuizQuestion: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let options: [QuizOption]
    var amountFor: String?   // option id that reveals `amount`
    var amount: QuizAmountField?
}

/// A row of the closing step's "what got tailored" summary card.
struct QuizSummaryLine: Identifiable {
    let id = UUID()
    let emoji: String
    let text: LocalizedStringKey
}

enum InsightsQuiz {
    static let goal = "goal"
    static let income = "income"
    static let bills = "bills"
    static let budget = "budget"
    static let detail = "detail"
    static let entry = "entry"
    /// Answer-map key of the currency step (the stored value is the currency code).
    static let currency = "currency"

    /// Index of the currency step — right after the goal question, before income, so the amount
    /// fields can show the chosen symbol.
    static let currencyStep = 1

    /// Total steps before the closing one: the six questions plus the currency step.
    static var stepCount: Int { questions.count + 1 }

    /// The question shown at `step`, or nil when `step` is the currency step.
    static func question(at step: Int) -> QuizQuestion? {
        switch step {
        case currencyStep: nil
        case ..<currencyStep: questions[step]
        default: questions[step - 1]
        }
    }

    static let questions: [QuizQuestion] = [
        QuizQuestion(
            id: goal,
            title: "What's your main goal with Budgetty?",
            subtitle: "This shapes your Insights — change anytime.",
            options: [
                QuizOption(id: "see", emoji: "🔍", label: "See where my money goes"),
                QuizOption(id: "budget", emoji: "🎯", label: "Stick to a budget"),
                QuizOption(id: "bills", emoji: "📅", label: "Keep bills & subscriptions in check"),
                QuizOption(id: "savings", emoji: "🪙", label: "Save more each month"),
            ]
        ),
        QuizQuestion(
            id: income,
            title: "Do you want to track income too?",
            subtitle: "Income unlocks savings and cash-flow cards.",
            options: [
                QuizOption(id: "yes", emoji: "💰", label: "Yes — income and spending", revealsAmount: true),
                QuizOption(id: "no", emoji: "🧾", label: "No — just my spending"),
            ],
            amountFor: "yes",
            amount: QuizAmountField(
                label: "Your monthly income (roughly)",
                helper: "Optional — you can add exact income sources later."
            )
        ),
        QuizQuestion(
            id: bills,
            title: "Any recurring bills or subscriptions to watch?",
            subtitle: "Rent, streaming, gym — anything regular.",
            options: [
                QuizOption(id: "yes", emoji: "🔁", label: "Yes, I have recurring payments"),
                QuizOption(id: "no", emoji: "✨", label: "Not really"),
            ]
        ),
        QuizQuestion(
            id: budget,
            title: "Do you plan to set a spending budget?",
            subtitle: "Budgets add progress tracking to Insights.",
            options: [
                QuizOption(id: "yes", emoji: "✅", label: "Yes", revealsAmount: true),
                QuizOption(id: "later", emoji: "🤔", label: "Maybe later"),
                QuizOption(id: "no", emoji: "❌", label: "No"),
            ],
            amountFor: "yes",
            amount: QuizAmountField(
                label: "Monthly spending budget",
                helper: "Optional — switch to a weekly budget later in the Budget tab."
            )
        ),
        QuizQuestion(
            id: detail,
            title: "How much detail do you like?",
            subtitle: "You can always dig deeper later.",
            options: [
                QuizOption(id: "big", emoji: "🌅", label: "Just the big picture"),
                QuizOption(id: "full", emoji: "🔬", label: "All the details"),
            ]
        ),
        // Informational only for now: stored with the other answers, mapped to nothing.
        QuizQuestion(
            id: entry,
            title: "How will you mostly add expenses?",
            subtitle: "Just curious — it helps us tune things.",
            options: [
                QuizOption(id: "scan", emoji: "📷", label: "Scanning receipts"),
                QuizOption(id: "manual", emoji: "⌨️", label: "Typing them in"),
                QuizOption(id: "both", emoji: "🤝", label: "A bit of both"),
            ]
        ),
    ]

    // MARK: - Answer → Insights customization

    /// Sections hidden for `answers`. Never touches the core set (breakdown, stats, highlights,
    /// trend, top categories), so Insights stays coherent in the most minimal outcome. The iOS
    /// section model folds income + bills + savings into one `.income` card, so bills-off has no
    /// separate section to hide (it lives inside the income card, hidden with income).
    static func hiddenSections(_ answers: [String: String]) -> Set<InsightSection> {
        var hidden = Set<InsightSection>()
        if answers[income] == "no" { hidden.insert(.income) }
        if answers[budget] == "no" { hidden.insert(.budget) }
        if answers[detail] == "big" {
            hidden.formUnion([.topStores, .biggestPurchases, .comparison])
        }
        return hidden
    }

    /// Section order for `answers`: the main-goal sections move up right after the Breakdown hero.
    /// Empty (the app's default order) when the goal is the plain spending overview.
    static func sectionOrder(_ answers: [String: String]) -> [InsightSection] {
        let boosted: [InsightSection]
        switch answers[goal] {
        case "budget": boosted = [.budget, .comparison]
        case "bills": boosted = [.income]
        case "savings": boosted = [.income]
        default: return []
        }
        let head = [.breakdown] + boosted
        return head + InsightSection.allCases.filter { !head.contains($0) }
    }

    // MARK: - Seeds

    /// Parses an amount field's text into a positive amount (comma decimals ok), or nil if blank/invalid.
    static func amount(_ text: String) -> Decimal? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let d = Decimal(string: normalized), d > 0 else { return nil }
        return d
    }

    /// The income-source amount to seed on finish — only when income tracking was chosen.
    static func incomeSeed(_ answers: [String: String], _ amounts: [String: String]) -> Decimal? {
        answers[income] == "yes" ? amount(amounts[income] ?? "") : nil
    }

    /// The monthly-budget amount to seed on finish — only when a budget was planned.
    static func budgetSeed(_ answers: [String: String], _ amounts: [String: String]) -> Decimal? {
        answers[budget] == "yes" ? amount(amounts[budget] ?? "") : nil
    }

    // MARK: - Closing summary

    /// The closing step's summary rows. `incomeAmount` / `budgetAmount` are pre-formatted display
    /// amounts (nil when the field was left blank). A bills-yes answer is deliberately absent — it
    /// surfaces as the "add your bills" hand-off hint under the CTA instead of a summary row.
    static func summary(
        _ answers: [String: String],
        incomeAmount: String? = nil,
        budgetAmount: String? = nil
    ) -> [QuizSummaryLine] {
        var rows: [QuizSummaryLine] = []
        switch answers[goal] {
        case "see": rows.append(.init(emoji: "🔍", text: "Spending-overview layout"))
        case "budget": rows.append(.init(emoji: "🎯", text: "Budget-focused layout"))
        case "bills": rows.append(.init(emoji: "📅", text: "Bills-first layout"))
        case "savings": rows.append(.init(emoji: "🪙", text: "Savings-focused layout"))
        default: break
        }
        if let code = answers[currency] {
            rows.append(.init(emoji: "💱", text: "Currency — \(code)"))
        }
        if answers[income] == "yes", let incomeAmount {
            rows.append(.init(emoji: "💰", text: "Income set — \(incomeAmount)/month"))
        } else if answers[income] == "yes" {
            rows.append(.init(emoji: "💰", text: "Income & spending tracked"))
        } else if answers[income] == "no" {
            rows.append(.init(emoji: "🧾", text: "Spending only — income cards off"))
        }
        if answers[budget] == "yes", let budgetAmount {
            rows.append(.init(emoji: "✅", text: "Monthly budget — \(budgetAmount)"))
        }
        if answers[bills] == "no" {
            rows.append(.init(emoji: "✨", text: "Bills & subscriptions off"))
        }
        switch answers[detail] {
        case "big": rows.append(.init(emoji: "🌅", text: "Big-picture view"))
        case "full": rows.append(.init(emoji: "🔬", text: "Detailed view"))
        default: break
        }
        return rows
    }

    /// True when the closing step should show the "add your recurring bills" hand-off hint.
    static func showsBillsHint(_ answers: [String: String]) -> Bool { answers[bills] == "yes" }

    // MARK: - Currency helpers

    /// The region-suggested currency code pinned at the top of the currency step — the device's
    /// region currency when it's one we support, otherwise EUR.
    static var suggestedCurrencyCode: String {
        let region = Locale.current.currency?.identifier ?? "EUR"
        return CurrencyOption.all.contains { $0.code == region } ? region : "EUR"
    }

    /// Localized currency display name (e.g. "Euro", "Британска лира"), falling back to our English
    /// name and then the code.
    static func currencyName(_ code: String) -> String {
        if let localized = Locale.current.localizedString(forCurrencyCode: code) {
            return localized.prefix(1).uppercased() + localized.dropFirst()
        }
        return CurrencyOption.all.first { $0.code == code }?.name ?? code
    }

    /// Sanitizes typed amount text: digits plus at most one decimal point (a typed comma becomes the
    /// point — EU decimal keyboards only offer ','), capped so it never outgrows its row.
    static func sanitizeAmount(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        if let dot = cleaned.firstIndex(of: ".") {
            let head = cleaned[..<cleaned.index(after: dot)]
            let tail = cleaned[cleaned.index(after: dot)...].replacingOccurrences(of: ".", with: "")
            return String((head + tail).prefix(10))
        }
        return String(cleaned.prefix(10))
    }
}
