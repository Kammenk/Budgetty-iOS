//
//  AccessibilityID.swift
//  Budgetty
//
//  Stable `accessibilityIdentifier` strings for UI automation (Maestro / XCUITest). These are NOT
//  localized display text — they never change when the app is run in German — so one cross-platform
//  Maestro flow can drive both iOS and Android by the same selectors.
//
//  ⚠️ CROSS-PLATFORM CONTRACT: keep these strings identical to Android's Compose test tags. The
//  scheme is `snake_case`, `{screen}_{element}`, matching Android (e.g. `LoginTagEmail = "login_email"`
//  in LoginScreen.kt). When either platform adds a tag, mirror it here / there. Android exposes tags
//  as resource-ids via `testTagsAsResourceId`; iOS gets there for free with `accessibilityIdentifier`.
//
//  Only interactive controls on the main journeys are tagged (launch → scan → save, plus the tab
//  screens). Repeated rows share one id (fine for `assertVisible`, which any match satisfies).
//

enum A11y {
    enum Login {
        static let apple = "login_apple"
        static let email = "login_email"          // == Android LoginTagEmail
        static let password = "login_password"     // == Android LoginTagPassword
        static let signIn = "login_sign_in"        // == Android LoginTagSignIn
        static let modeToggle = "login_mode_toggle"
    }

    enum Tab {
        static let home = "tab_home"
        static let history = "tab_history"
        static let insights = "tab_insights"
        static let budget = "tab_budget"
        static let scan = "tab_scan"               // the floating Scan pill / accessory
    }

    /// Receipt-scan capture screen (ScanFlowView).
    enum Scan {
        static let close = "scan_close"
        static let shutter = "scan_shutter"
        static let gallery = "scan_gallery"
        static let manual = "scan_manual"
        static let goPremium = "scan_go_premium"
        static let save = "scan_save"              // the pivotal journey action (footer CTA in Review)
    }

    /// Editable review screen (ReviewView).
    enum Review {
        static let cancel = "review_cancel"
        static let saveHeader = "review_save_header"
        static let addItem = "review_add_item"
        static let store = "review_store"
    }

    enum Home {
        static let account = "home_account"
        static let customize = "home_customize"
        static let recentReceipts = "home_recent_receipts"
        static let seeAllReceipts = "home_see_all_receipts"
        static let seeAllBudgets = "home_see_all_budgets"
    }

    enum History {
        static let search = "history_search"
        static let modeToggle = "history_mode_toggle"
        static let receiptsList = "history_receipts_list"
    }

    enum Budget {
        static let periodToggle = "budget_period_toggle"
        static let overall = "budget_overall"
    }

    enum Insights {
        static let customize = "insights_customize"
        static let periodPrev = "insights_period_prev"
        static let periodNext = "insights_period_next"
    }

    enum Paywall {
        static let close = "paywall_close"
        static let planYearly = "paywall_plan_yearly"
        static let planMonthly = "paywall_plan_monthly"
        static let subscribe = "paywall_subscribe"
        static let restore = "paywall_restore"
    }

    /// Shared receipt row (Home "Recent Receipts" + History). One id for "a receipt is present".
    static let receiptRow = "receipt_row"
}
