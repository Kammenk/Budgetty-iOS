# Budgetty iOS — Savings goals

**Design brief for Claude design.** Produce the visual mockups for a new
**Savings goals** feature: the user sets a goal (name, emoji, target amount,
optional target date) and tracks progress with a ring, topping it up with manual
contributions. **Android is getting the identical feature** (Android repo's
`SAVINGS_GOALS_DESIGN_REQUEST.md`); this brief renders it in the iOS **Liquid
Glass** language for a native SwiftUI build. This is a saving/budgeting feature, so
**full behavioral parity** with Android.

Deliver **light + dark**, **iPhone**, plus **iPad** where noted. Mockups as
HTML/CSS in the Budgetty iOS design project — match the **Budget** screen most
closely, since Savings goals live there.

---

## What this is
A motivational, planning-side tracker. Budgetty has **no account balances**, so a
goal is a **manual tracker**: the user adds/withdraws contributions themselves
(there's no wallet to draw from). Keep the tone honest — a savings *tracker*.

A goal = **emoji + name + target amount + optional target date**, and a **saved
amount** built from dated **contributions** (add/withdraw). Derived: **remaining =
target − saved**, **% = saved / target**, and with a target date, *"€X/month to
reach by {date}"* + an on-track / behind hint.

## Gating (design the locked state)
**Capped-free: 1 goal free, unlimited with Premium** — matches the app's existing
freemium caps (recurring bills 3, widgets 2). A free user with one goal who taps
**New goal** hits the paywall. Please design the **locked "New goal"** affordance
(Premium lock + "Unlock unlimited goals").

## Placement & treatment
Savings goals are a **section on the Budget tab**, below the budget / income /
recurring sections. Goal cards are quiet content cards with a **progress ring**;
reserve Liquid Glass *material* for the primary CTA / paywall chrome, not the goal
cards. Tap a card → a **goal detail** sheet.

- **iPhone:** section in the Budget scroll; goal detail as a sheet.
- **iPad:** goal cards in the adaptive grid; detail as a centered sheet (~520pt).

## Screens / states to draw
1. **Savings section — empty:** an inviting *"Set a savings goal"* card + CTA.
2. **One goal in progress:** goal card — emoji chip, name, **progress ring** with %,
   *"€480 of €1,200 · €720 to go"*, optional *"€120/month to reach by Dec"*.
3. **Multiple goals (Premium):** 2–3 cards + a small total-saved summary at the header.
4. **Locked "New goal" (free at cap):** the Premium-locked add affordance + unlock nudge.
5. **Goal detail:** large ring, saved / target / remaining, the **contribution
   history** (dated +/− rows), actions **Add to savings** / **Withdraw** / **Edit** / **Delete**.
6. **Add-to-savings sheet:** amount field (currency **suffix** — "120 €"), optional note + date; a Withdraw variant.
7. **Create / edit goal sheet:** emoji chip picker, name, target amount, optional target date toggle.
8. **Goal reached:** 100% — celebratory *"Goal reached! 🎉"*, ring full.

## Copy reference
- **Savings goals**, **Set a savings goal**, **New goal**
- **Add to savings**, **Withdraw**, **Edit**, **Delete**
- *"€480 of €1,200"*, *"€720 to go"*, *"€120/month to reach by Dec"*
- **Goal reached!** 🎉
- Paywall: **Unlock unlimited goals**
- Amounts use the trailing currency **suffix** ("480 €").

## States to make sure the mockups cover
- Empty / one goal / multiple goals / locked-at-cap.
- Goal detail with contribution history; the add + withdraw sheets; create/edit sheet.
- The **reached** (100%) celebratory state.
- **Light and dark**, **iPhone**, and an **iPad** rendering of the section + goal detail.

## Constraints / keep intact
- **Liquid Glass restraint** — glass on CTA / paywall chrome; goal cards are quiet content cards with the ring.
- **Reuse the emoji chip + accent/green tokens**; don't invent a palette. Contributions/progress use the app's positive **green**.
- **16-language tolerance**; never design to English width.
- Honest framing: a manual tracker, no real balance.

---

*Source of truth for content & behavior: the Android repo's
`SAVINGS_GOALS_DESIGN_REQUEST.md`. iOS build = a new SwiftData `SavingsGoal` +
`SavingsContribution` model + a savings view model; `saved = Σ contributions`;
1-goal free cap gated on the same `isPremium` check as the recurring-bill / widget caps.*
