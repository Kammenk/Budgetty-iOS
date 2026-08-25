//
//  StreakMotif.swift
//  Budgetty
//
//  The shared, calm streak visual language (§2.6) — the SwiftUI port of Android's
//  `ui/streaks/StreakMotif.kt`. A short row of rounded segments that reads the same everywhere a streak
//  surfaces: the Recap Streak card (§1.3), the de-flamed monthly budget card (§2.4), and later the
//  Wellbeing evidence (§3) and Buying-limits card (§4). Deliberately general and stateless so those
//  callers reuse it as-is.
//
//  The motif carries three states, all in the one "good" tone — never a flame, never a status red, never
//  amber, and never a countdown (§1 principle 2):
//   - `filledCount` solid segments = closed periods met.
//   - one dashed ghost segment (60% opacity) when `showLive` = the open period, "on track so far". Only
//     rendered for a live current run, never for a best-run fallback.
//   - `muted` mode = every segment solid good at ~55% opacity with no ghost — the best-run fallback, a
//     quiet record of a past run rather than a live one.
//
//  Segment geometry mirrors the design mockup (rounded pills, ~24 × 8 pt); `maxSegments` caps the row so
//  a long (up to 24-period) run can't overflow — the exact number always lives in the hero copy.
//

import SwiftUI

struct StreakMotif: View {
    let filledCount: Int
    var showLive: Bool = false
    var muted: Bool = false
    var maxSegments: Int = 8
    /// The one "good" tone all three states share. Defaults to the app's budget-good green; a caller can
    /// override it (e.g. a future Wellbeing/limit surface) without the motif ever going red/amber.
    var tone: Color = Palette.good

    private var filled: Int { min(max(filledCount, 0), maxSegments) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<filled, id: \.self) { _ in
                Capsule()
                    .fill(tone.opacity(muted ? 0.55 : 1))
                    .frame(width: 24, height: 8)
            }
            // The live/on-track ghost: a dashed outline of the same good tone, only on a live current run.
            if showLive && !muted {
                Capsule()
                    .strokeBorder(tone.opacity(0.6),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                    .frame(width: 24, height: 8)
            }
        }
    }
}

#if DEBUG
#Preview("Streak motif · states") {
    VStack(alignment: .leading, spacing: 14) {
        StreakMotif(filledCount: 3, showLive: true)   // live current run
        StreakMotif(filledCount: 6, muted: true)      // best-run fallback
        StreakMotif(filledCount: 2)                    // plain
    }
    .padding()
    .background(Palette.groupedBackground)
}
#endif
