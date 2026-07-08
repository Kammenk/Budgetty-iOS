# iOS Design Request — Phase 2 (remaining screens + iPad/tablet)

Follow-up to `IOS_DESIGN_REQUEST.md`. Phase 1 delivered 8 iOS mockups (Home, History, Insights,
Budget, Account, Paywall, Scan, Onboarding) — all now built in SwiftUI. This phase covers the
**remaining screens** and the **iPad/tablet layouts**.

## Conventions (apply to every screen here)

- **iOS-native, per Apple HIG.** Reuse the exact tokens already established in the Phase 1 mockups:
  the CSS `:root` / `.dark` variable block (grouped backgrounds `#F2F2F7`/`#000`, card `#FFF`/`#1C1C1E`,
  label levels, `--tint` violet `#6650A4`/`#BFA8FF`, `--good/--warn/--bad`, hero gradient
  `#5E4CAB→#7B5AC8→#9A6FE0`). Keep the brand + the 46-category emoji/colors.
- **SF Symbols**, native sheets with grabbers + detents, inset-grouped `List` styling, large nav
  titles, `.regularMaterial` bars, safe-area aware, **light + dark**.
- Deliver each as a `.dc.html` mockup with the same prop pattern as Phase 1 (`dark` enum, `device`
  enum `iphone`/`ipad`, plus per-screen `state` props). One file per screen (or per closely-related
  group), named `iOS <Name>.dc.html`.

---

## Part 1 — Remaining iPhone screens

### Auth
1. **iOS Login** — email + password sign-in and sign-up (segmented or toggled), "Sign in with Apple"
   button (primary on iOS), forgot-password link, weak-password inline validation. Also a "Continue
   as guest" path (the app currently uses anonymous auth). Branded header with the app glyph.

### Receipts
2. **iOS Receipt Detail** — a saved receipt: store + date header, the line-item list (emoji tile,
   name, `Category · qty`, price), and a totals block (Subtotal, Discount in green, incl. VAT,
   extra charges, **Total**). Edit + delete actions. Present as a pushed screen and as an iPad detail
   pane. (Note: the app stores **no receipt image**, so no image viewer needed.)
3. **iOS Manual Entry** — add a receipt by hand: store, date, then add/edit line items (name,
   category, qty, price) reusing the Review sheet's item card; running total; Save.

### Categories
4. **iOS Category Picker** — full-screen category chooser as a **3-column card grid** (emoji + name,
   groups first then sub-categories), with a "Your categories" section and a "＋ New category" tile.
5. **iOS Custom Category** — create/edit a custom category: name field, emoji grid picker, color
   swatch row (the app's muted palette), free/premium cap note (3 free / 10 premium), delete.
6. **iOS Category Memory** — the "remember this name → category?" propagate sheet shown after a
   category change (apply to this item only / all matching past & future), a native action sheet or
   bottom sheet.
7. **iOS Category Transactions** — a sheet listing all line items in one category for the period
   (emoji header + total, then item rows), reachable by tapping a category in Insights/History.

### History search & filters
8. **iOS History Search** — active search field (native `.searchable` look) with results, plus the
   empty **Quick-find** state (recent searches, top stores, top categories chips).
9. **iOS History Filters** — the filter-chip destinations from the History header: **Sort** (menu:
   newest, oldest, price high/low, name), **Category** (multi-select list), and **Price range**
   (a min–max slider sheet).
10. **iOS Date Range** — the "Custom range…" picker: a single-month paged calendar with start/end
    selection and big Cancel/Apply (matches the Android hand-rolled calendar, not the Material one).

### Insights (extra cards)
11. **iOS Insights — income/recurring cards** — designs for the 5 money cards to add to the Insights
    scroll: Income-vs-Spending, Savings-rate ring, Fixed-vs-Flexible split, Upcoming bills, Income by
    source. Plus **Highlights** (narrative callouts), **Biggest purchases**, and the **Customize
    sections** sheet (show/hide + reorder). Match the existing Insights card styling.

### Store / trends
12. **iOS Store Transactions** — tapping a store in "Top stores" opens a sheet: store avatar + total,
    then that store's receipts for the period.

### Settings & system
13. **iOS Notifications** — notification preferences (budget alerts, weekly summary, large-purchase
    alerts as toggles) + an **Alerts inbox** list.
14. **iOS Support & About** — help/FAQ links, contact, privacy policy, terms, version, and the
    hidden 11-tap tester-premium gesture target.
15. **iOS Biometric Lock** — Face ID app-lock screen (locked state with an "Unlock" affordance).
16. **iOS Widgets** — the in-app widget picker/gallery (widget types × sizes) shown from Account →
    Widgets; plus the WidgetKit widget faces themselves (small/medium: spend total, budget ring,
    recent receipts).

### Empty states
17. **iOS Empty States** — first-run/empty variants for Home (no receipts), History, Insights, and
    Budget (no budget set), consistent with `ContentUnavailableView` styling.

---

## Part 2 — iPad / tablet versions

The app already runs adaptively (compact = tab bar, regular = `NavigationSplitView` sidebar). Phase 1
mockups **already include iPad layouts** for Home, History, Insights, Budget, and Account — those can
be built from the existing files. This phase needs iPad designs for everything else.

**iPad conventions:**
- **Two- or three-column** `NavigationSplitView`: persistent sidebar (Home · History · Scan ·
  Insights · Budget + the account row), a middle list column where it helps (History receipts,
  Insights sections, Budget categories), and a detail pane.
- Multi-column content grids on the wide detail pane; sheets become **centered dialogs / popovers**
  (not full-width bottom sheets). Support Split View / Slide Over widths and both orientations.

**iPad layouts still needed:**
1. **iOS Scan — iPad** — capture + review as a centered document-scanner panel / dialog rather than a
   full-screen phone camera; review as a centered sheet.
2. **iOS Paywall — iPad** — centered modal card (not full-height sheet), features + plans side by side.
3. **iOS Onboarding — iPad** — centered content with the illustration and text balanced for the wider
   canvas; optional two-column (art left, copy right).
4. **iPad detail panes** for the Part 1 screens that have a natural detail view: Receipt Detail,
   Category Picker, Category Transactions, Store Transactions, Notifications, Support & About — shown
   in the split-view detail column.
5. **iOS Login — iPad** — centered auth card on a branded background.

---

## Priority order (suggested)

1. Login (unblocks real accounts) · Receipt Detail (completes the core loop)
2. Category Picker + Custom Category (used everywhere)
3. History Search/Filters/Date Range
4. Insights extra cards · Store/Category transaction sheets
5. Notifications · Support/About · Biometric lock · Widgets
6. All iPad layouts
