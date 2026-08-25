//
//  BuyingLimitEditorSheet.swift
//  Budgetty
//
//  Create / edit a buying limit. A Liquid Glass adaptation of Android's `BuyingLimitEditorSheet`:
//  emoji + label, a keyword chip input (commit on space / comma / return, removable, Cyrillic-safe),
//  a live match preview (matches / no-match / amber "catching a lot" + suggestion), a Weekly | Monthly
//  segmented control, and a count stepper (floor 1). The match preview and normalization mirror the
//  Android logic exactly (see `BuyingLimitPreview`).
//

import SwiftUI
import SwiftData

struct BuyingLimitEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new limit; non-nil = edit.
    var existing: BuyingLimit?
    /// Saved line items, for the live match preview (counts quantity, not rows).
    let items: [CountableItem]
    let monthStartDay: Int

    @State private var emoji = ""
    @State private var label = ""
    @State private var keywords: [String] = []
    @State private var keywordField = ""
    @State private var timeframe: BuyingLimitTimeframe = .monthly
    @State private var count = 1
    @State private var showEmoji = false
    @State private var loaded = false

    /// Provisional keywords include the still-uncommitted field so the preview updates as the user types.
    private var previewKeywords: [String] {
        keywordField.trimmingCharacters(in: .whitespaces).isEmpty ? keywords : keywords + [keywordField]
    }
    private var preview: BuyingLimitPreview {
        BuyingLimitPreview.compute(items: items, rawKeywords: previewKeywords, timeframe: timeframe,
                                   label: label, startDay: monthStartDay)
    }
    private var canSave: Bool {
        !keywords.isEmpty || !keywordField.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    emojiAndLabel
                    keywordsSection
                    matchPreview
                    timeframeSection
                    countSection
                    if existing != nil {
                        Button("Delete limit", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle(existing == nil ? "New limit" : "Edit limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showEmoji) { EmojiPickerSheet(selection: $emoji) }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: - Emoji + label

    private var emojiAndLabel: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button { showEmoji = true } label: { emojiChip }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Label · optional")
                TextField("e.g. Fizzy drinks", text: $label)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .glassControl(cornerRadius: 12)
            }
        }
    }

    private var emojiChip: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // Taller than the label field beside it and bottom-aligned with it (see the HStack above): the
        // chip's top rises up beside the LABEL while its bottom edge lines up flush with the field's bottom.
        return shape
            .fill(emoji.isEmpty ? Color.clear : Palette.tintSoft)
            .frame(width: 60, height: 60)
            .overlay {
                if emoji.isEmpty {
                    shape.strokeBorder(Palette.separatorStrong, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .overlay(Image(systemName: "tag").font(.system(size: 22))
                            .foregroundStyle(Palette.secondaryLabel))
                } else {
                    Text(emoji).font(.system(size: 28))
                }
            }
            .accessibilityLabel("Choose an emoji")
    }

    // MARK: - Keywords

    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Keywords")
            VStack(alignment: .leading, spacing: 8) {
                if !keywords.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(keywords, id: \.self) { kw in keywordChip(kw) }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondaryLabel)
                    TextField("Add keyword", text: $keywordField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onChange(of: keywordField) { _, newValue in
                            let (updated, remainder) = Self.commitKeywordInput(keywords, newValue)
                            keywords = updated
                            keywordField = remainder
                        }
                        .onSubmit(commitTrailing)
                }
            }
            .padding(12)
            .glassControl(cornerRadius: 12)
            Text("Any of these counts toward the same limit.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
    }

    private func keywordChip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.subheadline).fontWeight(.medium).foregroundStyle(Palette.tint)
            Button { keywords.removeAll { $0 == text } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
        .background(Palette.tintSoft, in: Capsule())
    }

    private func commitTrailing() {
        let (updated, _) = Self.commitKeywordInput(keywords, keywordField + " ")
        keywords = updated
        keywordField = ""
    }

    // MARK: - Match preview

    @ViewBuilder
    private var matchPreview: some View {
        switch preview.state {
        case .hidden:
            EmptyView()
        case .noMatch:
            VStack(alignment: .leading, spacing: 6) {
                previewHeader
                Text("No matching items yet").font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Palette.label)
                Text("Nothing on your saved receipts matches. We'll start counting from your next one.")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassControl(cornerRadius: 12)
        case .match where preview.tooBroad:
            tooBroadCard
        case .match:
            VStack(alignment: .leading, spacing: 4) {
                previewHeader
                matchNames
                matchCount
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassControl(cornerRadius: 12)
        }
    }

    private var previewHeader: some View {
        Label("Currently matches", systemImage: "magnifyingglass")
            .font(.caption2).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
            .textCase(.uppercase).tracking(0.6)
    }

    private var matchNames: some View {
        let names = preview.names.joined(separator: " · ")
        return (Text(verbatim: names)
                + (preview.moreCount > 0
                   ? Text(verbatim: "  ") + Text("+\(preview.moreCount) more")
                   : Text(verbatim: "")))
            .font(.subheadline).foregroundStyle(Palette.label)
    }

    private var matchCount: some View {
        let period = String(localized: timeframe == .weekly ? "this week" : "this month")
        return Text("\(preview.windowQuantity) bought \(period)")
            .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
    }

    /// Amber "catching a lot" warning — a warning only; it never blocks Save.
    private var tooBroadCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Catching a lot", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).fontWeight(.bold).foregroundStyle(Palette.warn)
                .textCase(.uppercase)
            matchNames
            matchCount
            if let suggestion = preview.suggestion {
                Button {
                    if !keywords.contains(suggestion) { keywords.append(suggestion) }
                    keywordField = ""
                } label: {
                    Text("Use \u{201C}\(suggestion)\u{201D} instead")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Palette.card, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Timeframe + count

    private var timeframeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Timeframe")
            GlassSegmentedControl(options: BuyingLimitTimeframe.allCases, selection: $timeframe) {
                $0 == .weekly ? "Weekly" : "Monthly"
            }
        }
    }

    private var countSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(timeframe == .weekly ? "Limit per week" : "Limit per month")
            HStack(spacing: 0) {
                stepperButton("minus", enabled: count > 1) { if count > 1 { count -= 1 } }
                Text("\(count)").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
                    .frame(maxWidth: .infinity)
                stepperButton("plus", enabled: true) { count += 1 }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .glassControl(cornerRadius: 12)
        }
    }

    private func stepperButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? Palette.tint : Palette.tertiaryLabel)
                .frame(width: 56, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Decrease limit" : "Increase limit")
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.bold)
            .textCase(.uppercase).tracking(0.6)
            .foregroundStyle(Palette.secondaryLabel)
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let e = existing else { return }
        emoji = e.emoji; label = e.label; keywords = e.keywords
        timeframe = e.timeframe; count = e.count
    }

    private func save() {
        let (finalKeywords, _) = Self.commitKeywordInput(keywords, keywordField + " ")
        let normalized = BuyingLimit.normalizedKeywords(finalKeywords)
        guard !normalized.isEmpty else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if let e = existing {
            e.emoji = trimmedEmoji; e.label = trimmedLabel; e.keywords = normalized
            e.timeframe = timeframe; e.count = max(count, 1)   // createdAt preserved
        } else {
            context.insert(BuyingLimit(emoji: trimmedEmoji, label: trimmedLabel, keywords: normalized,
                                       timeframe: timeframe, count: max(count, 1)))
            // §0 analytics: a brand-new limit from the editor. Suggestion-sourced creation (§4.4) will
            // pass .suggestion when that flow lands; the editor is always .manual.
            Analytics.logLimitCreated(.manual)
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let e = existing { context.delete(e); try? context.save() }
        dismiss()
    }

    /// Commits any complete tokens in `raw` (split on space / comma / return) into `current` as
    /// normalized, de-duplicated keyword chips; returns the updated list and the trailing partial token
    /// still being typed. Pure — mirrors Android's `commitKeywordInput`.
    static func commitKeywordInput(_ current: [String], _ raw: String) -> (keywords: [String], remainder: String) {
        guard raw.contains(where: { $0 == " " || $0 == "," || $0 == "\n" }) else { return (current, raw) }
        let parts = raw.split(omittingEmptySubsequences: false) { $0 == " " || $0 == "," || $0 == "\n" }
            .map(String.init)
        var result = current
        for token in parts.dropLast() {
            let key = BuyingLimit.normalizeKeyword(token)
            if !key.isEmpty && !result.contains(key) { result.append(key) }
        }
        return (result, parts.last ?? "")
    }
}
