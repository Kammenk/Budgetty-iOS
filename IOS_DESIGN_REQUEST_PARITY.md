# iOS Design Request — Android parity gaps (Liquid Glass)

Source: the 2026-07-14 Android⇄iOS cross-check (`PARITY.md`). Every feature below already
ships on Android with a Material mockup in this design project, but has **no Liquid Glass
counterpart**. Produce the iOS mockups so implementation can start; behavior is fixed by the
Android app — only the visual language changes.

## Conventions (apply to every item)

- **Liquid Glass v2**, matching the token set and restraint rules of the existing `iOS *.dc.html`
  mockups (rounds 1–11): content is the hero, glass only for chrome and a few key controls,
  capsule geometry, light + dark, graceful Reduce-Transparency fallbacks.
- Deliver as `.dc.html` with the established prop pattern (`dark` enum, `device` `iphone`/`ipad`,
  per-screen `state` props). Extend an existing `iOS *.dc.html` file where noted instead of
  creating a near-duplicate.
- Layouts must tolerate **long translated strings** — iOS localization (21 languages) is queued
  right behind these features. Don't design to English width.
- Money strings below use EUR; keep the app's category emoji/colors.

---

## 1. iOS Home — recurring-bills summary strip (extend `iOS Home.dc.html`, new state `bills`)

Android 10.4.0's headline feature. The Home "Total spent" card pairs receipt-backed spending
with **planned** recurring bills for the current month:

- A slim two-segment strip: actual **Spent** vs **Bills · planned** (planned portion visually
  lighter/hatched — it hasn't happened yet).
- Below it: a "Spent" line (receipt total), a "Bills · planned" line (sum of this month's
  recurring bills), and a combined "**With bills**" total.
- Bills must clearly read as *planned, not yet spent* — don't let the combined number look like
  actual spending.
- When the user has **no recurring bills**, the card collapses to today's plain total (current
  design) — show both states.
- Very large amounts scroll horizontally rather than truncate.

**Android reference:** `Home Bills Summary Explorations.dc.html` — the shipped option is
**1b "planned strip"**. Translate that concept, not its Material chrome.

## 2. iOS Insights — missing analysis cards (extend `iOS Insights Extra Cards.dc.html`)

Android's Insights has 14 customizable sections; iOS has 6. The five income cards are already
designed/built — these are the rest. Each is one card in the Insights scroll, reorderable and
hideable via the existing Customize sheet, all period-relative to the period stepper:

- **Highlights** — up to ~4 short insight rows/chips for the period, e.g. "First spend in
  Garden & Plants — €23.40", "Groceries up 18% vs last period", "Dining down 12% vs last
  period", "Groceries made up 31% of spending". Emoji of the category leads each row.
- **Period comparison** — this period vs the previous equivalent period (labels are relative:
  "vs last month/week/quarter"): totals side-by-side with a delta % up/down in good/bad color.
- **Budget** (budget-vs-actual) — progress toward the period budget: spent vs budget amount,
  progress bar in status color (good → warn → over), "N days left" caption. Only shown when a
  budget is set.
- **Biggest purchases** — the top ~5 single line items of the period: emoji tile, item name,
  store + date caption, amount, sorted largest first.
- **Spending pace** — a one-line projection on the **Trend card** (current period only):
  "On pace for about €412". A caption under the chart, not a separate card.
- **Stat grid** — add an "**Avg / day**" tile to the existing grid (currently Total spent /
  Receipts / Avg per receipt / Saved).

**Android references:** `InsightsScreen.dc.html`, `InsightsScreen Variants.dc.html`,
`InsightsBiggestBills.dc.html`. If any of these cards already exist in
`iOS Insights Extra Cards.dc.html`, skip them.

## 3. iOS Insights — Breakdown card toggle (extend `iOS Insights.dc.html`)

The Breakdown donut currently shows the 7 category **groups** only. Android adds a two-option
toggle on the card ("Groups ↔ All categories"): all-categories mode re-renders the donut and
legend at individual-category granularity. Use the app's existing capsule segmented-control
pattern, small, in the card header. Show both modes.

## 4. iOS Home — Customize sections sheet (small; can reuse the Insights pattern)

Same interaction as the existing iOS Insights Customize sheet (show/hide toggles + drag
reorder + revert), but for Home's sections: **Total spent · Week comparison · Budgets ·
Receipts**. Entry point: same top-trailing control as Insights. If the Insights sheet design
generalizes 1:1, a variant/state on that file is enough — no new concept needed.

## 5. iOS Add-receipt entry — free-scan quota states (extend `iOS Scan.dc.html` or the add sheet)

iOS currently has no quota UI at all. Android's add-receipt sheet has three states
(`Premium / Free(n) / Exhausted`):

- **Premium:** no counter, all options enabled.
- **Free(n):** subtitle under the title — "N of 10 free scans left (photo or file). Manual
  entry is always free."
- **Exhausted:** photo/file options disabled with a lock glyph, message "You've used all 10
  free scans. Go Premium to scan more — manual entry is always free.", and a **Go Premium**
  button. Manual entry stays enabled.

**Android reference:** `AddSheetScreen.dc.html`. A scan is only consumed when a receipt is
saved (not on failed reads) — no visual impact, just context.

## 6. iOS Scan review — extraction-warning pair (extend `iOS Scan.dc.html` review state)

Two warning tiers on the review step, both missing on iOS:

- **Dropped-line guard (blocking):** shown when the extracted items sum to *less* than the
  receipt's printed subtotal — an alert telling the user some lines may have been missed,
  asking them to double-check the items before saving. Native alert styling; the primary
  action returns to review, no silent save.
- **Price-mismatch notice (soft):** a non-blocking inline banner on the review list when
  totals don't reconcile exactly — informational tone, dismissible, doesn't stop saving.

**Android reference:** the 10.3.0 dropped-line dialog + the older soft `PriceMismatchNotice`
(see `ReviewEditScreen.dc.html` context).

## 7. (Optional, low priority) iOS Widgets — remaining widget types

iOS ships one widget (Spending, small+medium); Android ships several (summary, budget
progress, this-week, top-categories, quick-scan). If/when we close this, design LG WidgetKit
small+medium variants for the missing types — reference `Widgets v2.dc.html` /
`WidgetHomeScreen.dc.html`. **Skip for now unless trivial; decide after the items above.**

---

## Explicitly NOT needing design work (implementation-only parity items)

- **4 new categories** (Video Games, Investments, Tips, Delivery) — taxonomy/emoji already
  defined in the Android handoff.
- **Delivery & fees / Tip line items** — render as ordinary line items with their categories.
- **Document-scanner capture** — iOS uses the stock VisionKit scanner UI.
- **Unlimited premium custom categories** — copy change on the existing sheet.
- **Localization** — no visual change (but see the long-strings convention above).
