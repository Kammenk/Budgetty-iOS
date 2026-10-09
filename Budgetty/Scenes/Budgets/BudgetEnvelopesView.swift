//
//  BudgetEnvelopesView.swift
//  Budgetty
//
//  Budget → Multiple budgets ("envelopes"): named spending budgets beyond the single main budget,
//  each over its own date window and category scope, with a live pace bar. Each one's spend is summed
//  live from line items in the window matching the scope (same net-spend + paid-adjustment math as the
//  main budget). Free tier allows 1 extra budget; Premium is unlimited. Android parity:
//  `BudgetEnvelopesScreen` + `BudgetEnvelopesViewModel`.
//

import SwiftUI
import SwiftData

private let envelopeFreeLimit = 1
private let envelopeEmojis = ["🧾", "✈️", "🛒", "🎁", "🏠", "🎄", "🍽️", "🚗", "💊", "🎓", "🔧", "🐾", "💻", "🎉"]

private func paceColor(_ state: PaceState) -> Color {
    switch state {
    case .onPace: Palette.good
    case .ahead: Palette.warn
    case .overPace, .overBudget: Palette.bad
    }
}

struct BudgetEnvelopesView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.premium) private var premium = false
    @Query(sort: \BudgetEnvelope.createdAt) private var envelopes: [BudgetEnvelope]
    @Query private var items: [LineItem]

    @State private var editing: BudgetEnvelope?
    @State private var showNew = false
    @State private var showPaywall = false

    private var atCap: Bool { !premium && envelopes.count >= envelopeFreeLimit }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if envelopes.isEmpty {
                    Text("Create named budgets for trips, groceries or any category group, and track each one's pace.")
                        .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
                ForEach(envelopes) { env in
                    EnvelopeCard(envelope: env, spent: spend(for: env)) { editing = env }
                }
                if atCap {
                    Text("Free includes \(envelopeFreeLimit) extra budget. Premium adds as many as you need.")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2).padding(.top, 4)
                    Button { showPaywall = true } label: {
                        Label("Unlock unlimited budgets", systemImage: "lock.fill")
                            .frame(maxWidth: .infinity).ctaPill(height: 52)
                    }.buttonStyle(.plain)
                } else {
                    Button { showNew = true } label: {
                        Label("New budget", systemImage: "plus")
                            .frame(maxWidth: .infinity).ctaPill(height: 52)
                    }.buttonStyle(.plain).padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .underFloatingDock()
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Budgets").navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { EnvelopeEditSheet(original: $0) }
        .sheet(isPresented: $showNew) { EnvelopeEditSheet(original: nil) }
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
    }

    /// Net spend for an envelope: Σ line totals in its window matching its scope, plus each matched
    /// receipt's paid adjustment (on-top charges − discount), counted once. Mirrors Android's
    /// `spend() + paidAdjustmentOf`.
    private func spend(for env: BudgetEnvelope) -> Decimal {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: env.startDate)
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: env.endDate)) ?? env.endDate
        let scope = Set(env.categories)
        let inRange = items.filter {
            $0.purchaseDate >= startDay && $0.purchaseDate < endExclusive
                && (env.isAllSpending || scope.contains($0.category))
        }
        let itemsSum = inRange.reduce(Decimal.zero) { $0 + $1.lineTotal }
        var seen = Set<PersistentIdentifier>()
        var adjustment: Decimal = 0
        for item in inRange {
            if let r = item.receipt, seen.insert(r.persistentModelID).inserted {
                adjustment += r.additiveCharges - r.discount
            }
        }
        return itemsSum + adjustment
    }
}

private struct EnvelopeCard: View {
    let envelope: BudgetEnvelope
    let spent: Decimal
    let onTap: () -> Void

    var body: some View {
        let pace = BudgetPace.compute(spent: spent, limit: envelope.limitAmount,
                                      start: envelope.startDate, end: envelope.endDate, today: .now)
        let color = paceColor(pace.state)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.tintSoft)
                        .frame(width: 32, height: 32)
                        .overlay(Text(envelope.emoji.isEmpty ? "🧾" : envelope.emoji).font(.system(size: 17)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(envelope.name).font(.body).fontWeight(.bold).foregroundStyle(Palette.label).lineLimit(1)
                        Text("\(EnvelopeFormat.range(envelope.startDate, envelope.endDate)) · \(scopeLabel)")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(spent.formatMoney()) / \(envelope.limitAmount.formatMoney())")
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(color)
                }
                PaceBar(pace: pace, color: color).frame(height: 10)
                Text(paceSubtitle(pace)).font(.caption).foregroundStyle(color)
            }
            .padding(16).contentCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private var scopeLabel: String {
        envelope.isAllSpending ? String(localized: "All spending")
                               : String(localized: "\(envelope.categories.count) categories")
    }

    private func paceSubtitle(_ pace: PaceResult) -> String {
        switch pace.state {
        case .overBudget: String(localized: "Over budget by \((-pace.remaining).formatMoney()) · \(pace.daysLeft) days left")
        case .overPace: String(localized: "Over pace · \(pace.remaining.formatMoney()) left, \(pace.daysLeft) days")
        case .ahead: String(localized: "Slightly ahead · \(pace.dailyAllowance.formatMoney())/day for \(pace.daysLeft) days left")
        case .onPace: String(localized: "\(pace.dailyAllowance.formatMoney())/day for \(pace.daysLeft) days left")
        }
    }
}

/// The pace bar: a track, a coloured fill to `pace.fill`, and a "today" tick (haloed) at
/// `pace.todayFraction`. Android parity: `PaceBar` Canvas.
private struct PaceBar: View {
    let pace: PaceResult
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let h = size.height, w = size.width
            let r = h / 2
            let track = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: r)
            ctx.fill(track, with: .color(Palette.fill))
            let fillW = pace.fill <= 0 ? 0 : Swift.max(CGFloat(pace.fill) * w, h)
            if fillW > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: fillW, height: h), cornerRadius: r), with: .color(color))
            }
            let tx = Swift.min(Swift.max(CGFloat(pace.todayFraction) * w, 1.5), w - 1.5)
            var tick = Path(); tick.move(to: CGPoint(x: tx, y: -3)); tick.addLine(to: CGPoint(x: tx, y: h + 3))
            ctx.stroke(tick, with: .color(Palette.card), lineWidth: 7)
            ctx.stroke(tick, with: .color(Palette.label), lineWidth: 3)
        }
    }
}

enum EnvelopeFormat {
    static func range(_ s: Date, _ e: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: s) == cal.component(.year, from: e)
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }
}

/// Create / edit a budget envelope (mockup): emoji grid, name, amount, a date range (with a "This
/// month" quick-set), and a scope toggle (All spending / Some categories) with a category multi-select.
private struct EnvelopeEditSheet: View {
    let original: BudgetEnvelope?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Category> { $0.isCustom }, sort: \Category.createdAt) private var customCategories: [Category]

    private enum Scope: CaseIterable, Identifiable { case all, some; var id: Self { self } }

    @State private var name = ""
    @State private var emoji = "🧾"
    @State private var amount: Decimal = 0
    @State private var start = EnvelopeEditSheet.monthStart()
    @State private var end = EnvelopeEditSheet.monthEnd()
    @State private var scope: Scope = .all
    @State private var picked: Set<String> = []
    @State private var rangeSel: ClosedRange<Date>?
    @State private var showRange = false
    @FocusState private var focused: Bool

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 }

    private var categoryOptions: [(name: String, emoji: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for o in Categories.predefined.map({ ($0.name, $0.emoji) })
            + customCategories.map({ ($0.name, Categories.emoji(for: $0.name)) }) {
            if seen.insert(o.0).inserted { out.append(o) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(envelopeEmojis, id: \.self) { candidate in
                            Button { emoji = candidate } label: {
                                Text(candidate).font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(candidate == emoji ? Palette.tintSoft : Palette.fill,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                    labeledField("Name") {
                        TextField("Everyday", text: $name).focused($focused)
                    }
                    labeledField("Amount") {
                        TextField("0", value: $amount, format: .number).keyboardType(.decimalPad).focused($focused)
                    }
                    Button { rangeSel = start...end; showRange = true } label: {
                        Text(EnvelopeFormat.range(start, end)).frame(maxWidth: .infinity)
                            .glassControl(cornerRadius: 14).frame(height: 50)
                    }.buttonStyle(.plain)
                    Button("This month") { start = Self.monthStart(); end = Self.monthEnd() }
                        .font(.subheadline).foregroundStyle(Palette.tint)

                    Text("Counts").font(.caption).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
                    GlassSegmentedControl(options: Scope.allCases, selection: $scope) {
                        $0 == .all ? "All spending" : "Some categories"
                    }
                    if scope == .some {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(categoryOptions, id: \.name) { option in
                                let on = picked.contains(option.name)
                                Button {
                                    if on { picked.remove(option.name) } else { picked.insert(option.name) }
                                } label: {
                                    Text("\(on ? "✓ " : "")\(option.emoji) \(option.name)")
                                        .font(.caption).fontWeight(.medium)
                                        .foregroundStyle(on ? Palette.tint : Palette.label)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(on ? Palette.tintSoft : Palette.fill, in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if original != nil {
                        Button(role: .destructive) { delete() } label: {
                            Text("Delete").frame(maxWidth: .infinity)
                        }.padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle(original == nil ? "New budget" : "Edit budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .sheet(isPresented: $showRange) { DateRangeSheet(range: $rangeSel) }
            .onChange(of: rangeSel) { _, r in if let r { start = r.lowerBound; end = r.upperBound } }
        }
        .onAppear(perform: load)
    }

    private func labeledField(_ label: LocalizedStringKey, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
            field().padding(.horizontal, 14).frame(height: 48).glassControl(cornerRadius: 14)
        }
    }

    private func load() {
        guard let e = original else { return }
        name = e.name; emoji = e.emoji; amount = e.limitAmount
        start = e.startDate; end = e.endDate
        scope = e.isAllSpending ? .all : .some
        picked = Set(e.categories)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let limit = amount
        guard !trimmed.isEmpty, limit > 0 else { return }
        let cal = Calendar.current
        let s = cal.startOfDay(for: start), en = cal.startOfDay(for: end)
        let cats = scope == .some ? Array(picked) : []
        if let e = original {
            e.name = trimmed; e.emoji = emoji.isEmpty ? "🧾" : emoji; e.limitAmount = limit
            e.startDate = s; e.endDate = en; e.categories = cats
        } else {
            context.insert(BudgetEnvelope(name: trimmed, emoji: emoji.isEmpty ? "🧾" : emoji, limitAmount: limit,
                                          startDate: s, endDate: en, categories: cats))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let e = original { context.delete(e); try? context.save() }
        dismiss()
    }

    private static func monthStart() -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
    }
    private static func monthEnd() -> Date {
        let cal = Calendar.current
        let first = monthStart()
        let nextMonth = cal.date(byAdding: .month, value: 1, to: first) ?? first
        return cal.date(byAdding: .day, value: -1, to: nextMonth) ?? first
    }
}
