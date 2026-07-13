//
//  TransactionsSheets.swift
//  Budgetty
//
//  Drill-down sheets: all line items in one category, and all receipts from one store, for a period.
//  Presented from the Insights "Top categories" / "Top stores" rows.
//

import SwiftUI

/// Line items belonging to `category` (rolled up to its group) for the given items.
struct CategoryTransactionsSheet: View {
    let category: String
    let items: [LineItem]
    @Environment(\.dismiss) private var dismiss

    private var matching: [LineItem] {
        items.filter {
            $0.category.caseInsensitiveCompare(category) == .orderedSame
            || Categories.groupOf($0.category).caseInsensitiveCompare(category) == .orderedSame
        }
        .sorted { $0.lineTotal > $1.lineTotal }
    }
    private var total: Decimal { matching.reduce(.zero) { $0 + $1.lineTotal } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header(tile: CategoryTile(category: category, size: 52), title: category,
                           subtitle: "\(matching.count) item\(matching.count == 1 ? "" : "s")", total: total)
                    card {
                        ForEach(Array(matching.enumerated()), id: \.element.persistentModelID) { idx, item in
                            HStack(spacing: 12) {
                                CategoryTile(category: item.category)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline).foregroundStyle(Palette.label)
                                    Text(item.receipt?.store ?? "").font(.caption).foregroundStyle(Palette.secondaryLabel)
                                }
                                Spacer(minLength: 8)
                                Text(item.lineTotal.formatMoney()).font(.subheadline).fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            if idx < matching.count - 1 { Divider().padding(.leading, 58) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .background(Palette.groupedBackground)
            .navigationTitle(category).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Receipts from one store for the given receipts list.
struct StoreTransactionsSheet: View {
    let store: String
    let receipts: [Receipt]
    @Environment(\.dismiss) private var dismiss

    private var matching: [Receipt] {
        receipts.filter { $0.store.caseInsensitiveCompare(store) == .orderedSame }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var total: Decimal { matching.reduce(.zero) { $0 + $1.paidTotal } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header(tile: StoreAvatar(store: store, size: 52), title: store,
                           subtitle: "\(matching.count) receipt\(matching.count == 1 ? "" : "s")", total: total)
                    card {
                        ForEach(Array(matching.enumerated()), id: \.element.persistentModelID) { idx, r in
                            NavigationLink { ReceiptDetailView(receipt: r) } label: { ReceiptRowView(receipt: r) }
                                .buttonStyle(.plain)
                            if idx < matching.count - 1 { Divider().padding(.leading, 64) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .background(Palette.groupedBackground)
            .navigationTitle(store).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Shared bits

private func header<Tile: View>(tile: Tile, title: String, subtitle: String, total: Decimal) -> some View {
    HStack(spacing: 14) {
        tile
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3).fontWeight(.bold)
            Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        Spacer(minLength: 8)
        Text(total.formatMoney()).font(.title3).fontWeight(.bold)
    }
    .padding(16)
    .contentCard(cornerRadius: 14)
}

@ViewBuilder
private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
        .contentCard(cornerRadius: 14)
}
