//
//  RecapReopenView.swift
//  Budgetty
//
//  Re-opens the user's last recap from Insights, recomputed on demand (a quick dismiss never loses it)
//  — the Swift port of Android's `RecapReopenScreen` + `RecapReopenRow` + the `RecapViewModel.reopen`
//  target logic. The settings footnote promises this door. ✕ / Done / See details all just dismiss —
//  nothing is re-stamped, since this isn't the once-per-period interstitial.
//

import SwiftUI
import SwiftData

/// A recomputed target: which recap to rebuild and at what pay-cycle/week offset. Prefers whichever
/// period ended more recently (Android's `lastShownTarget`).
struct RecapReopenTarget {
    let kind: RecapKind
    let offset: Int

    /// Resolves the last-shown keys to a target, or nil when none was ever shown.
    static func resolve(lastShownWeek: String, lastShownMonth: String, monthStartDay: Int,
                        today: Date = .now, firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                        calendar cal: Calendar = .current) -> RecapReopenTarget? {
        let month = parseMonth(lastShownMonth, cal)   // (year, month, endDate)
        let week = parseWeek(lastShownWeek, cal)       // (start, end)

        if let month, week == nil || month.end >= week!.end {
            return RecapReopenTarget(kind: .monthly,
                                     offset: monthOffset(year: month.year, month: month.month,
                                                         monthStartDay: monthStartDay, today: today, cal: cal))
        }
        if let week {
            return RecapReopenTarget(kind: .weekly,
                                     offset: weekOffset(shownWeekStart: week.start, today: today,
                                                        firstWeekday: firstWeekday, cal: cal))
        }
        return nil
    }

    private static func parseMonth(_ id: String, _ cal: Calendar) -> (year: Int, month: Int, end: Date)? {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        // Last day of that calendar month (matches Android's YearMonth.atEndOfMonth).
        guard let firstOfMonth = cal.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth),
              let end = cal.date(from: DateComponents(year: y, month: m, day: range.count)) else { return nil }
        return (y, m, end)
    }

    private static func parseWeek(_ id: String, _ cal: Calendar) -> (start: Date, end: Date)? {
        guard !id.isEmpty else { return nil }
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: id),
              let end = cal.date(byAdding: .day, value: 6, to: start) else { return nil }
        return (start, end)
    }

    private static func monthOffset(year: Int, month: Int, monthStartDay: Int, today: Date, cal: Calendar) -> Int {
        let currentStart = PayCycle.month(today, startDay: monthStartDay, offset: 0, calendar: cal).start
        let cc = cal.dateComponents([.year, .month], from: currentStart)
        return (year - (cc.year ?? year)) * 12 + (month - (cc.month ?? month))
    }

    private static func weekOffset(shownWeekStart: Date, today: Date, firstWeekday: Int, cal: Calendar) -> Int {
        var wcal = cal
        wcal.firstWeekday = firstWeekday
        let currentWeekStart = wcal.dateInterval(of: .weekOfYear, for: today)?.start ?? wcal.startOfDay(for: today)
        return wcal.dateComponents([.weekOfYear], from: currentWeekStart, to: shownWeekStart).weekOfYear ?? 0
    }
}

struct RecapReopenView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]
    @Query private var ignoredRows: [IgnoredSubscription]
    @Query(sort: \BuyingLimit.createdAt) private var limits: [BuyingLimit]

    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.recapLastShownWeek) private var lastShownWeek = ""
    @AppStorage(SettingsKey.recapLastShownMonth) private var lastShownMonth = ""

    private var story: RecapStory? {
        guard let target = RecapReopenTarget.resolve(lastShownWeek: lastShownWeek,
                                                     lastShownMonth: lastShownMonth,
                                                     monthStartDay: monthStartDay) else { return nil }
        return RecapBuilder.build(kind: target.kind, offset: target.offset, receipts: receipts,
                                  budgets: budgets, recurring: recurring, goals: goals,
                                  contributions: contributions,
                                  ignoredSubs: Set(ignoredRows.map(\.merchant)), limits: limits,
                                  monthStartDay: monthStartDay)
    }

    var body: some View {
        if let story {
            RecapStoryView(story: story, onClose: { dismiss() }, onSeeDetails: { dismiss() })
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ZStack(alignment: .topLeading) {
            Palette.groupedBackground.ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.label).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.top, 8)
            Text("No recap yet. You will see one when a period closes.")
                .font(.title3).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The slim Insights entry that re-opens the last recap — a sibling of the Wellbeing row, pinned just
/// below it. Shown only once a recap has been generated for a closed period.
struct RecapReopenRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.recapSecondary)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text("Your last recap").font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                Text("The summary from your last closed period")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 20)
    }
}
