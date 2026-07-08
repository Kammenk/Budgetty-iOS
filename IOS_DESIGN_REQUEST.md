# iOS Design Request — Budgetty for iPhone & iPad

## Context

Budgetty is an existing Android app (Jetpack Compose, Material 3) that tracks spending by
scanning receipts. We are now building a **native SwiftUI** version for iOS (iPhone + iPad,
iOS 26.5). This request is for iOS-native mockups of the app's screens.

**Do not port the Material layouts 1:1.** Reimagine each screen for iOS following Apple's
Human Interface Guidelines, while keeping Budgetty's brand and information design.

## Keep (brand + product)

- **Brand accent:** violet `#6650A4` (light) / `#D0BCFF` (dark).
- **Category system:** the 46-category, two-level taxonomy — each category has an emoji icon
  and a specific color (green Groceries, rose Household, teal Health, terracotta Dining,
  violet Shopping, amber Transportation, blue Services, grey Other; sub-categories spread
  across distinct hues). Reuse these exact hues in charts and tiles.
- **Money add-on model:** per-receipt spend anchors on the printed grand total (net line
  prices + discount + on-top VAT + delivery/service fees & tip). Show discounts as a green
  savings pill and VAT as an "incl. VAT" line.
- The overall information architecture: Home dashboard, receipt scan/review, spending
  history, insights/trends, and budgeting (incl. income & recurring bills).

## Make it iOS-native

- **Bottom tab bar** as the primary nav: **Home · History · Scan · Insights · Budget**
  (Scan is the prominent center action).
- **Large navigation titles** that collapse on scroll; `NavigationStack`/`NavigationSplitView`.
- **SF Symbols** for all iconography (not Material icons).
- **Native sheet presentations** with grabbers + detents (`.medium`/`.large`) instead of
  Material bottom sheets; inset-grouped `List` styling; `.regularMaterial` cards.
- Respect safe areas, Dynamic Type, and San Francisco typography.
- **Light + dark mode** for every screen.

## Screens to design

1. **Home** — dashboard: period spend total, budget progress, category breakdown (donut),
   recent receipts, customizable sections.
2. **Receipt scan → review/edit** — camera capture, then an editable list of extracted line
   items (name, qty, price, category), store, date, discount, VAT, extra charges; save/finalize.
3. **History** — segmented tabs **Receipts · Items · Budgets**; day/month grouping; search,
   sort, price-range filter.
4. **Insights** — period stepper (Week/Month/Quarter/Half/Custom), trend chart, breakdown,
   top stores, biggest purchases, income-vs-spending, savings rate, upcoming bills.
5. **Budget** — single budget period (Monthly/Weekly), overall + per-category limits, income
   sources, recurring payments/bills, "left after bills".
6. **Account / Settings** — profile (initials avatar), currency, language, theme, premium.
7. **Paywall** — free vs. Premium (uses StoreKit on iOS).
8. **Onboarding** — first-run intro + currency auto-detect.

## Deliverables

- **iPhone (390 pt wide)** and **iPad (multi-column / split view)** layouts for each screen.
- Light + dark variants.
- Delivered as `.dc.html` mockups in the Budgetty design project so they can be pulled into
  the iOS codebase via DesignSync.

## Reference

- Existing brand/design source of truth: `BUDGETTY_DESIGN_BRIEF.md` (this repo) and the
  Android app's design tokens (`ui/theme/Color.kt`, `Dimens.kt`).
- iOS codebase: `/Users/kamenkostov/budgetty ios/budgetty/` (SwiftData models + theme tokens
  already ported; screens pending these designs).
