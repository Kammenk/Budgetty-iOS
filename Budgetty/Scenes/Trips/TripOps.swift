//
//  TripOps.swift
//  Budgetty
//
//  Trip lifecycle: start / end / delete, plus the tag the trip owns. A trip is metadata over a tag
//  (`Trip`), so starting one is: derive its tag from the name + year, make sure that tag is in the
//  catalog (`TagOps`), deactivate any other active trip, insert it, and — if asked — back-fill by
//  tagging every expense from the start date on. The trips table and the tag tables stay independent,
//  so ending a trip leaves every tagged expense intact. Android parity: `TripRepository` +
//  `TripsViewModel.start/endActive/delete`.
//

import Foundation
import SwiftData

enum TripOps {

    /// Starts a trip as the active one. Only the name is required; the tag derives from it + the year.
    @MainActor
    static func start(_ context: ModelContext, name: String, startDate: Date?, endDate: Date?,
                      budget: Decimal?, backfill: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = tripTag(trimmed, startDate)
        guard let tagRow = TagOps.ensure(context, name: tag) else { return }

        let now = Date()
        for t in activeTrips(context) { t.active = false; t.endedAt = now }

        context.insert(Trip(name: trimmed, tag: tag, startDate: startDate, endDate: endDate,
                            budgetAmount: budget, active: true, createdAt: now))

        if backfill, let start = startDate {
            let floor = Calendar.current.startOfDay(for: start)
            for item in itemsSince(context, floor) where !item.tags.contains(where: { $0.name == tag }) {
                item.tags.append(tagRow)
            }
        }
        try? context.save()
    }

    /// Resumes a past trip: makes it active again (ending any other active trip first). Its tag and
    /// expenses are untouched; new expenses start being tagged with it again.
    @MainActor
    static func resume(_ context: ModelContext, _ trip: Trip) {
        let now = Date()
        for t in activeTrips(context) where t !== trip { t.active = false; t.endedAt = now }
        trip.active = true
        trip.endedAt = nil
        try? context.save()
    }

    /// Ends the active trip — new expenses stop being tagged; nothing already tagged is touched.
    @MainActor
    static func endActive(_ context: ModelContext) {
        let now = Date()
        for t in activeTrips(context) { t.active = false; t.endedAt = now }
        try? context.save()
    }

    /// Removes a trip's metadata. Its tag and the expenses carrying it stay (find them under Tags).
    @MainActor
    static func delete(_ context: ModelContext, _ trip: Trip) {
        context.delete(trip)
        try? context.save()
    }

    /// "lisbon-2026" from "Lisbon" + the start year (or this year) — a normalized, year-stamped tag.
    /// A name that already ends in that year ("Lisbon 2026") isn't stamped twice (`lisbon-2026`, not
    /// `lisbon-2026-2026`); any other trailing number still gets the year. Android parity:
    /// `TripsViewModel.tripTag`.
    static func tripTag(_ name: String, _ startDate: Date?, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: startDate ?? Date())
        let normalized = Tag.normalize(name)
        let base = normalized.isEmpty ? "trip" : normalized
        let suffix = "-\(year)"
        return base.hasSuffix(suffix) ? base : base + suffix
    }

    /// Line items from `floor` (start of a day) onward — the backfill set and the start-sheet count.
    @MainActor
    static func itemsSince(_ context: ModelContext, _ floor: Date) -> [LineItem] {
        (try? context.fetch(FetchDescriptor<LineItem>(predicate: #Predicate { $0.createdAt >= floor }))) ?? []
    }

    private static func activeTrips(_ context: ModelContext) -> [Trip] {
        (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.active }))) ?? []
    }
}
