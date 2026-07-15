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
    @State private var noticeDismissed = false
    @State private var showDroppedAlert = false

    // MARK: - Total-reconciliation checks (Android parity)

    /// Mismatch beyond this is real, below it is cent-rounding: 1% of the anchor, floor 15 cents.
    private func tolerance(_ anchor: Decimal) -> Decimal {
        max(anchor * Decimal(string: "0.01")!, Decimal(string: "0.15")!)
    }

    /// Blocking, data-losing direction: the items sum to noticeably LESS than the receipt's printed
    /// subtotal — a line was dropped or under-read, and the shortfall would otherwise vanish silently
    /// into extra charges. Recomputes live, so fixing/adding the line clears it.
    private var droppedShortfall: Decimal? {
        guard let sub = draft.printedSubtotal, sub > 0 else { return nil }
        return (sub - draft.subtotal) > tolerance(sub) ? sub : nil
    }

    /// Soft, opposite direction: the items sum to MORE than the printed subtotal (an over-read or a
    /// price typo). Informational only — saving stays allowed.
    private var overReadAnchor: Decimal? {
        guard let sub = draft.printedSubtotal, sub > 0 else { return nil }
        return (draft.subtotal - sub) > tolerance(sub) ? sub : nil
    }

    /// Route Save through the dropped-line check: confirm on a shortfall, else save straight away.
    private func attemptSave() {
        if droppedShortfall != nil { showDroppedAlert = true } else { onSave() }
    }

    private struct MemoryCtx: Identifiable {
        let id = UUID(); let item: DraftItem; let old: String; let new: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    storeAndDate
                    if let anchor = overReadAnchor, !noticeDismissed {
                        mismatchNotice(anchor)
                    }
                    ForEach(draft.items) { item in
                        ItemCard(item: item, onDelete: { draft.remove(item) },
                                 onEditCategory: { oldCategory = item.category; categoryTarget = item })
                    }
                    addItemButton
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .adaptiveReadableWidth()
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
        .alert("Some lines may be missing", isPresented: $showDroppedAlert) {
            Button("Review items", role: .cancel) {}
            Button("Save anyway") { onSave() }
        } message: {
            if let sub = droppedShortfall {
                Text("The items we read add up to \(draft.subtotal.formatMoney()), but the receipt subtotal is \(sub.formatMoney()). Double-check the items before saving.")
            }
        }
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

    // MARK: - Header

    /// The mockup's sheet header: bold left-aligned title, plain-text Cancel (red) and Save (tint)
    /// actions on the right, hairline underneath.
    private var header: some View {
        HStack(spacing: 16) {
            Text("Review Receipt")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.label)
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.bad)
            Button("Save", action: attemptSave)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.tint)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.separator).frame(height: 0.5)
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
            HStack(spacing: 10) {
                StoreAvatar(store: draft.store, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("Store", color: Palette.tint)
                    TextField("Store", text: $draft.store)
                        .font(.system(size: 14)).textInputAutocapitalization(.words)
                }
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Palette.tertiaryBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                fieldLabel("Date")
                DatePicker("", selection: $draft.date, displayedComponents: .date)
                    .labelsHidden()
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(Palette.tertiaryBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Price-mismatch notice

    /// Soft, dismissible over-read banner (mockup): warn-tinted card at the top of the item list.
    private func mismatchNotice(_ anchor: Decimal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.warn)
                .padding(.top, 1)
            Text("Totals don't quite match — items add up to **\(draft.subtotal.formatMoney())**, the receipt shows **\(anchor.formatMoney())**. You can still save.")
                .font(.system(size: 13)).foregroundStyle(Palette.label)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { noticeDismissed = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.secondaryLabel)
                    .frame(width: 22, height: 22)
                    .background(Palette.fill, in: Circle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Palette.warn.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.warn.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Add item

    private var addItemButton: some View {
        Button { draft.addItem() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text("Add item").font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Palette.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(Palette.separatorStrong)
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
            Button(action: attemptSave) {
                Text("Save receipt · \(draft.total.formatMoney())")
                    .font(.headline)
                    .ctaPill()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Palette.groupedBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.separator).frame(height: 0.5)
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, _ value: String, color: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Text(value).foregroundStyle(color)
        }
        .font(.subheadline)
    }

    private func fieldLabel(_ text: LocalizedStringKey, color: Color = Palette.secondaryLabel) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
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
                    TextField("Item name", text: $item.name).font(.system(size: 15))
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
                                Text(Categories.displayName(item.category)).font(.system(size: 14)).foregroundStyle(Palette.label)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .glassControl(cornerRadius: 10)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    label("Price")
                    TextField("0", value: $item.price, format: .number)
                        .font(.system(size: 14)).keyboardType(.decimalPad)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .frame(width: 100)
                .glassControl(cornerRadius: 10)
            }
        }
        .padding(14)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.secondaryLabel)
    }
}
