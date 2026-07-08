# iOS Design Request — iPad Landscape + Native Navigation Rework

Follow-up to `IOS_DESIGN_REQUEST.md` and `IOS_DESIGN_REQUEST_PHASE2.md`. Those established the
iPhone screens and a first iPad pass built around a `NavigationSplitView` sidebar. This request does
two connected things:

1. **Moves the navigation to Apple's current tab-app convention** — `TabView` +
   `.tabViewStyle(.sidebarAdaptable)` — because the app's four destinations are **peer tabs**, not a
   content hierarchy. The persistent sidebar (and the dashboard card inside it) is the least
   iOS-idiomatic thing in the app today. **Goal, stated by the product owner: the app must look 100%
   iOS-native, nothing custom or Android/web-like.**
2. **Adds explicit iPad *landscape* compositions** for every screen. Today's screens only cap width;
   landscape is where iPad should earn its space (multi-column dashboards + master–detail panes).

Please deliver mockups for **both orientations** so we can build against them.

---

## Conventions (apply to every screen)

- **iOS-native, Apple HIG.** Reuse the exact token block from the Phase 1/2 mockups: grouped bg
  `#F2F2F7`/`#000`, card `#FFF`/`#1C1C1E`, label levels, `--tint` violet `#6650A4`/`#BFA8FF`,
  `--good/--warn/--bad`, hero gradient `#5E4CAB→#7B5AC8→#9A6FE0`. Keep the 46-category emoji/colors.
- **SF Symbols**, native sheets with grabbers + detents, inset-grouped `List`, large nav titles,
  `.regularMaterial` bars, safe-area aware, **light + dark**.
- **Prop pattern:** extend each existing `iOS <Name>.dc.html` to accept a new **`orientation` enum
  (`portrait` / `landscape`)** alongside the existing `device` (`iphone`/`ipad`) and `dark` props.
  Landscape only needs to differ on `device=ipad` (see iPhone note at the end).
- **Content max widths:** dashboards center at ~980–1100pt; readable single columns at ~720pt. Never
  let a card stretch edge-to-edge across a 1366pt canvas.

---

## Part 1 — The navigation shell (this is the priority)

Replace the always-open sidebar with the **adaptive tab bar**:

### iPhone (compact) — both orientations
- Standard **system bottom `TabView`**: Home · History · Insights · Budget (SF Symbols, no custom
  chrome, no raised center button).
- **Scan** is a primary *action*, not a browsable tab. Recommended treatment (please mock the first,
  show the second as an alt):
  1. **iOS 26 `tabViewBottomAccessory`** — a tinted "Scan receipt" pill (camera glyph) that floats
     just above the tab bar, always reachable. This is the cleanest native home for a persistent
     create-action.
  2. **Alt:** a camera button in the top-trailing nav bar of each tab.
- Landscape iPhone: same layout, tab bar shrinks to the compact landscape bar (system behavior).

### iPad (regular) — portrait and landscape
- **`.sidebarAdaptable` `TabView`:** Apple's **floating top tab bar** (Home · History · Insights ·
  Budget) with the expand control that morphs it into a **left sidebar** — exactly like Music / News
  / App Store on iPadOS 26.
- **Collapsed (default):** floating top tab bar, full-width content beneath.
- **Expanded sidebar:** a **plain `Label` list** (icon + title) in `.sidebar` style — **no dashboard
  card in the sidebar.** The old `SidebarSummary` violet card moves into the **Home** screen
  (see Part 2). Sidebar footer may hold Account (avatar) + Scan as a prominent item.
- **Scan on iPad:** a prominent camera button in the tab bar's trailing accessory / top-trailing nav
  bar (and a Scan item at the top of the expanded sidebar). Presented as a centered document panel
  (per Phase 2), never a full-bleed sheet.
- Show the **Account** entry point (avatar, top-trailing) in every composition.

Deliver as **`iOS Navigation Shell.dc.html`** with props `device`, `orientation`, `dark`, and a
`state` enum (`tabbar` / `sidebar-expanded`) so we can see both iPad modes.

---

## Part 2 — Per-screen landscape (iPad) compositions

For each, portrait = the multi-column layout we already build; **landscape = wider, and uses
master–detail where the screen has a natural detail.** All beneath the floating top tab bar.

1. **Home — landscape.** Top: the **hero "Total spent" card** and the **Budgets** card *side by
   side* (hero ~60% / budgets ~40%). Below: a 2–3 column row — **Recent Receipts** list + a
   secondary column (e.g. this-month **Top categories** or quick stats). The relocated summary lives
   here as the hero, not in the sidebar. Center the whole dashboard ~1100pt.

2. **History — landscape → two-pane master–detail (the big iPad win).** Left **master** column
   (~360–400pt): the search field + segmented Receipts/Items/Budgets + filter chips + the
   day-grouped list. Right **detail** pane: the selected receipt's full detail (or an empty
   "Select a receipt" state). Tapping a row updates the right pane instead of pushing. Portrait stays
   single readable column (720pt) with push navigation. This is the Mail/Notes pattern and is the
   most iOS-native use of landscape.

3. **Insights — landscape.** 2–3 column masonry of the existing cards. The **Breakdown donut** gets
   a dedicated wider tile with the legend *beside* the chart (not under it). Trend chart spans wider.
   Drill-downs (category / store transactions) may open as a right-hand detail pane rather than a
   sheet when in landscape. Center ~1100pt.

4. **Budget — landscape.** Overall budget card wide across the top; **Income** and **Recurring** as
   two columns; **Category Budgets** grid at **5–6 columns**. Active sub-budgets full-width band.
   Center ~1100pt.

5. **Receipt Detail — landscape.** Primarily the right-hand detail pane of History (see #2); also
   valid as a standalone centered readable column (~720pt) when reached from Home.

6. **Scan review — landscape.** Centered document panel: captured-receipt summary + the editable
   item list in a **two-column** arrangement (details/totals left, items right) so the tall item list
   doesn't force scrolling on a short landscape canvas. Save pinned.

7. **Paywall — landscape.** Centered modal card: features on the left, the Yearly/Monthly plan cards
   + CTA on the right (side by side, not stacked).

8. **Account & settings — landscape.** Keep the inset-grouped `List`; in landscape present as a
   **two-column settings split** (categories list left, selected pane right) like iPad Settings, or
   a centered readable list (~720pt) if simpler. Please mock the split.

9. **Onboarding / Login — landscape.** Centered content balanced for the wide short canvas —
   illustration/brand on one side, controls on the other.

---

## Part 3 — iPhone landscape

No bespoke design needed: iPhone stays the **single-column compact layout** in landscape (system tab
bar behavior). The only screen worth a landscape look is **Scan review** (two-column as in #6, scaled
down) and the **camera capture** framing. Note these, don't produce full sets.

---

## Deliverables checklist

- [ ] `iOS Navigation Shell.dc.html` — adaptive tab bar (iPhone bottom + Scan accessory; iPad
      floating top bar + expandable sidebar), props `device` / `orientation` / `dark` / `state`.
- [ ] Landscape variants (via the new `orientation=landscape` prop) for Home, History (two-pane),
      Insights, Budget, Receipt Detail, Scan review, Paywall, Account, Onboarding/Login.
- [ ] Confirm the sidebar is a plain Label list (no dashboard card) and Scan's placement.
- [ ] Light + dark for every composition.

Design project: **`5b8c8470-38ec-49d0-b332-b27a9000b4b0`** ("Budgetty app design brief"). Add these to
that project alongside the existing `iOS *.dc.html` files.
