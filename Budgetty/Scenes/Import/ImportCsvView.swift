//
//  ImportCsvView.swift
//  Budgetty
//
//  Account → Import from CSV: a 4-step wizard (pick a file → map its columns → review options →
//  summary) that reads a bank/app CSV export and writes each expense row as a manual receipt + line
//  item. Income rows are recognised and counted but not imported (Budgetty tracks income as recurring).
//  FREE, no premium gate. Android parity: `ImportCsvScreen` + `ImportCsvViewModel`.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The four wizard steps: pick a file, map its columns, review options, then the summary.
enum ImportStep: Int { case pick, map, review, done }

/// The date layout the CSV uses, chosen on the Review step; maps to a `CsvImport` pattern.
enum ImportDateFormat: CaseIterable, Identifiable {
    case dmy, mdy, iso
    var id: Self { self }
    var pattern: String {
        switch self {
        case .dmy: CsvImport.patternDMY
        case .mdy: CsvImport.patternMDY
        case .iso: CsvImport.patternISO
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .dmy: "DD/MM/YYYY"
        case .mdy: "MM/DD/YYYY"
        case .iso: "YYYY-MM-DD"
        }
    }
    /// The import default derived from the user's display date-format preference.
    static var fromSettings: ImportDateFormat {
        switch DateFormatOption.current {
        case .monthDayYear: .mdy
        case .dayMonthYear, .numeric, .system: .dmy
        }
    }
}

/// A recoverable problem with the chosen file (shown in place of the file card on the Pick step).
enum ImportError { case readFailed, emptyFile }

/// One transaction the import will write once Review is confirmed.
struct PlannedTxn { let date: Date; let name: String; let amount: Decimal; let category: String }

/// The parsed outcome of the whole file under the current options — drives the Review counts.
struct ImportPlan {
    var toImport: [PlannedTxn] = []
    var duplicates = 0
    var income = 0
    var invalid = 0
    var filedAsOther = 0
    var minDate: Date?
    var maxDate: Date?
    var expenseTotal: Decimal = 0
}

/// What the summary step reports after the write completes.
struct ImportResult {
    let imported: Int, skippedDuplicates: Int, income: Int, invalid: Int, filedAsOther: Int
    let minDate: Date?, maxDate: Date?, expenseTotal: Decimal
}

struct ImportCsvView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectTab) private var selectTab

    @State private var step: ImportStep = .pick
    @State private var fileName = ""
    @State private var table = CsvTable(headers: [], rows: [])
    @State private var mapping: [CsvField] = []
    @State private var dateFormat: ImportDateFormat = .fromSettings
    @State private var sign: SignConvention = .minusIsExpense
    @State private var skipDuplicates = true
    @State private var plan: ImportPlan?
    @State private var result: ImportResult?
    @State private var error: ImportError?
    @State private var importing = false
    @State private var showPicker = false
    /// Receipts written by the last import, so Undo can delete exactly this batch (cascades to items).
    @State private var lastBatch: [Receipt] = []

    private var hasFile: Bool { !table.isEmpty }
    private var mappingError: CsvImport.MappingError? { CsvImport.mappingError(mapping) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .done { stepProgress }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch step {
                        case .pick: pickStep
                        case .map: mapStep
                        case .review: reviewStep
                        case .done: doneStep
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Import CSV").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { if step == .pick { dismiss() } else { back() } } label: {
                        Image(systemName: step == .pick ? "xmark" : "chevron.left")
                    }
                }
                if step != .done {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text("Step \(step.rawValue + 1) of 4").font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomCta }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { onPicked($0) }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Progress

    private var stepProgress: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i <= step.rawValue ? Palette.tint : Palette.fill).frame(height: 4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    // MARK: Pick

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Choose a file")
            if let error { errorNote(error) }
            if hasFile {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fileName).font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                    Text("\(table.rows.count) rows · \(table.headers.count) columns")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    Text(table.headers.joinedPreview())
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(2).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).contentCard(cornerRadius: 16)
                Button { showPicker = true } label: {
                    Text("Choose another file").frame(maxWidth: .infinity).glassControl(cornerRadius: 14).frame(height: 50)
                }.buttonStyle(.plain)
            } else {
                Button { showPicker = true } label: {
                    Label("Choose a file", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity).glassControl(cornerRadius: 14).frame(height: 50)
                }.buttonStyle(.plain)
            }
            Text("Opens the Files picker. Works with exports from most banks and budgeting apps.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
    }

    // MARK: Map

    private var mapStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Map columns")
            Text("We guessed from the headers. Tap a field to change it.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            VStack(spacing: 0) {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                    if index > 0 { Divider().padding(.leading, 16) }
                    columnMapRow(index: index, header: header,
                                 sample: table.rows.first.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "")
                }
            }
            .contentCard(cornerRadius: 16)
            if let mappingError { mappingWarning(mappingError) }

            let preview = Array(table.rows.prefix(3)).map {
                CsvImport.parseRow($0, mapping: mapping, pattern: dateFormat.pattern, sign: sign)
            }
            if !preview.isEmpty {
                Text("first \(preview.count) of \(table.rows.count)")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                VStack(spacing: 0) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { i, p in
                        if i > 0 { Divider().padding(.leading, 16) }
                        previewRow(p)
                    }
                }
                .contentCard(cornerRadius: 16)
            }
        }
    }

    private func columnMapRow(index: Int, header: String, sample: String) -> some View {
        let field = mapping.indices.contains(index) ? mapping[index] : .ignore
        let active = field != .ignore
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(header).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Palette.label).lineLimit(1)
                if !sample.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(sample).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button { cycleColumn(index) } label: {
                Text(fieldLabel(field)).font(.caption).fontWeight(.bold)
                    .foregroundStyle(active ? Palette.tint : Palette.secondaryLabel)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(active ? Palette.tintSoft : Palette.fill, in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func previewRow(_ p: ParsedImportRow) -> some View {
        HStack(spacing: 12) {
            Text(p.date.map(Self.shortDate) ?? "?")
                .font(.caption).foregroundStyle(p.date == nil ? Palette.bad : Palette.secondaryLabel)
            Text(p.name).font(.subheadline).foregroundStyle(Palette.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(amountText(p)).font(.subheadline).fontWeight(.bold)
                .foregroundStyle(p.kind == .income ? Palette.good : (p.kind == .invalid ? Palette.bad : Palette.label))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func amountText(_ p: ParsedImportRow) -> String {
        switch p.kind {
        case .expense: "−" + (p.amount?.formatMoney() ?? "")
        case .income: "+" + (p.amount?.formatMoney() ?? "")
        case .invalid: "?"
        }
    }

    // MARK: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Review")
            optionCard("Date format") {
                GlassSegmentedControl(options: ImportDateFormat.allCases, selection: $dateFormat) { $0.label }
                    .onChange(of: dateFormat) { _, _ in recomputePlan() }
            }
            optionCard("Amounts") {
                GlassSegmentedControl(options: SignConvention.allCases, selection: $sign) {
                    $0 == .minusIsExpense ? "− is an expense" : "− is income"
                }
                .onChange(of: sign) { _, _ in recomputePlan() }
            }
            Toggle(isOn: $skipDuplicates.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip likely duplicates").font(.body).foregroundStyle(Palette.label)
                    Text("Same date, amount and store as something already in Budgetty")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .tint(Palette.tint).padding(16).contentCard(cornerRadius: 16)
            .onChange(of: skipDuplicates) { _, _ in recomputePlan() }

            if let plan { planCounts(plan) }
        }
    }

    private func planCounts(_ plan: ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                countRow("Ready to import", plan.toImport.count)
                if plan.duplicates > 0 { Divider().padding(.leading, 16); countRow("Likely duplicates · skipped", plan.duplicates) }
                if plan.income > 0 { Divider().padding(.leading, 16); countRow("Income rows · not imported", plan.income) }
                if plan.invalid > 0 { Divider().padding(.leading, 16); countRow("Couldn't read · skipped", plan.invalid) }
                if plan.filedAsOther > 0 { Divider().padding(.leading, 16); countRow("Filed as Other", plan.filedAsOther) }
            }
            .contentCard(cornerRadius: 16)
            if plan.income > 0 {
                Text("Budgetty tracks income as recurring, so income rows are counted but not imported.")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
        }
    }

    // MARK: Done

    private var doneStep: some View {
        Group {
            if let result {
                VStack(alignment: .leading, spacing: 14) {
                    Text("✓").font(.title).fontWeight(.bold).foregroundStyle(Palette.good)
                        .frame(width: 56, height: 56).background(Palette.good.opacity(0.16), in: Circle())
                        .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                    Text("\(result.imported) imported").font(.title2).fontWeight(.bold).foregroundStyle(Palette.label)
                        .frame(maxWidth: .infinity, alignment: .center)
                    let skipped = result.skippedDuplicates + result.income + result.invalid
                    if skipped > 0 {
                        Text("\(skipped) skipped").font(.body).foregroundStyle(Palette.secondaryLabel)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    VStack(spacing: 0) {
                        if let lo = result.minDate, let hi = result.maxDate {
                            summaryRow("Date range", "\(Self.fullDate(lo)) – \(Self.fullDate(hi))")
                            Divider().padding(.leading, 16)
                        }
                        summaryRow("Expenses", "\(result.imported) · \(result.expenseTotal.formatMoney())")
                        if result.income > 0 { Divider().padding(.leading, 16); summaryRow("Income (not imported)", "\(result.income)") }
                        if result.filedAsOther > 0 { Divider().padding(.leading, 16); summaryRow("Filed as Other", "\(result.filedAsOther)") }
                    }
                    .contentCard(cornerRadius: 16).padding(.top, 4)
                    Text("Imported rows appear in History, Insights and Budget.")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    Button(role: .destructive) { undo() } label: {
                        Text("Undo this import").frame(maxWidth: .infinity).glassControl(cornerRadius: 14).frame(height: 50)
                    }.buttonStyle(.plain).tint(Palette.bad)
                }
            }
        }
    }

    // MARK: Bottom CTA

    @ViewBuilder private var bottomCta: some View {
        if let cfg = ctaConfig {
            Button { cfg.action() } label: {
                Text(cfg.label).font(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).ctaPill(height: 52).opacity(cfg.enabled ? 1 : 0.5)
            }
            .buttonStyle(.plain).disabled(!cfg.enabled)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
            .background(.ultraThinMaterial)
        }
    }

    private struct Cta { let label: LocalizedStringKey; let enabled: Bool; let action: () -> Void }

    private var ctaConfig: Cta? {
        switch step {
        case .pick:
            return hasFile ? Cta(label: "Map columns", enabled: true) { goToMap() } : nil
        case .map:
            return Cta(label: "Review", enabled: mappingError == nil) { goToReview() }
        case .review:
            let count = plan?.toImport.count ?? 0
            return Cta(label: "Import \(count)", enabled: count > 0 && !importing) { performImport() }
        case .done:
            return Cta(label: "View in History", enabled: true) { selectTab?(.history); dismiss() }
        }
    }

    // MARK: Small components

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.title3).fontWeight(.bold).foregroundStyle(Palette.label).padding(.top, 2)
    }

    private func optionCard(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).contentCard(cornerRadius: 16)
    }

    private func countRow(_ label: LocalizedStringKey, _ count: Int) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Text("\(count)").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func summaryRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func fieldLabel(_ f: CsvField) -> LocalizedStringKey {
        switch f {
        case .date: "Date"
        case .amount: "Amount"
        case .store: "Store"
        case .category: "Category"
        case .ignore: "Ignore"
        }
    }

    private func mappingWarning(_ error: CsvImport.MappingError) -> some View {
        let labels: [CsvField: String] = [.date: String(localized: "Date"), .amount: String(localized: "Amount"),
                                          .store: String(localized: "Store"), .category: String(localized: "Category")]
        let text: String
        switch error {
        case .missing(let fields):
            text = String(format: String(localized: "%@ must be mapped to continue."),
                          fields.compactMap { labels[$0] }.joined(separator: " & "))
        case .duplicated(let field):
            text = String(format: String(localized: "%@ is mapped twice; only one column can feed it."),
                          labels[field] ?? "")
        }
        return Text(text).font(.caption).foregroundStyle(Palette.bad).padding(.horizontal, 2)
    }

    private func errorNote(_ error: ImportError) -> some View {
        Text(error == .readFailed ? "Couldn't read that file. Try another."
                                  : "That file has no rows to import.")
            .font(.subheadline).foregroundStyle(Palette.bad)
    }

    // MARK: Actions

    private func onPicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            error = .readFailed
        case .success(let url):
            let name = url.lastPathComponent
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            onFileRead(name: name, text: text)
        }
    }

    private func onFileRead(name: String, text: String?) {
        guard let text else { error = .readFailed; return }
        let parsed = CsvImport.parse(text)
        if parsed.isEmpty || parsed.rows.isEmpty {
            fileName = name; table = CsvTable(headers: [], rows: []); mapping = []; error = .emptyFile
            return
        }
        fileName = name; table = parsed; mapping = CsvImport.guessMapping(parsed.headers); error = nil
    }

    private func cycleColumn(_ index: Int) {
        guard mapping.indices.contains(index) else { return }
        let all = CsvField.allCases
        mapping[index] = all[(mapping[index].rawValue + 1) % all.count]
    }

    private func goToMap() { step = .map }

    private func goToReview() {
        guard mappingError == nil else { return }
        step = .review
        recomputePlan()
    }

    private func back() {
        switch step {
        case .review: step = .map
        case .map: step = .pick
        default: break
        }
    }

    private func recomputePlan() {
        guard step == .review else { return }
        plan = buildPlan()
    }

    private func buildPlan() -> ImportPlan {
        let known = knownCategories()
        let existing: Set<String> = {
            let items = (try? context.fetch(FetchDescriptor<LineItem>())) ?? []
            return Set(items.map { CsvImport.dedupKey(date: $0.createdAt, amount: $0.lineTotal, name: $0.name) })
        }()
        var seen = Set<String>()
        var p = ImportPlan()
        for row in table.rows {
            let parsed = CsvImport.parseRow(row, mapping: mapping, pattern: dateFormat.pattern, sign: sign)
            switch parsed.kind {
            case .invalid: p.invalid += 1
            case .income: p.income += 1
            case .expense:
                guard let amount = parsed.amount, let date = parsed.date else { continue }
                let key = CsvImport.dedupKey(date: date, amount: amount, name: parsed.name)
                if skipDuplicates && (existing.contains(key) || seen.contains(key)) {
                    p.duplicates += 1
                } else {
                    seen.insert(key)
                    let category = resolveCategory(parsed.category, known: known)
                    if category == Categories.other { p.filedAsOther += 1 }
                    p.toImport.append(PlannedTxn(date: date, name: parsed.name, amount: amount, category: category))
                    p.expenseTotal += amount
                    p.minDate = p.minDate.map { min($0, date) } ?? date
                    p.maxDate = p.maxDate.map { max($0, date) } ?? date
                }
            }
        }
        return p
    }

    private func performImport() {
        guard let plan, !importing else { return }
        importing = true
        var batch: [Receipt] = []
        for p in plan.toImport {
            let receipt = Receipt(createdAt: p.date, store: p.name, date: p.date, isManual: true)
            let item = LineItem(name: p.name, createdAt: p.date, price: p.amount, quantity: 1,
                                category: p.category, receipt: receipt)
            receipt.items = [item]
            context.insert(receipt)
            context.insert(item)
            batch.append(receipt)
        }
        try? context.save()
        lastBatch = batch
        result = ImportResult(imported: plan.toImport.count, skippedDuplicates: plan.duplicates,
                              income: plan.income, invalid: plan.invalid, filedAsOther: plan.filedAsOther,
                              minDate: plan.minDate, maxDate: plan.maxDate, expenseTotal: plan.expenseTotal)
        importing = false
        step = .done
    }

    private func undo() {
        guard !lastBatch.isEmpty else { return }
        for r in lastBatch { context.delete(r) }
        try? context.save()
        lastBatch = []
        // Reset the wizard to its initial state.
        step = .pick; fileName = ""; table = CsvTable(headers: [], rows: [])
        mapping = []; plan = nil; result = nil; error = nil
    }

    private func knownCategories() -> [String: String] {
        let custom = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).filter(\.isCustom).map(\.name)
        let all = Categories.predefined.map(\.name) + custom
        return Dictionary(all.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func resolveCategory(_ raw: String, known: [String: String]) -> String {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if key.isEmpty { return Categories.other }
        return known[key] ?? Categories.other
    }

    // MARK: Date formatting

    nonisolated private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f.string(from: d)
    }
    nonisolated private static func fullDate(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy"); return f.string(from: d)
    }
}

private extension Array where Element == String {
    /// A compact, comma-joined header preview for the file card.
    func joinedPreview() -> String { joined(separator: ",") }
}
