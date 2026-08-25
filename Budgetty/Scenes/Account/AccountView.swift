//
//  AccountView.swift
//  Budgetty
//
//  Account / Settings — Liquid Glass v2 (iOS Account.dc.html): glass section cards over the
//  ambient canvas, colored icon tiles, inline toggles. Appearance and Currency are functional
//  and persisted; toggles persist; Subscription → Paywall.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AccountView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearancePref.system.rawValue
    @AppStorage(SettingsKey.currency) private var currency = "EUR"
    @AppStorage(SettingsKey.language) private var language = "system"
    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.faceID) private var faceID = false
    @AppStorage(SettingsKey.appLockEnabled) private var appLockEnabled = false
    @AppStorage(SettingsKey.autoLockMinutes) private var autoLockMinutes = 0
    @AppStorage(SettingsKey.recapEnabled) private var recapEnabled = true
    @AppStorage(SettingsKey.recapFrequency) private var recapFrequencyRaw = RecapFrequency.monthly.rawValue
    @AppStorage(SettingsKey.crashReporting) private var crashReporting = true
    @AppStorage(SettingsKey.premium) private var premium = false
    private let theme = AppTheme.shared

    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    // Backup / restore
    @State private var showExporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var showImporter = false
    @State private var pendingImport: BackupFile?
    @State private var importChoice = false
    @State private var backupError: String?
    @State private var showExportSheet = false
    @State private var showSetPin = false

    private var appearance: AppearancePref { AppearancePref(rawValue: appearanceRaw) ?? .system }
    private var dateFormat: DateFormatOption { DateFormatOption(rawValue: dateFormatRaw) ?? .system }
    /// Compact value on the "Month starts on" row: the plain day, or "1 (calendar month)" for the default.
    private var monthStartLabel: String {
        monthStartDay == 1 ? String(localized: "1 (calendar month)") : "\(monthStartDay)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileCard
                    .padding(.bottom, 32)

                sectionHeader("Account")
                accountCard
                    .padding(.bottom, 24)

                sectionHeader("Preferences")
                preferencesCard
                    .padding(.bottom, 24)

                sectionHeader("Recap")
                recapCard
                recapFootnote
                    .padding(.bottom, 24)

                sectionHeader("Privacy & Security")
                privacyCard
                    .padding(.bottom, 24)

                NavigationLink { SupportAboutView() } label: {
                    row("Help & Support", "questionmark.circle.fill", Color(argb: 0xFF8E8E93)) { chevron }
                }
                .buttonStyle(.plain)
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 24)

                Button { confirmSignOut = true } label: {
                    Text("Sign Out")
                        .foregroundStyle(Palette.bad)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 12)

                Button("Delete Account") { confirmDelete = true }
                    .font(.subheadline)
                    .foregroundStyle(Palette.bad)
                    .padding(.vertical, 8)

                Text("Budgetty \(Self.appVersion) · Made with ❤️")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryLabel)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
            .adaptiveReadableWidth()
        }
        .underFloatingDock(reportingScroll: false)
        .screenCanvas()
        .navigationTitle("Account")
        .sheet(isPresented: $showExportSheet) { ExportSheet() }
        .sheet(isPresented: $showSetPin) { SetPinView { appLockEnabled = true } }
        .confirmationDialog("Sign out of Budgetty?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { try? auth.signOut() }
        }
        .confirmationDialog("Delete your account? This can't be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { try? await auth.deleteAccount() } }
        } message: {
            Text("This permanently deletes your account and its data. Deleting your account doesn't cancel a Premium subscription — you can manage or cancel it in your Apple subscription settings.")
        }
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                      defaultFilename: Self.backupFilename()) { result in
            if case .failure(let error) = result { backupError = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog(importDialogTitle, isPresented: $importChoice, titleVisibility: .visible) {
            Button("Merge with current data") { applyImport(.merge) }
            Button("Replace all data", role: .destructive) { applyImport(.replace) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Merge keeps your current data and adds the backup. Replace deletes everything first.")
        }
        .alert("Backup", isPresented: Binding(get: { backupError != nil },
                                              set: { if !$0 { backupError = nil } })) {
            Button("OK", role: .cancel) { backupError = nil }
        } message: { Text(backupError ?? "") }
    }

    // MARK: - Cards

    private var profileCard: some View {
        HStack(spacing: 14) {
            AvatarView(initials: auth.initials, size: 56, fontSize: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(auth.email.isEmpty ? "Your account" : auth.email)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text("Signed in").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .contentCard(cornerRadius: 16)
    }

    private var accountCard: some View {
        VStack(spacing: 0) {
            NavigationLink { PaywallView() } label: {
                row("Subscription", "star.fill", Color(argb: 0xFFFFD700), icon: Color(argb: 0xFF7A6000)) {
                    Text(premium ? "Premium" : "Free")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Palette.tint, in: Capsule())
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { CurrencyPickerView(selection: $currency) } label: {
                row("Currency", "eurosign", Palette.good) {
                    value("\(currency) (\(CurrencyOption.symbol(currency)))")
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            Button { exportBackup() } label: {
                row("Export data", "square.and.arrow.up", Color(argb: 0xFF007AFF)) { chevron }
            }
            .buttonStyle(.plain)
            divider
            // Human-readable CSV / PDF export (Premium), distinct from the JSON backup above.
            if premium {
                Button { showExportSheet = true } label: {
                    row("Export CSV or PDF", "tablecells", Color(argb: 0xFF34C759)) { chevron }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { PaywallView() } label: {
                    row("Export CSV or PDF", "tablecells", Color(argb: 0xFF34C759)) {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryLabel)
                        chevron
                    }
                }
                .buttonStyle(.plain)
            }
            divider
            Button { showImporter = true } label: {
                row("Import data", "square.and.arrow.down", Color(argb: 0xFF30B0C7)) { chevron }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { WidgetsView() } label: {
                row("Widgets", "square.grid.2x2.fill", Color(argb: 0xFF5856D6)) { chevron }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { BuyingLimitsView() } label: {
                row("Buying limits", "chart.bar.xaxis", Color(argb: 0xFF30B0C7)) { chevron }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { ManageCategoriesView() } label: {
                row("Manage categories", "square.grid.3x3.fill", Color(argb: 0xFFFF9F0A)) { chevron }
            }
            .buttonStyle(.plain)
        }
        .contentCard(cornerRadius: 14)
    }

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            NavigationLink { appearancePicker } label: {
                row("Appearance", "moon.fill", Color(argb: 0xFF636366)) {
                    value(appearance.label)
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            if premium {
                NavigationLink { accentPicker } label: {
                    row("Accent color", "sun.max.fill", Palette.tint) {
                        value(theme.accent.label)
                        chevron
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { PaywallView() } label: {
                    row("Accent color", "sun.max.fill", Palette.tint) {
                        Text("Premium")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Palette.tint, in: Capsule())
                        chevron
                    }
                }
                .buttonStyle(.plain)
            }
            divider
            NavigationLink { dateFormatPicker } label: {
                row("Date format", "calendar", Color(argb: 0xFFFF9500)) {
                    value(dateFormat.settingLabel)
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { monthStartPicker } label: {
                row("Month starts on", "calendar.badge.clock", Color(argb: 0xFFAF52DE)) {
                    value(monthStartLabel)
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { LanguagePickerView(selection: $language) } label: {
                row("Language", "globe", Color(argb: 0xFF0A84FF)) {
                    value(LanguageOption.name(language))
                    chevron
                }
            }
            .buttonStyle(.plain)
        }
        .contentCard(cornerRadius: 14)
    }

    /// The "Recap" group: a master switch (default on) turns the end-of-period recap on/off; when on it
    /// reveals a Weekly | Monthly | Both selector and a hint naming when the next one lands, with an
    /// honesty footnote below the card. Modelled on the app-lock group's on/reveals-more shape. Turning
    /// it off keeps the stored cadence, so switching back on doesn't re-ask. Free. Android parity:
    /// `RecapSectionRows`.
    private var recapCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $recapEnabled) {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "calendar.badge.checkmark", background: Color(argb: 0xFFAF52DE))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("End-of-period recap").foregroundStyle(Palette.label)
                        Text(recapEnabled ? "A summary when the period closes"
                                          : "Get a summary when a month or week closes")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
            }
            .tint(Palette.good)
            .padding(.vertical, 8).padding(.horizontal, 16)
            if recapEnabled {
                divider
                VStack(alignment: .leading, spacing: 12) {
                    GlassSegmentedControl(options: RecapFrequency.allCases,
                                          selection: recapFrequencyBinding) { recapTitle($0) }
                    Text(recapHint(RecapFrequency(rawValue: recapFrequencyRaw) ?? .monthly))
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .contentCard(cornerRadius: 14)
    }

    private var recapFootnote: some View {
        Text(recapEnabled
             ? "Not a notification. It appears the next time you open Budgetty after the period ends, once per period, and closes to Home."
             : "Turn this on to get a short summary when a month or week closes. You can still open the last one from Insights.")
            .font(.caption).foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 8)
    }

    private var recapFrequencyBinding: Binding<RecapFrequency> {
        Binding(get: { RecapFrequency(rawValue: recapFrequencyRaw) ?? .monthly },
                set: { recapFrequencyRaw = $0.rawValue })
    }

    private func recapTitle(_ frequency: RecapFrequency) -> LocalizedStringKey {
        switch frequency {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .both: "Both"
        }
    }

    /// The hint line under the cadence selector, naming when the next recap lands (Android's `recapHint`).
    private func recapHint(_ frequency: RecapFrequency) -> LocalizedStringKey {
        let cal = Calendar.current
        let weekday = cal.weekdaySymbols[(cal.firstWeekday - 1) % 7]
        let nextStart = PayCycle.month(.now, startDay: monthStartDay, offset: 1).start
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        let nextMonthly = f.string(from: nextStart)
        switch frequency {
        case .weekly:
            return "Every \(weekday), for the week just finished. No monthly report card."
        case .monthly:
            return "Next one on \(nextMonthly) — monthly follows your pay-cycle start day."
        case .both:
            return "Every \(weekday), and again on \(nextMonthly) for the month. The weekly one is a short momentum check."
        }
    }

    /// Security group: the app-lock PIN gate (with biometrics as an optional shortcut and the
    /// auto-lock delay), then the crash-reporting opt-out. Turning App lock on sets a PIN first; the
    /// PIN hash lives in the Keychain (see `PinLock`), while the on/off + delay + biometric flags are
    /// AppStorage. This absorbs the old Face-ID-only lock — biometrics reuse the same `faceID` flag.
    private var privacyCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $appLockEnabled) { label("App lock", "lock.fill", Color(argb: 0xFF30B0C7)) }
                .tint(Palette.good)
                .padding(.vertical, 8).padding(.horizontal, 16)
                .onChange(of: appLockEnabled) { _, on in
                    if on && !PinLock.hasPin { showSetPin = true }   // set a PIN before the lock is real
                    if !on { PinLock.clear() }
                }
                .onChange(of: showSetPin) { _, showing in
                    // Cancelled the set-PIN sheet with no PIN saved → don't leave the lock half-on.
                    if !showing && appLockEnabled && !PinLock.hasPin { appLockEnabled = false }
                }
            if appLockEnabled {
                divider
                Button { showSetPin = true } label: {
                    row("Change PIN", "key.fill", Color(argb: 0xFF5856D6)) { chevron }
                }
                .buttonStyle(.plain)
                if BiometricAuth.isAvailable {
                    divider
                    Toggle(isOn: $faceID) { label("Use Face ID / Touch ID", "faceid", Color(argb: 0xFF30B0C7)) }
                        .tint(Palette.good)
                        .padding(.vertical, 8).padding(.horizontal, 16)
                }
                divider
                Menu {
                    Picker("Auto-lock", selection: $autoLockMinutes) {
                        Text("Immediately").tag(0)
                        Text("After 1 minute").tag(1)
                        Text("After 5 minutes").tag(5)
                    }
                } label: {
                    row("Auto-lock", "clock.fill", Color(argb: 0xFFFF9500)) {
                        value(autoLockLabel); chevron
                    }
                }
            }
            divider
            // Default-on with a real opt-out (Android parity). The stored preference is the source of
            // truth — push every change straight to the SDK so it can't drift from the toggle.
            Toggle(isOn: $crashReporting) {
                label("Crash reporting", "exclamationmark.triangle.fill", Color(argb: 0xFFFF9500))
            }
            .tint(Palette.good)
            .padding(.vertical, 8).padding(.horizontal, 16)
            .onChange(of: crashReporting) { _, enabled in CrashReporting.setEnabled(enabled) }
        }
        .contentCard(cornerRadius: 14)
    }

    private var autoLockLabel: String {
        switch autoLockMinutes {
        case 0: String(localized: "Immediately")
        case 1: String(localized: "After 1 minute")
        default: String(localized: "After 5 minutes")
        }
    }

    // MARK: - Backup / restore

    private func exportBackup() {
        do {
            exportDoc = BackupDocument(data: try BackupService.export(from: context))
            showExporter = true
        } catch {
            backupError = "Couldn't prepare the export."
        }
    }

    private var importDialogTitle: String {
        guard let f = pendingImport else { return "Import backup?" }
        return "Import \(f.receipts.count) receipts and \(f.itemCount) items?"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try BackupService.decode(try Data(contentsOf: url))
                importChoice = true
            } catch {
                backupError = (error as? LocalizedError)?.errorDescription
                    ?? "That file isn't a valid Budgetty backup."
            }
        case .failure(let error):
            backupError = error.localizedDescription
        }
    }

    private func applyImport(_ mode: BackupService.ImportMode) {
        guard let file = pendingImport else { return }
        do { try BackupService.restore(file, into: context, mode: mode) }
        catch { backupError = error.localizedDescription }
        pendingImport = nil
    }

    private static func backupFilename() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "Budgetty-backup-\(f.string(from: .now))"
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Row building blocks

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle().fill(Palette.separator).frame(height: 0.5)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.label.opacity(0.3))
    }

    private func value(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
    }

    private func label(_ title: LocalizedStringKey, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, background: tint)
            Text(title).foregroundStyle(Palette.label)
        }
    }

    private func row<Trailing: View>(_ title: LocalizedStringKey, _ symbol: String, _ tint: Color,
                                     icon: Color = .white,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, background: tint, foreground: icon)
            Text(title).foregroundStyle(Palette.label)
            Spacer()
            HStack(spacing: 12) { trailing() }
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Sub-screens

    private var appearancePicker: some View {
        List {
            ForEach(AppearancePref.allCases) { pref in
                Button {
                    appearanceRaw = pref.rawValue
                } label: {
                    HStack {
                        Text(pref.label).foregroundStyle(Palette.label)
                        Spacer()
                        if pref == appearance {
                            Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .underFloatingDock(reportingScroll: false)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dateFormatPicker: some View {
        List {
            Section {
                ForEach(DateFormatOption.allCases) { option in
                    Button {
                        dateFormatRaw = option.rawValue
                    } label: {
                        HStack {
                            Text(option.pickerLabel).foregroundStyle(Palette.label)
                            Spacer()
                            if option == dateFormat {
                                Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("How dates appear on receipts and lists.")
            }
        }
        .underFloatingDock(reportingScroll: false)
        .navigationTitle("Date format")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Month starts on" — the pay day the financial month begins (1–31; 1 = calendar month). Applies
    /// live: every screen that shows a monthly figure reads `@AppStorage(SettingsKey.monthStartDay)`.
    private var monthStartPicker: some View {
        List {
            Section {
                ForEach(1...31, id: \.self) { day in
                    Button {
                        monthStartDay = day
                    } label: {
                        HStack {
                            Text(day == 1 ? String(localized: "1 (calendar month)") : "\(day)")
                                .foregroundStyle(Palette.label)
                            Spacer()
                            if day == monthStartDay {
                                Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("The day your financial month begins — set it to your pay day. Shifts “this month” totals, the monthly budget and the Insights month view. Weekly, quarterly and half-year stay calendar-aligned.")
            }
        }
        .underFloatingDock(reportingScroll: false)
        .navigationTitle("Month starts on")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Premium accent picker. Only reachable while `premium` — the free path sends you to the
    /// paywall instead — and the choice applies live, since every tinted view observes `AppTheme`.
    private var accentPicker: some View {
        List {
            Section {
                ForEach(AccentOption.allCases) { option in
                    Button {
                        theme.accent = option
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(option.color).frame(width: 22, height: 22)
                            Text(option.label).foregroundStyle(Palette.label)
                            Spacer()
                            if option == theme.accent {
                                Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("Tints buttons, highlights and the spending card.")
            }
        }
        .underFloatingDock(reportingScroll: false)
        .navigationTitle("Accent color")
        .navigationBarTitleDisplayMode(.inline)
    }

}

/// A rounded colored icon tile with a white SF Symbol — the iOS Settings row glyph.
struct SettingsIcon: View {
    let symbol: String
    let background: Color
    var foreground: Color = .white
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(background)
            .frame(width: 30, height: 30)
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(foreground))
    }
}

struct LanguagePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(LanguageOption.all, id: \.code) { l in
                    Button {
                        selection = l.code
                        LanguageOption.apply(l.code)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(l.name).foregroundStyle(Palette.label)
                            Spacer()
                            if l.code == selection {
                                Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("Your preferred language for Budgetty.")
            }
        }
        .underFloatingDock(reportingScroll: false)
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(CurrencyOption.all, id: \.code) { c in
                Button {
                    selection = c.code
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(c.symbol).frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.code).foregroundStyle(Palette.label)
                            Text(c.name).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.code == selection {
                            Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .underFloatingDock(reportingScroll: false)
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}
