//
//  WidgetQuotaTests.swift
//  BudgettyTests
//
//  The widget cap is enforced inside the extension's timeline provider, where a test can't reach it
//  — so the decision is a pure function and this is where it's checked. What's left for device
//  verification is only the plumbing: whether `WidgetCenter.currentConfigurations()` answers from an
//  extension, and whether a purchase reloads the timelines.
//
//  NB: these exercise the app target's copy of WidgetQuota. The extension carries a byte-identical
//  duplicate (the two targets can't share a file under the synchronized-folder layout) — if you edit
//  one, diff it against the other.
//

import Testing
import WidgetKit
@testable import Budgetty

struct WidgetQuotaTests {
    private let spendSmall = WidgetSlot(kind: "BudgettySpending", family: .systemSmall)
    private let spendMedium = WidgetSlot(kind: "BudgettySpending", family: .systemMedium)
    private let ringSmall = WidgetSlot(kind: "BudgettyBudgetRing", family: .systemSmall)
    private let receiptsMedium = WidgetSlot(kind: "BudgettyRecentReceipts", family: .systemMedium)

    @Test func underTheCapNothingLocks() {
        let placed = [spendSmall, ringSmall]
        for slot in placed {
            #expect(!WidgetQuota.isLocked(slot, placed: placed, isPremium: false))
        }
        #expect(WidgetQuota.remaining(placed: placed, isPremium: false) == 0)
    }

    @Test func pastTheCapOnlyTheOverflowLocks() {
        let placed = [spendSmall, ringSmall, receiptsMedium]
        #expect(!WidgetQuota.isLocked(spendSmall, placed: placed, isPremium: false))
        #expect(!WidgetQuota.isLocked(ringSmall, placed: placed, isPremium: false))
        #expect(WidgetQuota.isLocked(receiptsMedium, placed: placed, isPremium: false))
    }

    /// The rank is canonical, so the same two faces stay lit however WidgetKit orders its reply —
    /// otherwise which widget goes dark would flicker between reloads.
    @Test func theLockedFaceDoesNotDependOnEnumerationOrder() {
        let forwards = [spendSmall, ringSmall, receiptsMedium]
        let backwards: [WidgetSlot] = forwards.reversed()
        for slot in forwards {
            #expect(WidgetQuota.isLocked(slot, placed: forwards, isPremium: false)
                    == WidgetQuota.isLocked(slot, placed: backwards, isPremium: false))
        }
    }

    /// Sizes are separate faces: two sizes of one widget use both free slots.
    @Test func sizesCountSeparately() {
        let placed = [spendSmall, spendMedium, ringSmall]
        #expect(WidgetQuota.remaining(placed: placed, isPremium: false) == 0)
        #expect(WidgetQuota.isLocked(ringSmall, placed: placed, isPremium: false))
    }

    /// …but duplicates of one face share its fate, which is the documented divergence from Android:
    /// WidgetKit exposes no per-instance identity, so three copies of an allowed face all render.
    @Test func duplicatesOfOneFaceShareASlot() {
        let placed = [spendSmall, spendSmall, spendSmall]
        #expect(WidgetQuota.remaining(placed: placed, isPremium: false) == 1)
        #expect(!WidgetQuota.isLocked(spendSmall, placed: placed, isPremium: false))
    }

    @Test func premiumIsUncapped() {
        let placed = [spendSmall, spendMedium, ringSmall, receiptsMedium]
        for slot in placed {
            #expect(!WidgetQuota.isLocked(slot, placed: placed, isPremium: true))
        }
        #expect(WidgetQuota.remaining(placed: placed, isPremium: true) == nil)
    }

    /// Removing a widget frees its slot immediately — the cap is live, not a high-water mark.
    @Test func removingAWidgetUnlocksTheRest() {
        let over = [spendSmall, ringSmall, receiptsMedium]
        #expect(WidgetQuota.isLocked(receiptsMedium, placed: over, isPremium: false))
        let after = [spendSmall, receiptsMedium] // the user removed the ring
        #expect(!WidgetQuota.isLocked(receiptsMedium, placed: after, isPremium: false))
    }

    /// Fail open: an empty enumeration means WidgetKit didn't tell us, or the widget is rendering
    /// before the system registered it. Locking there would flash a lock on a legitimate widget.
    @Test func unknownPlacementsNeverLock() {
        #expect(!WidgetQuota.isLocked(spendSmall, placed: [], isPremium: false))
        #expect(WidgetQuota.remaining(placed: [], isPremium: false) == WidgetQuota.freeLimit)
    }

    /// Every shipped widget kind must be ranked, or an unranked one sorts last and is always the
    /// first to lock — a silent bug the moment a fourth widget is added.
    @Test func everyShippedKindIsRanked() {
        #expect(WidgetQuota.kindOrder.count == 3)
        for kind in ["BudgettySpending", "BudgettyBudgetRing", "BudgettyRecentReceipts"] {
            #expect(WidgetQuota.kindOrder.contains(kind))
        }
    }
}
