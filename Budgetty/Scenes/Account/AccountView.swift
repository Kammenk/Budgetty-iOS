//
//  AccountView.swift
//  Budgetty
//
//  Account / Settings — an iOS inset-grouped list with colored icon tiles (Settings-app style).
//  Appearance and Currency are functional and persisted; the rest are faithful rows wired where it
//  makes sense (toggles persist; Subscription → Paywall).
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
    @AppStorage(SettingsKey.faceID) private var faceID = false
    @AppStorage(SettingsKey.analytics) private var analytics = true
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

    var body: some View {
        List {
            Section { profileRow }

            accountSection
            dataSection
            preferencesSection
            privacySection

            Section {
                NavigationLink { SupportAboutView() } label: {
                    label("Help & Support", "questionmark.circle.fill", Color(argb: 0xFF8E8E93))
                }
            }

            Section {
                Button("Sign Out") { confirmSignOut = true }
                    .frame(maxWidth: .infinity).foregroundStyle(Palette.bad)
            }
            Section {
                Button("Delete Account", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Budgetty 1.0 · Made with ❤️")
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
            }
        }
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

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            NavigationLink { PaywallView() } label: {
                row("Subscription", "star.fill", Color(argb: 0xFFFFD700), icon: Color(argb: 0xFF7A6000)) {
                    Text(premium ? "Premium" : "Free")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Palette.tint, in: Capsule())
                }
            }
            NavigationLink { NotificationsView() } label: { label("Notifications", "bell.fill", Palette.bad) }
            NavigationLink { CurrencyPickerView(selection: $currency) } label: {
                row("Currency", "eurosign", Palette.good) {
                    Text("\(currency) (\(CurrencyOption.symbol(currency)))").foregroundStyle(.secondary)
                }
            }
            NavigationLink { WidgetsView() } label: { label("Widgets", "square.grid.2x2.fill", Color(argb: 0xFF5856D6)) }
        }
    }

    private var dataSection: some View {
        Section {
            Button { exportBackup() } label: {
                label("Export data", "square.and.arrow.up", Color(argb: 0xFF007AFF))
            }
            .buttonStyle(.plain)
            Button { showImporter = true } label: {
                label("Import data", "square.and.arrow.down", Color(argb: 0xFF30B0C7))
            }
            .buttonStyle(.plain)
        } header: {
            Text("Data")
        } footer: {
            Text("Export all your receipts, budgets and categories to a file, or restore from one.")
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            NavigationLink { appearancePicker } label: {
                row("Appearance", "moon.fill", Color(argb: 0xFF636366)) {
                    Text(appearance.label).foregroundStyle(.secondary)
                }
            }
            row("Accent color", "sun.max.fill", Palette.tint) {
                Text("Violet").font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
            }
            NavigationLink { LanguagePickerView(selection: $language) } label: {
                row("Language", "globe", Color(argb: 0xFF0A84FF)) {
                    Text(LanguageOption.name(language)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy & Security") {
            Toggle(isOn: $faceID) { label("Face ID Lock", "lock.fill", Color(argb: 0xFF30B0C7)) }
            Toggle(isOn: $analytics) { label("Analytics", "chart.bar.fill", Color(argb: 0xFF5AC8FA)) }
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

    // MARK: - Rows

    private var profileRow: some View {
        HStack(spacing: 14) {
            AvatarView(initials: auth.initials, size: 56, fontSize: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(auth.email.isEmpty ? "Your account" : auth.email)
                    .font(.title3).fontWeight(.semibold).lineLimit(1)
                Text("Signed in").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func label(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, background: tint)
            Text(title)
        }
    }

    private func row<Trailing: View>(_ title: String, _ symbol: String, _ tint: Color,
                                      icon: Color = .white,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, background: tint, foreground: icon)
            Text(title)
            Spacer()
            trailing()
        }
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
