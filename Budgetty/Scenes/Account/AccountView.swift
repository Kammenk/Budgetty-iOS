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
    @AppStorage(SettingsKey.notifications) private var notifications = true
    @AppStorage(SettingsKey.faceID) private var faceID = false
    @AppStorage(SettingsKey.analytics) private var analytics = true
    @AppStorage(SettingsKey.crashReporting) private var crashReporting = true
    @AppStorage(SettingsKey.premium) private var premium = false

    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    // Backup / restore
    @State private var showExporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var showImporter = false
    @State private var pendingImport: BackupFile?
    @State private var importChoice = false
    @State private var backupError: String?

    private var appearance: AppearancePref { AppearancePref(rawValue: appearanceRaw) ?? .system }
    private var dateFormat: DateFormatOption { DateFormatOption(rawValue: dateFormatRaw) ?? .system }

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
        .screenCanvas()
        .navigationTitle("Account")
        .confirmationDialog("Sign out of Budgetty?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { try? auth.signOut() }
        }
        .confirmationDialog("Delete your account? This can't be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { try? await auth.deleteAccount() } }
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
            Toggle(isOn: $notifications) { label("Notifications", "bell.fill", Palette.bad) }
                .tint(Palette.good)
                .padding(.vertical, 8).padding(.horizontal, 16)
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
            Button { showImporter = true } label: {
                row("Import data", "square.and.arrow.down", Color(argb: 0xFF30B0C7)) { chevron }
            }
            .buttonStyle(.plain)
            divider
            NavigationLink { WidgetsView() } label: {
                row("Widgets", "square.grid.2x2.fill", Color(argb: 0xFF5856D6)) { chevron }
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
                row("Accent color", "sun.max.fill", Palette.tint) {
                    Text("Violet").font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
                }
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

    private var privacyCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $faceID) { label("Face ID", "lock.fill", Color(argb: 0xFF30B0C7)) }
                .tint(Palette.good)
                .padding(.vertical, 8).padding(.horizontal, 16)
            divider
            Toggle(isOn: $analytics) { label("Analytics", "chart.bar.fill", Color(argb: 0xFF5AC8FA)) }
                .tint(Palette.good)
                .padding(.vertical, 8).padding(.horizontal, 16)
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
        .navigationTitle("Date format")
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
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}
