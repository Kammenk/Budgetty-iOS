# Budgetty iOS — "Safe to spend" until payday

**Design brief for Claude design.** Produce the visual mockups for a new Home
feature: a **"Safe to spend" figure** — one clear number telling the user how much
they can freely spend before their next payday, after what they've already spent
and the bills they still owe this pay-cycle. This is the Monzo/Simple
"safe-to-spend" idea. **Android is getting the identical feature** (see the Android
repo's `SAFE_TO_SPEND_DESIGN_REQUEST.md`); this brief renders it in the iOS
**Liquid Glass** language for a native SwiftUI build. The two platforms must behave
identically (this is a budgeting/cash-flow feature — full parity).

Deliver **light + dark**, **iPhone**, plus **iPad** where noted. Mockups as
HTML/CSS in the Budgetty iOS design project, consistent with the existing Liquid
Glass mockups — match the **iOS Home** and money-flow cards most closely, since
this hero sits at the top of Home.

---

## What this is
**Safe to spend = Income this pay-cycle − Spent so far this cycle − Bills still unpaid this cycle.**
- A **hero number** at the top of the Home screen. Resets every pay-cycle; the
  cycle can start on any day of the month (Budgetty already supports a custom
  "month starts on" day).
- Optional **per-day** secondary: safe-to-spend ÷ days until payday
  (*"€28/day for 9 days"*).
- It's **cash-flow**, distinct from the existing **Budget** (a spending *target*) —
  design it as its own hero, not a restyle of the budget ring.
- **Free feature** (no paywall).

## Placement & treatment
A **prominent hero card at the top of Home**, using the app's signature Liquid
Glass hero treatment (same material family as the existing Home total / money-flow
cards). Big bold amount, muted "Safe to spend" overline, the per-day + "until
{date}" as a quiet caption. Reserve the glass *material* for this hero; keep the
supporting stats as clean content.

- **iPhone:** full-width hero at the top of the Home scroll, above the existing cards.
- **iPad:** the hero anchors the top of the Home column / leads the adaptive grid.

## The states to draw
1. **Healthy** — comfortably positive: *"€420 safe to spend · €28/day · until 1 Aug"*. Positive/green accent within the glass.
2. **Getting low** — little left for the days remaining. Amber tint, gentle caution (*"€40 left for 9 days"*).
3. **Overspent** — negative. Red treatment, *"€65 over — spent more than you have left this cycle."*
4. **Setup / no income yet** — can't compute until income is set. A friendly setup
   state inside the hero: *"Add your income to see what's safe to spend"* with a CTA
   pointing to the **Budget** tab (income lives there). Make it look intentional —
   this is a common first-run state.

## Copy reference
- Overline: **Safe to spend**
- Amount states: *"€420 safe to spend"* / *"€40 left for 9 days"* / *"€65 over"*
- Secondary: *"€28/day"*, *"until 1 Aug"*, *"€65 over — spent more than you have left this cycle"*
- Setup state: *"Add your income to see what's safe to spend"*, CTA *"Add income"*
- Amounts render with the **currency symbol as a trailing suffix** ("420 €" style), matching the rest of the app.

## States to make sure the mockups cover
- All **four** states above (healthy / low / over / setup).
- The **per-day + until-payday** caption present vs absent.
- **Light and dark**, **iPhone**, and an **iPad** rendering of the healthy state + the setup state.

## Constraints / keep intact
- **Liquid Glass restraint:** glass material on the hero card; supporting stats stay quiet content.
- **Reuse the app's tint + surface tokens** and the green/amber/red status language already used for budget/over-budget — don't invent a palette.
- **16-language tolerance** — flexible, wrapping labels; never design to English width.
- Distinct from Budget — coexists with the budget ring, doesn't replace it.

---

*Source of truth for content & behavior: the shared spec in the Android repo's
`SAFE_TO_SPEND_DESIGN_REQUEST.md`, and the implementation building blocks that
already ship on both platforms — pay-cycle windows + days-to-payday (`PayCycle`),
recurring **income** rows (`isIncome`), **unpaid** recurring bills
(`RecurringMath`/`isPaidThisCycle`), and spend-so-far in the Home view model. No new
data model — a new Home view-model derivation + one hero card.*
