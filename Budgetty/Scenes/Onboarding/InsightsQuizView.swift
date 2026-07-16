//
//  InsightsQuizView.swift
//  Budgetty
//
//  The post-signup Insights setup questionnaire UI (see `InsightsQuiz` for the steps and the
//  answer → customization mapping). Full-screen gate between registration and the main app:
//  finishing applies the derived section visibility/order plus the optional currency, income and
//  budget seeds; both finishing and skipping clear the pending flag that keeps the gate up.
//  Matches `iOS Insights Setup.dc.html` (Liquid Glass v2).
//

import SwiftUI
import SwiftData

struct InsightsQuizView: View {
    /// Called when the gate should come down (finish or skip) — clears the pending flag.
    var onComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.colorScheme) private var scheme

    @AppStorage(SettingsKey.currency) private var currencyCode = "EUR"
    @AppStorage(InsightsLayoutStore.orderKey) private var orderRaw = ""
    @AppStorage(InsightsLayoutStore.hiddenKey) private var hiddenRaw = ""

    @State private var step = 0
    @State private var answers: [String: String] = [:]
    @State private var amounts: [String: String] = [:]
    @State private var advanceTask: Task<Void, Never>?
    @FocusState private var amountFocused: Bool

    private var isExpanded: Bool { hSize == .regular }
    private var isDone: Bool { step == InsightsQuiz.stepCount }
    private var isCurrency: Bool { step == InsightsQuiz.currencyStep }

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        #if DEBUG
        // Screenshot hooks: jump to a step, and optionally pre-fill answers so the amount-reveal and
        // closing-summary states can be captured directly (there's no tap-driving in the CI path).
        let env = ProcessInfo.processInfo.environment
        if let s = env["QUIZ_STEP"].flatMap(Int.init) {
            _step = State(initialValue: max(0, min(s, InsightsQuiz.stepCount)))
        }
        var a: [String: String] = [:]
        var amt: [String: String] = [:]
        if env["QUIZ_DEMO"] == "1" {
            a = ["goal": "budget", "currency": "EUR", "income": "yes", "bills": "yes", "budget": "yes", "detail": "big"]
            amt = ["income": "2400", "budget": "1500"]
        }
        if env["QUIZ_REVEAL"] == "1" {
            a["income"] = "yes"; a["budget"] = "yes"; amt["income"] = "2400"; amt["budget"] = "1500"
        }
        if !a.isEmpty { _answers = State(initialValue: a) }
        if !amt.isEmpty { _amounts = State(initialValue: amt) }
        #endif
    }

    var body: some View {
        ZStack {
            Palette.canvas
            VStack(spacing: 0) {
                topBar
                if isDone {
                    doneStep
                } else {
                    questionArea
                }
            }
            .frame(maxWidth: isExpanded ? 520 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .onDisappear { advanceTask?.cancel() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: isExpanded ? 16 : 14) {
            Button {
                back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: isExpanded ? 18 : 17, weight: .bold))
                    .foregroundStyle(Palette.label)
                    .frame(width: isExpanded ? 36 : 34, height: isExpanded ? 36 : 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.matPillBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .opacity(showBack ? 1 : 0)
            .disabled(!showBack)

            HStack(spacing: isExpanded ? 6 : 5) {
                ForEach(0..<InsightsQuiz.stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i < filledSegments ? Palette.tint : Palette.fill)
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.25), value: filledSegments)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                onComplete()
            } label: {
                Text("Skip")
                    .font(.system(size: isExpanded ? 16 : 15, weight: .medium))
                    .foregroundStyle(Palette.secondaryLabel)
                    .padding(.horizontal, 2).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .frame(minWidth: isExpanded ? 36 : 34, alignment: .trailing)
            .opacity(isDone ? 0 : 1)
            .disabled(isDone)
        }
        .frame(height: isExpanded ? 56 : 48)
        .padding(.horizontal, isExpanded ? 0 : 16)
        .padding(.top, isExpanded ? 10 : 4)
    }

    private var showBack: Bool { step >= 1 && !isDone }
    private var filledSegments: Int { isDone ? InsightsQuiz.stepCount : min(step + 1, InsightsQuiz.stepCount) }

    // MARK: - Question / currency area

    private var questionArea: some View {
        GeometryReader { proxy in
            ScrollView {
                stepBody
                    .padding(.horizontal, isExpanded ? 0 : 20)
                    .padding(.top, isExpanded ? 20 : 16)
                    .padding(.bottom, 44)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .id(step) // fresh transition per step
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isCurrency {
                currencyPicker
            } else if let q = InsightsQuiz.question(at: step) {
                optionCards(q)
                if let field = q.amount, answers[q.id] == q.amountFor {
                    amountField(q, field)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Question \(step + 1) of \(InsightsQuiz.stepCount)")
                .font(.system(size: isExpanded ? 13.5 : 13, weight: .semibold))
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.bottom, isExpanded ? 12 : 10)
            Text(headerTitle)
                .font(.system(size: isExpanded ? 34 : 28, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(Palette.label)
                .padding(.bottom, isExpanded ? 12 : 10)
            Text(headerSubtitle)
                .font(.system(size: isExpanded ? 16.5 : 15.5))
                .foregroundStyle(Palette.secondaryLabel)
                .lineSpacing(3)
                .padding(.bottom, isExpanded ? 30 : 24)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var headerTitle: LocalizedStringKey {
        if isCurrency { return "Which currency do you use?" }
        return InsightsQuiz.question(at: step)?.title ?? ""
    }
    private var headerSubtitle: LocalizedStringKey {
        if isCurrency { return "Used for every amount in the app — change anytime in Account." }
        return InsightsQuiz.question(at: step)?.subtitle ?? ""
    }

    // MARK: - Option cards

    private func optionCards(_ q: QuizQuestion) -> some View {
        VStack(spacing: isExpanded ? 12 : 10) {
            ForEach(q.options) { opt in
                optionRow(q, opt)
            }
        }
    }

    private func optionRow(_ q: QuizQuestion, _ opt: QuizOption) -> some View {
        let selected = answers[q.id] == opt.id
        return Button {
            select(q, opt)
        } label: {
            HStack(spacing: isExpanded ? 14 : 12) {
                emojiChip(opt.emoji, selected: selected, size: isExpanded ? 40 : 36,
                          corner: isExpanded ? 12 : 11, font: isExpanded ? 21 : 19)
                Text(opt.label)
                    .font(.system(size: isExpanded ? 17 : 16, weight: selected ? .bold : .semibold))
                    .foregroundStyle(Palette.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                checkBadge(selected, size: isExpanded ? 24 : 22)
            }
            .padding(.vertical, isExpanded ? 12 : 10)
            .padding(.horizontal, isExpanded ? 14 : 12)
            .frame(minHeight: isExpanded ? 64 : 56)
            .background(selected ? selectedFill : Palette.card,
                        in: RoundedRectangle(cornerRadius: isExpanded ? 18 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isExpanded ? 18 : 16, style: .continuous)
                    .strokeBorder(selected ? Palette.tint : .clear, lineWidth: 2)
            )
            .shadow(color: Palette.cardShadow.opacity(0.5), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    // MARK: - Currency picker

    private var currencyPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Suggested for your region")
                .padding(.bottom, isExpanded ? 9 : 8)
            currencyRow(currencyCode, pinned: true)
            sectionLabel("All currencies")
                .padding(.top, isExpanded ? 22 : 20)
                .padding(.bottom, isExpanded ? 9 : 8)
            VStack(spacing: isExpanded ? 9 : 8) {
                ForEach(CurrencyOption.all.filter { $0.code != currencyCode }, id: \.code) { c in
                    currencyRow(c.code, pinned: false)
                }
            }
        }
    }

    private func currencyRow(_ code: String, pinned: Bool) -> some View {
        let selected = answers[InsightsQuiz.currency] == code
        let symbol = CurrencyOption.symbol(code)
        return Button {
            selectCurrency(code)
        } label: {
            HStack(spacing: isExpanded ? 14 : 12) {
                Text(symbol)
                    .font(.system(size: symbolSize(symbol), weight: .bold))
                    .foregroundStyle(Palette.label)
                    .frame(width: isExpanded ? 36 : 32, height: isExpanded ? 36 : 32)
                    .background(selected || pinned ? chipSelectedBg : Palette.fill,
                                in: RoundedRectangle(cornerRadius: isExpanded ? 10 : 9, style: .continuous))
                Text(code)
                    .font(.system(size: isExpanded ? 17 : 16, weight: selected ? .bold : .semibold))
                    .foregroundStyle(Palette.label)
                Text(InsightsQuiz.currencyName(code))
                    .font(.system(size: isExpanded ? 15 : 14))
                    .foregroundStyle(Palette.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                checkBadge(selected, size: isExpanded ? 24 : 22)
            }
            .padding(.vertical, isExpanded ? 9 : 7)
            .padding(.horizontal, isExpanded ? 14 : 12)
            .frame(minHeight: pinned ? (isExpanded ? 56 : 50) : (isExpanded ? 52 : 48))
            .background(rowBackground(selected: selected, pinned: pinned),
                        in: RoundedRectangle(cornerRadius: isExpanded ? 16 : 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isExpanded ? 16 : 14, style: .continuous)
                    .strokeBorder(selected ? Palette.tint : .clear, lineWidth: 2)
            )
            .shadow(color: Palette.cardShadow.opacity(pinned ? 0.6 : 0.4),
                    radius: pinned ? 9 : 2, y: pinned ? 4 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    private func rowBackground(selected: Bool, pinned: Bool) -> Color {
        if selected { return selectedFill }
        if pinned { return Palette.tertiaryBackground }
        return Palette.card
    }

    private func symbolSize(_ symbol: String) -> CGFloat {
        if symbol.count >= 3 { return isExpanded ? 11 : 10 }
        if symbol.count == 2 { return isExpanded ? 13.5 : 12.5 }
        return isExpanded ? 18 : 17
    }

    // MARK: - Amount field + Continue

    private func amountField(_ q: QuizQuestion, _ field: QuizAmountField) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(field.label)
                .font(.system(size: isExpanded ? 13.5 : 13, weight: .semibold))
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.bottom, isExpanded ? 9 : 8)
            HStack(alignment: .firstTextBaseline, spacing: isExpanded ? 8 : 7) {
                TextField("0", text: amountBinding(q.id))
                    .font(.system(size: isExpanded ? 31 : 28, weight: .bold))
                    .foregroundStyle(Palette.label)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .fixedSize()
                Text(CurrencyOption.symbol(currencyCode))
                    .font(.system(size: isExpanded ? 22 : 20, weight: .semibold))
                    .foregroundStyle(Palette.secondaryLabel)
                Spacer(minLength: 0)
            }
            .padding(.vertical, isExpanded ? 17 : 15)
            .padding(.horizontal, isExpanded ? 20 : 18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: isExpanded ? 18 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isExpanded ? 18 : 16, style: .continuous)
                    .strokeBorder(Palette.separatorStrong, lineWidth: 0.5)
            )
            Text(field.helper)
                .font(.system(size: isExpanded ? 14 : 13))
                .foregroundStyle(Palette.secondaryLabel)
                .lineSpacing(2)
                .padding(.top, isExpanded ? 9 : 8)
                .fixedSize(horizontal: false, vertical: true)
            Button { advance() } label: {
                Text("Continue").font(.system(size: 17, weight: .semibold)).ctaPill(height: isExpanded ? 54 : 50)
            }
            .buttonStyle(.plain)
            .padding(.top, isExpanded ? 22 : 18)
        }
        .padding(.top, isExpanded ? 26 : 22)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func amountBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { amounts[id] ?? "" },
            set: { amounts[id] = InsightsQuiz.sanitizeAmount($0) }
        )
    }

    // MARK: - Closing step

    private var doneStep: some View {
        let incomeAmount = InsightsQuiz.incomeSeed(answers, amounts)?.formatMoney()
        let budgetAmount = InsightsQuiz.budgetSeed(answers, amounts)?.formatMoney()
        let rows = InsightsQuiz.summary(answers, incomeAmount: incomeAmount, budgetAmount: budgetAmount)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("🎉")
                .font(.system(size: isExpanded ? 44 : 38))
                .frame(width: isExpanded ? 88 : 76, height: isExpanded ? 88 : 76)
                .background(selectedFill, in: RoundedRectangle(cornerRadius: isExpanded ? 26 : 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 26 : 22, style: .continuous)
                        .strokeBorder(Palette.separatorStrong, lineWidth: 0.5)
                )
                .padding(.bottom, isExpanded ? 22 : 18)
            Text("You're all set!")
                .font(.system(size: isExpanded ? 34 : 30, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
                .padding(.bottom, isExpanded ? 12 : 10)
            Text("Insights are tailored to you — they'll fill in as you add your first receipts.")
                .font(.system(size: isExpanded ? 17 : 15.5))
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: isExpanded ? 380 : 300)
                .padding(.bottom, isExpanded ? 30 : 26)
            summaryCard(rows)
            Text("Change anytime in Insights → ⋮ → Customize sections.")
                .font(.system(size: isExpanded ? 13 : 12.5))
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.top, isExpanded ? 16 : 14)
            Spacer(minLength: 0)
            Button { finish() } label: {
                Text("Get started").font(.system(size: 17, weight: .semibold)).ctaPill(height: isExpanded ? 54 : 50)
            }
            .buttonStyle(.plain)
            .padding(.top, isExpanded ? 20 : 12)
            if InsightsQuiz.showsBillsHint(answers) {
                Text("Next: add your recurring bills in the Budget tab")
                    .font(.system(size: isExpanded ? 14 : 13.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, isExpanded ? 16 : 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer().frame(height: isExpanded ? 24 : 20)
        }
        .padding(.horizontal, isExpanded ? 0 : 24)
    }

    private func summaryCard(_ rows: [QuizSummaryLine]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: isExpanded ? 14 : 12) {
                    Text(row.emoji).font(.system(size: isExpanded ? 18 : 17))
                    Text(row.text)
                        .font(.system(size: isExpanded ? 16 : 15, weight: .semibold))
                        .foregroundStyle(Palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, isExpanded ? 7 : 6)
                .padding(.horizontal, isExpanded ? 18 : 16)
                .frame(minHeight: isExpanded ? 50 : 46)
                if index < rows.count - 1 {
                    Divider().overlay(Palette.separator).padding(.leading, isExpanded ? 18 : 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous)
                .strokeBorder(Palette.separatorStrong, lineWidth: 0.5)
        )
        .shadow(color: Palette.cardShadow.opacity(0.6), radius: 12, y: 8)
    }

    // MARK: - Shared bits

    private func emojiChip(_ emoji: String, selected: Bool, size: CGFloat, corner: CGFloat, font: CGFloat) -> some View {
        Text(emoji)
            .font(.system(size: font))
            .frame(width: size, height: size)
            .background(selected ? chipSelectedBg : Palette.fill,
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: selected ? .clear : .black.opacity(0.1), radius: 1.5, y: 1)
    }

    private func checkBadge(_ selected: Bool, size: CGFloat) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(checkForeground)
            .frame(width: size, height: size)
            .background(Palette.tint, in: Circle())
            .opacity(selected ? 1 : 0)
            .scaleEffect(selected ? 1 : 0.4)
            .animation(.easeOut(duration: 0.18), value: selected)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: isExpanded ? 11.5 : 11, weight: .bold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Palette.secondaryLabel)
    }

    private var selectedFill: Color { Palette.tint.opacity(scheme == .dark ? 0.16 : 0.10) }
    private var chipSelectedBg: Color { Color.white.opacity(scheme == .dark ? 0.18 : 0.95) }
    private var checkForeground: Color {
        scheme == .dark ? Color(red: 0.14, green: 0.10, blue: 0.28) : .white
    }

    // MARK: - Flow

    private func select(_ q: QuizQuestion, _ opt: QuizOption) {
        advanceTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { answers[q.id] = opt.id }
        if opt.revealsAmount {
            // Wait for Continue; pull up the keyboard once the reveal has landed.
            advanceTask = Task {
                try? await Task.sleep(for: .milliseconds(320))
                if !Task.isCancelled { amountFocused = true }
            }
        } else {
            armAdvance()
        }
    }

    private func selectCurrency(_ code: String) {
        advanceTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { answers[InsightsQuiz.currency] = code }
        currencyCode = code  // apply live, so it stays pinned when the user comes Back
        armAdvance()
    }

    private func armAdvance() {
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { advance() }
        }
    }

    private func advance() {
        amountFocused = false
        withAnimation(.easeInOut(duration: 0.28)) { step = min(step + 1, InsightsQuiz.stepCount) }
    }

    private func back() {
        advanceTask?.cancel()
        amountFocused = false
        withAnimation(.easeInOut(duration: 0.28)) { step = max(step - 1, 0) }
    }

    /// Apply the derived customization + optional seeds, then bring the gate down.
    private func finish() {
        let order = InsightsQuiz.sectionOrder(answers)
        if !order.isEmpty { orderRaw = InsightsLayoutStore.csv(order) }
        hiddenRaw = InsightsLayoutStore.csv(InsightsQuiz.hiddenSections(answers))

        if let income = InsightsQuiz.incomeSeed(answers, amounts) {
            context.insert(Recurring(label: String(localized: "Income"), amount: income,
                                     isIncome: true, cadence: .monthly, dueDay: 1))
        }
        if let budget = InsightsQuiz.budgetSeed(answers, amounts) {
            let existing = try? context.fetch(
                FetchDescriptor<Budget>(predicate: #Predicate { $0.key == "MONTHLY" })
            )
            if let b = existing?.first { b.amount = budget }
            else { context.insert(Budget(key: Budget.monthlyKey, amount: budget)) }
        }
        try? context.save()
        onComplete()
    }
}

#Preview("Quiz") {
    InsightsQuizView(onComplete: {})
        .modelContainer(for: [Budget.self, Recurring.self], inMemory: true)
}
