//
//  WidgetQuota.swift
//  Budgetty · BudgettyWidget
//
//  The free tier's home-screen widget cap.
//
//  ⚠️ DUPLICATED byte-for-byte in `Budgetty/Widget/` and `BudgettyWidget/`. Both targets need it —
//  the extension to enforce, the app to show how many slots are left — and under the
//  synchronized-folder project layout a file belongs to exactly one target. Same arrangement as
//  WidgetSnapshot.swift. Change one, change the other.
//
//  Nothing is persisted: the set of placed widgets *is* the state, which is what makes the cap
//  self-healing — remove one from the home screen and its slot frees immediately, with nothing to
//  migrate. That much is straight from Android's `WidgetQuota`.
//
//  ⚠️ WHERE iOS DIVERGES FROM ANDROID, deliberately. Android counts placed *instances* and keeps the
//  oldest ones working, because `AppWidgetManager` hands out ascending ids that encode placement
//  order. WidgetKit exposes no per-instance identity at all — `WidgetInfo` carries only kind, family
//  and configuration — so two medium Budget Rings are indistinguishable and "lock the third one" is
//  not expressible. We cap distinct **faces** (kind × size) in a fixed canonical order instead.
//  Consequence to keep in mind when writing copy: a free user can place three copies of one allowed
//  face for free.
//

import WidgetKit

/// One widget face: a kind at a size. Not a placed instance — see the divergence note above.
struct WidgetSlot: Hashable {
    let kind: String
    let family: WidgetFamily
}

enum WidgetQuota {
    /// Widget faces a free user may have placed at once. Premium is uncapped.
    static let freeLimit = 2

    static let appGroup = "group.com.budgetty.Budgetty"
    /// Written by the app whenever entitlement changes, so the extension can enforce without it.
    static let premiumKey = "widget.premium"

    /// The order the cap keeps when a free user is over it. Android keeps whichever widgets are
    /// *oldest*; iOS surfaces no placement order, so a stable canonical rank stands in — arbitrary
    /// from the user's side, but deterministic, so the same two stay lit across every reload rather
    /// than shuffling.
    static let kindOrder = ["BudgettySpending", "BudgettyBudgetRing", "BudgettyRecentReceipts"]

    static func rank(_ slot: WidgetSlot) -> Int {
        (kindOrder.firstIndex(of: slot.kind) ?? kindOrder.count) * 100 + slot.family.rawValue
    }

    /// The faces that render their data rather than the locked card.
    static func allowed(placed: [WidgetSlot], isPremium: Bool) -> Set<WidgetSlot> {
        let distinct = Set(placed)
        guard !isPremium else { return distinct }
        return Set(distinct.sorted { rank($0) < rank($1) }.prefix(freeLimit))
    }

    /// Whether this face must draw the locked card.
    ///
    /// Fails **open** on an empty `placed`: WidgetKit can't always enumerate configurations, and a
    /// widget can render before the system registers it, so locking on that half-known state would
    /// flash a lock over a perfectly legitimate first widget. The next reload settles it. (Android
    /// guards the same way on `INVALID_APPWIDGET_ID`.)
    static func isLocked(_ slot: WidgetSlot, placed: [WidgetSlot], isPremium: Bool) -> Bool {
        guard !isPremium, !placed.isEmpty else { return false }
        return !allowed(placed: placed, isPremium: false).contains(slot)
    }

    /// Free slots left, or nil when uncapped — callers show an "unlimited" state instead of a count.
    static func remaining(placed: [WidgetSlot], isPremium: Bool) -> Int? {
        isPremium ? nil : max(0, freeLimit - Set(placed).count)
    }

    /// Every widget face currently on a home screen. Empty when WidgetKit won't say — which
    /// `isLocked` reads as "don't lock".
    static func placedSlots() async -> [WidgetSlot] {
        let infos = try? await WidgetCenter.shared.currentConfigurations()
        return (infos ?? []).map { WidgetSlot(kind: $0.kind, family: $0.family) }
    }

    /// Entitlement as last written by the app. Unknown (no key yet — an older build, or a fresh
    /// install whose app hasn't run) means **don't lock**: widgets shipped free, and locking someone
    /// out on a missing flag is the worse failure.
    static func isPremiumFromSharedStore() -> Bool {
        UserDefaults(suiteName: appGroup)?.object(forKey: premiumKey) as? Bool ?? true
    }

    /// The enforcement entry point, called from each widget's timeline provider.
    static func isLocked(kind: String, family: WidgetFamily) async -> Bool {
        isLocked(WidgetSlot(kind: kind, family: family),
                 placed: await placedSlots(),
                 isPremium: isPremiumFromSharedStore())
    }
}
