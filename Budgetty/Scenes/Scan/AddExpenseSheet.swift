//
//  AddExpenseSheet.swift
//  Budgetty
//
//  The "Add Expense" sheet (mockup 5a) — the Scan button's entry point. A scrolling strip of template
//  chips above the Take Photo / Upload File / Add Manually options. Tapping a template pre-fills the
//  manual review; the capture/upload options open the scan flow. Android parity: `AddSheetScreen` +
//  `TemplateStrip`.
//

import SwiftUI
import SwiftData

struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Template.createdAt) private var templates: [Template]

    var onCapture: () -> Void
    var onLibrary: () -> Void
    var onManual: () -> Void
    var onTemplate: (Template) -> Void

    @State private var showNewTemplate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if templates.isEmpty { emptyInvite } else { templateStrip }
                    optionsCard
                }
                .padding(.vertical, 8).padding(.horizontal, 20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Add expense").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showNewTemplate) { TemplateEditSheet(existing: nil) }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Template strip

    private var templateStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEMPLATES").font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(templates) { t in chip(t) }
                    newChip
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
    }

    private func chip(_ t: Template) -> some View {
        Button { onTemplate(t); dismiss() } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 99, style: .continuous)
                    .fill(Color(argb: Categories.color(for: t.category.isEmpty ? Categories.defaultName : t.category)).opacity(0.9))
                    .frame(width: 34, height: 34)
                    .overlay(Text(templateEmoji(t)).font(.system(size: 18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(t.name) · \(t.askAmount ? String(localized: "Ask") : t.amount.formatMoney())")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.label).lineLimit(1)
                    Text(Categories.displayName(t.category.isEmpty ? Categories.defaultName : t.category))
                        .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                }
            }
            .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8)
            .background(Capsule().fill(Palette.glassFill).background(.ultraThinMaterial, in: Capsule()))
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var newChip: some View {
        Button { showNewTemplate = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text("New").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Palette.tint)
            .padding(.horizontal, 16).frame(height: 50)
            .background(Palette.tintSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyInvite: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log your regulars in one tap").font(.body).fontWeight(.semibold).foregroundStyle(Palette.label)
            Text("Save a coffee, a fare or the rent as a template. It fills everything in, and you confirm.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            Button { showNewTemplate = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    Text("New template").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Palette.tint).padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentCard(cornerRadius: 18)
    }

    // MARK: - Options

    private var optionsCard: some View {
        VStack(spacing: 0) {
            optionRow("Take Photo", "Snap the receipt", "camera.fill", Palette.tint) { onCapture(); dismiss() }
            Divider().padding(.leading, 62)
            optionRow("Upload File", "A photo from your library", "square.and.arrow.up", Color(argb: 0xFF34A3F0)) { onLibrary(); dismiss() }
            Divider().padding(.leading, 62)
            optionRow("Add Manually", "Always free", "pencil", Color(argb: 0xFF8E8E93)) { onManual(); dismiss() }
        }
        .contentCard(cornerRadius: 18)
    }

    private func optionRow(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey,
                           _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body).foregroundStyle(Palette.label)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
