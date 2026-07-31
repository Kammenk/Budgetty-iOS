//
//  ExportSheet.swift
//  Budgetty
//
//  The Export options sheet (Android's ExportSheet): pick CSV or PDF and a period, then hand the
//  generated file to the iOS share sheet. Premium-gated at the Account row that presents it.
//

import SwiftUI
import SwiftData

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV", pdf = "PDF"
    var id: String { rawValue }
}

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var recurring: [Recurring]
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.currency) private var currencyCode = "EUR"

    @State private var format: ExportFormat = .csv
    @State private var period: ExportPeriod = .thisMonth
    @State private var shareItem: ShareItem?

    private var isPdf: Bool { format == .pdf }
    private var income: [Recurring] { recurring.filter(\.isIncome) }
    private var interval: DateInterval { period.interval(startDay: monthStartDay, receipts: receipts) }
    private var currencySymbol: String { CurrencyOption.symbol(currencyCode) }
    private var periodLabelText: String {
        period == .allTime ? String(localized: "All time") : ExportBuilder.periodLabel(interval)
    }
    private var data: ExportData {
        let today = DateFormatter(); today.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return ExportBuilder.buildData(
            receipts: receipts, income: income, interval: interval, currencySymbol: currencySymbol,
            periodLabel: periodLabelText,
            generatedLabel: String(localized: "Generated \(today.string(from: .now)) · \(currencySymbol) · \(receiptCount) receipts"),
            totalRowLabel: String(localized: "Total · \(periodLabelText)"))
    }
    private var receiptCount: Int { receipts.filter { interval.contains($0.createdAt) }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                let data = data
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export").font(.title2).fontWeight(.bold)
                        Text("A spreadsheet to work with, or a statement to send.")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                    formatSection
                    periodSection
                    summary(data)
                    Button { export(data) } label: {
                        Text(isPdf ? "Export PDF" : "Export CSV").font(.headline).ctaPill(height: 52)
                    }
                    .disabled(data.isEmpty)
                    .opacity(data.isEmpty ? 0.5 : 1)
                    Text("Created on your phone, then handed to the share sheet.")
                        .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .adaptiveReadableWidth(Dimens.contentMaxWidth)
            }
            .background(Palette.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $shareItem) { ActivityView(url: $0.url) }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("Format")
            GlassSegmentedControl(options: ExportFormat.allCases, selection: $format) {
                LocalizedStringKey($0.rawValue)
            }
            Text(isPdf
                 ? "A one-page statement: totals, a category summary and the transaction table."
                 : "A row per receipt — date, store, category, amount. Opens in Excel, Numbers or Sheets.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("Period")
            Menu {
                Picker("Period", selection: $period) {
                    ForEach(ExportPeriod.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(Palette.secondaryLabel)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(period.label).font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                        Text(periodLabelText).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func summary(_ data: ExportData) -> some View {
        if data.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing to export for this period").font(.subheadline).fontWeight(.bold)
                Text("No receipts in this range. Pick another period, or add a receipt first.")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("\(data.rows.count) receipts · \(data.totalSpent.formatMoney())")
                .font(.subheadline).fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.caption).fontWeight(.semibold).textCase(.uppercase)
            .foregroundStyle(Palette.secondaryLabel).tracking(0.5)
    }

    private func export(_ data: ExportData) {
        guard !data.isEmpty else { return }
        let cleaned = data.periodLabel.replacingOccurrences(
            of: "[^\\p{L}\\p{N} \\-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let name = "Budgetty \(cleaned)".trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + (isPdf ? ".pdf" : ".csv"))
        do {
            if isPdf { try DataExporter.renderPdf(data).write(to: url) }
            else { try ExportBuilder.toCsv(data).data(using: .utf8)?.write(to: url) }
            shareItem = ShareItem(url: url)
        } catch { }
    }
}

/// Identifiable wrapper so a freshly-generated file URL drives a `.sheet(item:)` share.
struct ShareItem: Identifiable { let id = UUID(); let url: URL }

/// The iOS share sheet (UIActivityViewController) for a generated export file.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
