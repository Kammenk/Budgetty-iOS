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
    /// One container for the whole app, holding every persisted model.
    let container: ModelContainer

    @State private var auth: AuthModel
    @State private var store: StoreManager

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearancePref.system.rawValue
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.quizPending) private var quizPending = false

    /// First-run gate: show Onboarding until completed. DEBUG env can force either way for previews.
    private var showOnboarding: Bool {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["ONBOARDING"] {
        case "force": return true
        case "skip": return false
        default: break
        }
        #endif
        return !onboarded
    }

    init() {
        FirebaseBootstrap.configure()
        _auth = State(initialValue: AuthModel())
        _store = State(initialValue: StoreManager())
        do {
            container = try ModelContainer(
                for: LineItem.self, Receipt.self, Category.self,
                Budget.self, Recurring.self, CategoryRule.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Signed in? DEBUG builds can bypass the login gate for screenshots.
    private var isAuthed: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SKIP_AUTH"] == "1" { return true }
        #endif
        return auth.isSignedIn
    }

    /// Show the one-time Insights setup quiz (armed at sign-up). DEBUG env can force it for previews.
    private var showQuiz: Bool {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["QUIZ"] {
        case "force": return true
        case "skip": return false
        default: break
        }
        #endif
        return quizPending
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
            .task { @MainActor in
                Seed.categoriesIfNeeded(container.mainContext)
                #if DEBUG
                SampleData.populateIfEmpty(container.mainContext)
                #endif
                WidgetSharing.update(from: container.mainContext)
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
