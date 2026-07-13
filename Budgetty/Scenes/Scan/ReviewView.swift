//
//  ReviewView.swift
//  Budgetty
//
//  The editable "Review Receipt" screen from the mockup: store + date, per-item cards (name,
//  category, price, delete), add-item, and a pinned footer with subtotal/discount and a Save button.
//

import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Bindable var draft: ReceiptDraft
    var onCancel: () -> Void
    var onSave: () -> Void

    @State private var categoryTarget: DraftItem?
    @State private var oldCategory = ""
    @State private var memoryCtx: MemoryCtx?

    private struct MemoryCtx: Identifiable {
        let id = UUID(); let item: DraftItem; let old: String; let new: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    storeAndDate
                    ForEach(draft.items) { item in
                        ItemCard(item: item, onDelete: { draft.remove(item) },
                                 onEditCategory: { oldCategory = item.category; categoryTarget = item })
                    }
                    addItemButton
                }
                .padding(16)
                .adaptiveReadableWidth()
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel).tint(Palette.bad)
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .sheet(item: $categoryTarget) { target in
                CategoryPickerSheet(
                    selection: Binding(get: { target.category }, set: { target.category = $0 }),
                    onPicked: { newCat in
                        guard newCat != oldCategory else { return }
                        let captured = MemoryCtx(item: target, old: oldCategory, new: newCat)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { memoryCtx = captured }
                    })
            }
            .sheet(item: $memoryCtx) { ctx in
                CategoryMemorySheet(itemName: ctx.item.name, oldCategory: ctx.old, newCategory: ctx.new) { scope in
                    applyMemory(ctx.item, newCategory: ctx.new, scope: scope)
                }
            }
        }
    }

    /// Remember a category change: upsert a name→category rule and re-categorize matching items
    /// (in this draft and in past receipts).
    private func applyMemory(_ item: DraftItem, newCategory: String, scope: MemoryScope) {
        guard scope == .all else { return }
        let key = CategoryRule.key(item.name)
        for it in draft.items where CategoryRule.key(it.name) == key { it.category = newCategory }

        if let rule = try? context.fetch(FetchDescriptor<CategoryRule>(
            predicate: #Predicate { $0.name == key })).first {
            rule.category = newCategory
        } else {
            context.insert(CategoryRule(name: key, category: newCategory))
        }
        if let past = try? context.fetch(FetchDescriptor<LineItem>()) {
            for li in past where CategoryRule.key(li.name) == key { li.category = newCategory }
        }
        try? context.save()
    }

    // MARK: - Store + date

    private var storeAndDate: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Store")
                TextField("Store", text: $draft.store)
                    .font(.subheadline).textInputAutocapitalization(.words)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inputField(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Date")
                DatePicker("", selection: $draft.date, displayedComponents: .date)
                    .labelsHidden()
            }
            .padding(12)
            .inputField(cornerRadius: 12)
        }
    }

    // MARK: - Add item

    private var addItemButton: some View {
        Button { draft.addItem() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add item").fontWeight(.medium)
            }
            .foregroundStyle(Palette.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(Palette.separator)
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            summaryRow("Subtotal", draft.subtotal.formatMoney(), color: Palette.label)
            if draft.discount > 0 {
                summaryRow("Discount", "−\(draft.discount.formatMoney())", color: Palette.good)
            }
            Button(action: onSave) {
                Text("Save receipt · \(draft.total.formatMoney())")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(.bar)
    }

    private func summaryRow(_ title: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Text(value).foregroundStyle(color)
        }
        .font(.subheadline)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
            .foregroundStyle(Palette.secondaryLabel).tracking(0.4)
    }
}

/// One editable line-item card.
private struct ItemCard: View {
    @Bindable var item: DraftItem
    var onDelete: () -> Void
    var onEditCategory: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    label("Product")
                    TextField("Item name", text: $item.name).font(.subheadline)
                }
                Spacer(minLength: 8)
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 15))
                        .foregroundStyle(Palette.bad)
                        .frame(width: 32, height: 32)
                        .background(Palette.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(spacing: 8) {
                Button(action: onEditCategory) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            label("Category")
                            HStack(spacing: 4) {
                                Text(Categories.emoji(for: item.category))
                                Text(item.category).font(.subheadline).foregroundStyle(Palette.label)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                    .padding(10)
                    .inputField(cornerRadius: 10)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    label("Price")
                    TextField("0", value: $item.price, format: .number)
                        .font(.subheadline).keyboardType(.decimalPad)
                }
                .padding(10)
                .frame(width: 92)
                .inputField(cornerRadius: 10)
            }
        }
        .padding(14)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
            .foregroundStyle(Palette.secondaryLabel).tracking(0.4)
    }
}
