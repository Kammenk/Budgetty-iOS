# iOS Design Request — Home & History Android-parity corrections (Liquid Glass)

Source: a 2026-07-15 simulator pass on the iOS build found four places where the iOS UI had
**drifted from Android's shipped behavior**. The app has been corrected on branch
`home-history-android-parity`; these are the matching **mockup** updates so the Liquid Glass
design in the Claude Design project doesn't lag behind the code.

Behavior is fixed by the Android app (reference below) — only the iOS visual language / Liquid
Glass chrome should change. Keep the token set, restraint rules, capsule geometry, light + dark,
and long-translated-string tolerance of the existing `iOS *.dc.html` mockups.

**Android reference implementation** (`/Users/kamenkostov/AndroidStudioProjects/Budgetty`):
- `app/.../ui/home/HomeScreen.kt` → `BudgetProgressCard`
- `app/.../ui/history/HistoryScreen.kt` → `HistoryBudgetsTab`, `BudgetsSummaryCard`, `BudgetsSectionCard`, `BudgetsMoneyRow`

---

## 1. Home — remove the chevron from the "Total spent" period pill (`iOS Home.dc.html`, hero card)

The hero "Total spent" card's top-right period pill (e.g. **"July 2026"**) currently carries a
downward **chevron**, which makes it read as a tappable menu — but it is a **static label**, not a
control (there is no month picker; the period is always the current calendar month).

- **Remove the chevron.** Keep the pill itself — the month/year text in a white-alpha (~20%)
  rounded-8 capsule.
- No dropdown affordance, no tap target.

## 2. Home — Budgets card shows only the *active* period (`iOS Home.dc.html`, Budgets card)

The Budgets card currently renders **both** a Monthly row and a Weekly row. Android's
`BudgetProgressCard` shows a **single active period**, the inverse of the Budget screen's
Monthly/Weekly toggle (there the user *picks* the period; here we just display the active one):

- **Monthly wins if both or neither is set.** Show the Weekly row only when a Weekly budget is
  set **and** no Monthly budget is set.
- One progress row (title = "Monthly" or "Weekly", `spent / limit`, colored progress bar).
- The top-right **"See All"** link is active and navigates to the **Budget** tab.
- Deliver two states: **monthly** (the common case) and **weekly-only**.

## 3. Home — "Recent Receipts › See All" is now active (`iOS Home.dc.html`, receipts section)

Behavioral note only, no visual change: the **"See All"** link on the Recent Receipts header now
routes to the **History** tab. Please reflect it in the interaction spec so it's not drawn as
inert text.

## 4. History — Budgets tab is a money-plan snapshot, not category budgets (`iOS History.dc.html`, Budgets segment)

The History "Budgets" segment currently shows a per-category **budget progress** list. Android's
`HistoryBudgetsTab` instead shows a **read-only snapshot of the money plan** (income + recurring
payments) mirrored from the Budget screen — it is *not* searchable or time-scoped; it reflects the
current plan and links out to Budget to change it. Replace the content with:

- **Summary card** — labelled with the period (**"MONTHLY"**): an **Income** line (`+€X`, good/green),
  a **Recurring bills** line (`−€X`, muted), then a bold **"Left after bills"** total
  (`income − bills`) — green when ≥ 0, red when negative.
- **Income section card** — header "**Income** … `€X / mo`" (monthly-equivalent total). Rows: a 💰
  tile (good-tinted), the source label, a cadence subtitle ("Monthly · 1st"), and a green `+€X`.
- **Recurring payments section card** — header "**Recurring payments** … `€X / mo`". Rows: the bill's
  **category emoji tile**, the label, cadence subtitle, and the `€X` amount.
- **"Manage in Budget →"** link at the bottom → Budget tab.
- **Empty state** — "No budget plan yet" + a "**Set up your budget →**" link to the Budget tab.

**Controls on this tab:** the search field and the receipts/items filter row (Sort / Date /
Category / Price) are **hidden** — a plan snapshot isn't searchable or time-scoped. Only the
Receipts / Items / Budgets mode toggle remains above the content. Please draw the Budgets tab this
way (no search bar, no filter chips).

**Optional further parity (not done):** Android also puts a single **period chip** (a date-range
dropdown) in the now-empty filter slot, which scales the summary card's income/bills. iOS shows a
fixed **MONTHLY** summary instead — adding a functional period selector would need the date-range
scaling infrastructure iOS doesn't yet have, so it's deferred. A mockup for it isn't needed unless
we decide to build that scaling.
