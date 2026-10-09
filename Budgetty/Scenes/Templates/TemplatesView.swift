//
//  TemplatesView.swift
//  Budgetty
//
//  Account → Templates (mockup 5d/5e): the manage list + the create/edit form. Templates are saved
//  regulars logged in one tap from the Add sheet; they never post by themselves. FREE, no cap.
//  Android parity: `TemplatesScreen` + `TemplatesViewModel`.
//

import SwiftUI
import SwiftData

/// The emoji a template shows — its own, or its category's as a fallback.
func templateEmoji(_ t: Template) -> String {
    t.emoji.isEmpty ? Categories.emoji(for: t.category.isEmpty ? Categories.defaultName : t.category) : t.emoji
}

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Template.createdAt) private var templates: [Template]

    @State private var editing: Template?
    @State private var showNew = false
    @State private var deleteTarget: Template?

    var body: some View {
        Group {
            if templates.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(templates) { t in row(t) }
                    } footer: {
                        Text("Templates never post by themselves. For that, use a recurring bill.")
                    }
                }
            }
        }
        .navigationTitle("Templates").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { TemplateEditSheet(existing: $0) }
        .sheet(isPresented: $showNew) { TemplateEditSheet(existing: nil) }
    }

    private func row(_ t: Template) -> some View {
        Button { editing = t } label: {
            HStack(spacing: 12) {
                emojiTile(t)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name.isEmpty ? String(localized: "Template") : t.name)
                        .font(.body).foregroundStyle(Palette.label)
                    Text("\(t.askAmount ? String(localized: "Ask amount") : t.amount.formatMoney()) · \(Categories.displayName(t.category.isEmpty ? Categories.defaultName : t.category))")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryLabel)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { context.delete(t); try? context.save() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func emojiTile(_ t: Template) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(argb: Categories.color(for: t.category.isEmpty ? Categories.defaultName : t.category)).opacity(0.9))
            .frame(width: 34, height: 34)
            .overlay(Text(templateEmoji(t)).font(.system(size: 18)))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.fill").font(.system(size: 36)).foregroundStyle(Palette.tint)
                .frame(width: 64, height: 64)
                .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Log your regulars in one tap").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            Text("Save a coffee, a fare or the rent as a template. It fills everything in, and you confirm.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showNew = true } label: { Text("New template").font(.body).fontWeight(.semibold).ctaPill(height: 48) }
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .background(Palette.groupedBackground)
    }
}

/// Create / edit a template (mockup 5d): emoji, name, amount, category, optional store, and the
/// "ask for the amount each time" switch. Delete lives at the bottom when editing.
struct TemplateEditSheet: View {
    let existing: Template?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var emoji = ""
    @State private var name = ""
    @State private var amount: Decimal = 0
    @State private var category = Categories.defaultName
    @State private var store = ""
    @State private var askAmount = false
    @State private var showCategoryPicker = false
    @FocusState private var focused: Field?
    private enum Field { case emoji, name, amount, store }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var shownEmoji: String { emoji.isEmpty ? Categories.emoji(for: category) : emoji }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(argb: Categories.color(for: category)).opacity(0.9))
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
                    LabeledContent("Name") {
                        TextField("Coffee", text: $name).multilineTextAlignment(.trailing)
                            .focused($focused, equals: .name)
                    }
                    LabeledContent("Amount") {
                        AmountField(value: $amount).multilineTextAlignment(.trailing)
                            .focused($focused, equals: .amount)
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
                Section("Optional") {
                    LabeledContent("Store") {
                        TextField("Café Delta", text: $store).multilineTextAlignment(.trailing)
                            .focused($focused, equals: .store)
                    }
                }
                Section {
                    Toggle("Ask for the amount each time", isOn: $askAmount)
                } footer: {
                    Text("For variable regulars like groceries.")
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: {
                            Text("Delete template").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New template" : "Edit template")
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
        guard let t = existing else { return }
        emoji = t.emoji; name = t.name; amount = t.amount
        category = t.category.isEmpty ? Categories.defaultName : t.category
        store = t.store; askAmount = t.askAmount
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let t = existing {
            t.emoji = emoji; t.name = trimmed; t.amount = amount; t.category = category
            t.store = store; t.askAmount = askAmount
        } else {
            context.insert(Template(emoji: emoji, name: trimmed, amount: amount, category: category,
                                    store: store, askAmount: askAmount))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let t = existing { context.delete(t); try? context.save() }
        dismiss()
    }
}
