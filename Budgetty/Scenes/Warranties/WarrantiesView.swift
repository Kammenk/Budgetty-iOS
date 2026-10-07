//
//  WarrantiesView.swift
//  Budgetty
//
//  Account → Warranties (mockup 1a–1g): tracked warranties grouped by urgency (expiring soon → active
//  → expired) with each row's elapsed ring + countdown chip, an add/edit sheet, and the free-tier cap
//  (5 free; adding past it routes to the paywall). Android parity: `WarrantiesScreen` + `WarrantiesViewModel`.
//  No push reminders (Android omitted them) — warranties surface in-app only.
//

import SwiftUI
import SwiftData

/// The ring colour for a warranty state: green active, amber expiring-soon, muted expired.
func warrantyColor(_ s: WarrantyState) -> Color {
    switch s {
    case .active: Palette.good
    case .expiringSoon: Palette.warn
    case .expired: Palette.secondaryLabel
    }
}

/// The countdown chip for a warranty row.
func warrantyChip(_ st: WarrantyStatus) -> String {
    switch st.state {
    case .expired: String(format: String(localized: "Expired %@"), WarrantyFormat.date(st.expiryDate))
    case .expiringSoon: String(localized: "Expires in \(max(0, st.daysLeft)) days")
    case .active: String(localized: "\(st.monthsLeft) months left")
    }
}

enum WarrantyFormat {
    static func date(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy"); return f.string(from: d)
    }
}

/// An elapsed-coverage ring (full track + a coloured arc), with optional centre text.
struct WarrantyRing: View {
    let fraction: Double
    let color: Color
    var size: CGFloat = 44
    var lineWidth: CGFloat = 4.5
    var centerText: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(Palette.fill, lineWidth: lineWidth)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let centerText {
                Text(centerText).font(.system(size: size * 0.23, weight: .bold)).foregroundStyle(Palette.label)
            }
        }
        .frame(width: size, height: size)
    }
}

struct WarrantiesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Warranty.createdAt) private var warranties: [Warranty]
    @AppStorage(SettingsKey.premium) private var premium = false

    @State private var editing: Warranty?
    @State private var showAdd = false
    @State private var showPaywall = false

    private struct Card { let w: Warranty; let status: WarrantyStatus }

    private var cards: [Card] {
        warranties.map { Card(w: $0, status: Warranties.status(purchaseDate: $0.purchaseDate, durationMonths: $0.durationMonths)) }
    }
    private var expiringSoon: [Card] { cards.filter { $0.status.state == .expiringSoon }.sorted { $0.status.daysLeft < $1.status.daysLeft } }
    private var active: [Card] { cards.filter { $0.status.state == .active }.sorted { $0.status.daysLeft < $1.status.daysLeft } }
    private var expired: [Card] { cards.filter { $0.status.state == .expired }.sorted { $0.status.expiryDate > $1.status.expiryDate } }
    private var atCap: Bool { !premium && warranties.count >= Warranties.freeLimit }

    var body: some View {
        Group {
            if warranties.isEmpty { emptyState } else { list }
        }
        .navigationTitle("Warranties").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { if atCap { showPaywall = true } else { showAdd = true } } label: {
                    Image(systemName: atCap ? "lock.fill" : "plus")
                }
            }
        }
        .sheet(item: $editing) { WarrantyEditSheet(existing: $0) }
        .sheet(isPresented: $showAdd) { WarrantyEditSheet(existing: nil) }
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !premium {
                    Text("\(warranties.count) of \(Warranties.freeLimit) free")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20)
                }
                group("EXPIRING SOON", expiringSoon)
                group("ACTIVE", active)
                group("EXPIRED", expired)
                Text("Expired warranties stay here for reference.")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.horizontal, 36)
            }
            .padding(.top, 8).padding(.bottom, 24)
        }
        .background(Palette.groupedBackground)
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ items: [Card]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                    .padding(.leading, 36)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.w.persistentModelID) { idx, c in
                        if idx > 0 { Divider().padding(.leading, 66) }
                        row(c)
                    }
                }
                .contentCard(cornerRadius: 18)
                .padding(.horizontal, 20)
            }
        }
    }

    private func row(_ c: Card) -> some View {
        let expired = c.status.state == .expired
        return Button { editing = c.w } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.tintSoft)
                    .frame(width: 38, height: 38)
                    .overlay(Text(c.w.emoji.isEmpty ? "🛡️" : c.w.emoji).font(.system(size: 19)).grayscale(expired ? 1 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.w.name).font(.body).foregroundStyle(Palette.label).lineLimit(1)
                    Text("\(c.w.store.isEmpty ? Categories.displayName(c.w.category.isEmpty ? "—" : c.w.category) : c.w.store) · \(WarrantyFormat.date(c.w.purchaseDate))")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                    Text(warrantyChip(c.status)).font(.caption).fontWeight(.semibold)
                        .foregroundStyle(warrantyColor(c.status.state))
                }
                Spacer(minLength: 8)
                WarrantyRing(fraction: c.status.elapsedFraction, color: warrantyColor(c.status.state),
                             centerText: expired ? "—" : "\(Int(c.status.elapsedFraction * 100))%")
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .opacity(expired ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🛡️").font(.system(size: 42))
                .frame(width: 84, height: 84)
                .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("No warranties yet").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("Track warranties on electronics and appliances, and see what's expiring at a glance.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button { showAdd = true } label: { Text("Add a warranty").font(.body).fontWeight(.semibold).ctaPill(height: 48) }
                .buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 20)
        .background(Palette.groupedBackground)
    }
}

/// Create / edit a warranty (mockup 1d/1e): product, emoji, store, category, purchase date, and the
/// coverage length as a segmented 1 yr / 2 yr / 3 yr / Custom control. A live line shows the derived
/// expiry so the length edit is obvious. Delete lives at the bottom when editing.
struct WarrantyEditSheet: View {
    let existing: Warranty?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Length: Hashable { case y1, y2, y3, custom }

    @State private var name = ""
    @State private var emoji = ""
    @State private var store = ""
    @State private var category = Categories.defaultName
    @State private var purchaseDate: Date = .now
    @State private var length: Length = .y2
    @State private var customMonths = 24
    @State private var coverageNote = ""
    @State private var showCategoryPicker = false
    @FocusState private var focused: Field?
    private enum Field { case name, emoji, store, custom, note }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var shownEmoji: String { emoji.isEmpty ? "🛡️" : emoji }
    private var months: Int {
        switch length {
        case .y1: 12
        case .y2: 24
        case .y3: 36
        case .custom: max(1, customMonths)
        }
    }
    private var preview: WarrantyStatus {
        Warranties.status(purchaseDate: purchaseDate, durationMonths: months)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.tintSoft)
                                .frame(width: 64, height: 64)
                                .overlay(Text(shownEmoji).font(.system(size: 32)))
                            TextField("Emoji", text: $emoji)
                                .multilineTextAlignment(.center).frame(width: 90)
                                .focused($focused, equals: .emoji)
                                .font(.caption).foregroundStyle(Palette.tint)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Product") {
                        TextField("MacBook Pro", text: $name).multilineTextAlignment(.trailing)
                            .focused($focused, equals: .name)
                    }
                    Button { showCategoryPicker = true } label: {
                        HStack {
                            Text("Category").foregroundStyle(Palette.label)
                            Spacer()
                            Text("\(Categories.emoji(for: category)) \(Categories.displayName(category))")
                                .foregroundStyle(Palette.secondaryLabel)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.tertiaryLabel)
                        }
                    }
                }
                Section {
                    DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                    Picker("Length", selection: $length) {
                        Text("1 yr").tag(Length.y1)
                        Text("2 yr").tag(Length.y2)
                        Text("3 yr").tag(Length.y3)
                        Text("Custom").tag(Length.custom)
                    }
                    .pickerStyle(.segmented)
                    if length == .custom {
                        LabeledContent("Months") {
                            TextField("24", value: $customMonths, format: .number)
                                .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                                .focused($focused, equals: .custom)
                        }
                    }
                } header: {
                    Text("Coverage")
                } footer: {
                    Text("Covered until \(WarrantyFormat.date(preview.expiryDate)) · \(warrantyChip(preview))")
                        .foregroundStyle(warrantyColor(preview.state))
                }
                Section("Optional") {
                    LabeledContent("Store") {
                        TextField("Apple Store", text: $store).multilineTextAlignment(.trailing)
                            .focused($focused, equals: .store)
                    }
                    LabeledContent("Coverage note") {
                        TextField("Battery 1 yr", text: $coverageNote).multilineTextAlignment(.trailing)
                            .focused($focused, equals: .note)
                    }
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: {
                            Text("Delete warranty").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New warranty" : "Edit warranty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(selection: $category)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let w = existing else { return }
        name = w.name; emoji = w.emoji == "🛡️" ? "" : w.emoji; store = w.store
        category = w.category.isEmpty ? Categories.defaultName : w.category
        purchaseDate = w.purchaseDate; coverageNote = w.coverageNote
        switch w.durationMonths {
        case 12: length = .y1
        case 24: length = .y2
        case 36: length = .y3
        default: length = .custom; customMonths = w.durationMonths
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let w = existing {
            w.name = trimmed; w.emoji = shownEmoji; w.store = store; w.category = category
            w.purchaseDate = purchaseDate; w.durationMonths = months; w.coverageNote = coverageNote
        } else {
            context.insert(Warranty(name: trimmed, emoji: shownEmoji, store: store, category: category,
                                    purchaseDate: purchaseDate, durationMonths: months,
                                    coverageNote: coverageNote))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let w = existing { context.delete(w); try? context.save() }
        dismiss()
    }
}
