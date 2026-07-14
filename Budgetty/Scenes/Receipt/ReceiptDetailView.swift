//
//  ReceiptDetailView.swift
//  Budgetty
//
//  A saved receipt: store header, itemized list, totals (subtotal / discount / incl. VAT / extra /
//  total), and Edit (reuses the review editor) + Delete actions. Pushed from Home & History rows.
//

import SwiftUI
import SwiftData

struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let receipt: Receipt

    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue
    @State private var editDraft: ReceiptDraft?
    @State private var confirmDelete = false

    private var items: [LineItem] { receipt.items.sorted { $0.name < $1.name } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                storeHeader
                itemsSection
                totalsSection
                actions
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 40)
            .adaptiveReadableWidth()
        }
        .background(Palette.groupedBackground)
        .navigationTitle(receipt.store)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editDraft = ReceiptDraft(editing: receipt) }
            }
        }
        .sheet(item: $editDraft) { draft in
            ReviewView(draft: draft, onCancel: { editDraft = nil },
                       onSave: { draft.persist(into: context); editDraft = nil })
        }
        .confirmationDialog("Delete this receipt?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Receipt", role: .destructive) {
                context.delete(receipt)
                try? context.save()
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var storeHeader: some View {
        HStack(spacing: 14) {
            StoreAvatar(store: receipt.store, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.store).font(.title3).fontWeight(.bold)
                Text("\(longDate(receipt.date)) · \(receipt.items.count) item\(receipt.items.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(receipt.paidTotal.formatMoney()).font(.title3).fontWeight(.bold)
                if receipt.discount > 0 {
                    Text("−\(receipt.discount.formatMoney()) saved")
                        .font(.caption).foregroundStyle(Palette.good)
                }
            }
        }
        .padding(16)
        .contentCard(cornerRadius: 14)
    }

    // MARK: - Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Items")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { idx, item in
                    itemRow(item)
                    if idx < items.count - 1 { Divider().padding(.leading, 64) }
                }
            }
            .contentCard(cornerRadius: 14)
        }
    }

    private func itemRow(_ item: LineItem) -> some View {
        HStack(spacing: 12) {
            CategoryTile(category: item.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body).foregroundStyle(Palette.label)
                Text(subtitle(item)).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text(item.lineTotal.formatMoney()).font(.body).fontWeight(.semibold)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func subtitle(_ item: LineItem) -> String {
        if item.quantity > 1 {
            return "\(item.category) · qty \(item.quantity) × \(item.price.formatMoney())"
        }
        return "\(item.category) · qty \(item.quantity)"
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Totals")
            VStack(spacing: 0) {
                totalRow("Subtotal", receipt.itemsSum.formatMoney(), color: Palette.label)
                if receipt.discount > 0 {
                    Divider().padding(.leading, 16)
                    totalRow("Discount", "−\(receipt.discount.formatMoney())", color: Palette.good, bold: true)
                }
                if receipt.tax > 0 {
                    Divider().padding(.leading, 16)
                    totalRow("incl. VAT", receipt.tax.formatMoney(), color: Palette.secondaryLabel)
                }
                if receipt.extraCharges > 0 {
                    Divider().padding(.leading, 16)
                    totalRow("Fees & charges", receipt.extraCharges.formatMoney(), color: Palette.label)
                }
                Divider().padding(.leading, 16)
                HStack {
                    Text("Total").font(.body).fontWeight(.bold)
                    Spacer()
                    Text(receipt.paidTotal.formatMoney()).font(.title3).fontWeight(.bold)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .contentCard(cornerRadius: 14)
        }
    }

    private func totalRow(_ title: String, _ value: String, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(.body).foregroundStyle(Palette.label)
            Spacer()
            Text(value).font(.body).fontWeight(bold ? .semibold : .regular).foregroundStyle(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            Button { editDraft = ReceiptDraft(editing: receipt) } label: {
                Text("Edit Receipt").frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete Receipt").frame(maxWidth: .infinity).padding(.vertical, 14)
            }
        }
        .contentCard(cornerRadius: 14)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption).textCase(.uppercase).tracking(0.6)
            .foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
    }

    private func longDate(_ date: Date) -> String {
        (DateFormatOption(rawValue: dateFormatRaw) ?? .system).long(date)
    }
}
