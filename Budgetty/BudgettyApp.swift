//
//  BudgettyApp.swift
//  Budgetty
//
//  App entry point. Sets up the SwiftData container for the ported model layer and seeds the
//  predefined categories on launch.
//

import SwiftUI
import SwiftData

@main
struct BudgettyApp: App {
    /// The signed-in account's store. Swapped when the account changes so two users sharing a
    /// device never see each other's data — see `UserStore`.
    @State private var container: ModelContainer

    @State private var auth: AuthModel
    @State private var store: StoreManager

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearancePref.system.rawValue
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.quizPending) private var quizPending = false

    /// First-run gate: show Onboarding until completed. DEBUG env can force either way for previews.
    private var showOnboarding: Bool {
        #if DEBUG
        switch LaunchFlags.value("ONBOARDING") {
        case "force": return true
        case "skip": return false
        default: break
        }
        #endif
        return !onboarded
    }

    init() {
        FirebaseBootstrap.configure()
        // Firebase restores the previous session synchronously, so the very first container is
        // already the right account's — no empty frame, no scratch-store flash.
        let auth = AuthModel()
        _auth = State(initialValue: auth)
        _store = State(initialValue: StoreManager())
        _container = State(initialValue: UserStore.container(for: auth.uid))
    }

    /// Signed in? DEBUG builds can bypass the login gate for screenshots.
    private var isAuthed: Bool {
        #if DEBUG
        if LaunchFlags.isOn("SKIP_AUTH") { return true }
        #endif
        return auth.isSignedIn
    }

    /// Show the one-time Insights setup quiz (armed at sign-up). DEBUG env can force it for previews.
    private var showQuiz: Bool {
        #if DEBUG
        switch LaunchFlags.value("QUIZ") {
        case "force": return true
        case "skip": return false
        default: break
        }
        #endif
        return quizPending
    }

    /// Brings a freshly-opened store up to date: data migrations, then the predefined categories.
    @MainActor
    private func prepare(_ container: ModelContainer) {
        // Before seeding: the split repoints rows off the old category name, and seeding would
        // otherwise insert the new one first, forcing the collision branch and discarding the
        // existing row's colour.
        Migrations.splitSubscriptionsAndServices(container.mainContext)
        Seed.categoriesIfNeeded(container.mainContext)
        #if DEBUG
        SampleData.populateIfEmpty(container.mainContext)
        #endif
        WidgetSharing.update(from: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showOnboarding {
                    OnboardingView()
                } else if !isAuthed {
                    LoginView()
                } else if showQuiz {
                    InsightsQuizView(onComplete: { quizPending = false })
                } else {
                    LockGate { RootView() }
                }
            }
            .environment(auth)
            .environment(store)
            .tint(Palette.tint)
            .preferredColorScheme((AppearancePref(rawValue: appearanceRaw) ?? .system).colorScheme)
            .task { @MainActor in prepare(container) }
            .onChange(of: auth.uid) { _, uid in
                // A fresh account opens a store that has never been seeded, so prepare it too.
                let next = UserStore.container(for: uid)
                container = next
                prepare(next)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    WidgetSharing.update(from: container.mainContext)
                }
            }
        }
        .modelContainer(container)
    }
}
