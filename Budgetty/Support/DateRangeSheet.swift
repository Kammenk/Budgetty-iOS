//
//  DateRangeSheet.swift
//  Budgetty
//
//  A hand-rolled single-month paged calendar for picking a start–end date range (matches the
//  Android custom picker rather than the stock range picker). Returns a ClosedRange<Date> of days.
//

import SwiftUI

struct DateRangeSheet: View {
    @Binding var range: ClosedRange<Date>?
    @Environment(\.dismiss) private var dismiss

    @State private var visibleMonth = Calendar.current.startOfDay(for: .now)
    @State private var start: Date?
    @State private var end: Date?

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                monthHeader
                weekdayRow
                grid
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Palette.label)
                    Button("Apply") { apply() }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .opacity(start == nil ? 0.5 : 1)
                        .disabled(start == nil)
                }
            }
            .padding(20)
            .background(Palette.groupedBackground)
            .navigationTitle("Date Range").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { range = nil; dismiss() }
                }
            }
            .onAppear {
                start = range?.lowerBound
                end = range?.upperBound
                if let s = range?.lowerBound { visibleMonth = monthStart(s) }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle(visibleMonth)).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .foregroundStyle(Palette.label)
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(shortWeekdays, id: \.self) { d in
                Text(d).font(.caption).foregroundStyle(Palette.secondaryLabel).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(daysInGrid().enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = isInRange(day)
        let endpoint = sameDay(day, start) || sameDay(day, end)
        return Button {
            pick(day)
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.subheadline)
                .frame(maxWidth: .infinity).frame(height: 40)
                .foregroundStyle(endpoint ? .white : (selected ? Palette.tint : Palette.label))
                .background {
                    if endpoint { Circle().fill(Palette.tint) }
                    else if selected { Palette.tintSoft }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func pick(_ day: Date) {
        if start == nil || end != nil {
            start = day; end = nil
        } else if let s = start {
            if day < s { start = day } else { end = day }
        }
    }

    private func apply() {
        guard let s = start else { return }
        let e = end ?? s
        range = min(s, e)...max(s, e)
        dismiss()
    }

    private func isInRange(_ day: Date) -> Bool {
        guard let s = start else { return false }
        let e = end ?? s
        let lo = min(s, e), hi = max(s, e)
        return day >= cal.startOfDay(for: lo) && day <= cal.startOfDay(for: hi)
    }

    private func sameDay(_ a: Date, _ b: Date?) -> Bool { b.map { cal.isDate(a, inSameDayAs: $0) } ?? false }
    private func shift(_ n: Int) { visibleMonth = cal.date(byAdding: .month, value: n, to: visibleMonth) ?? visibleMonth }
    private func monthStart(_ d: Date) -> Date { cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d }

    private func daysInGrid() -> [Date?] {
        let first = monthStart(visibleMonth)
        let weekday = cal.component(.weekday, from: first) // 1=Sun
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<count { cells.append(cal.date(byAdding: .day, value: d, to: first)) }
        return cells
    }

    private var shortWeekdays: [String] {
        let syms = cal.shortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(syms[start...] + syms[..<start])
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: d)
    }
}
