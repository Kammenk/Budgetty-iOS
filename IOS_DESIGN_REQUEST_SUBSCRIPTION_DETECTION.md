# Budgetty iOS — Subscription detection

**Design brief for Claude design.** Produce the visual mockups for
**Subscription detection**: the app mines the user's own spending history to
auto-surface **recurring merchants** (subscriptions & regular bills) and flags
likely **price hikes**, on-device. **Android gets the identical feature** (Android
repo's `SUBSCRIPTION_DETECTION_DESIGN_REQUEST.md`); this brief renders it in the iOS
**Liquid Glass** language for a native SwiftUI build. Keep behavioral parity.

Deliver **light + dark**, **iPhone**, plus **iPad** where noted. Mockups as
HTML/CSS in the Budgetty iOS design project — match the **Insights** screen most
closely, since the entry point lives there.

---

## What this is
An on-device heuristic groups transactions by **normalized merchant name** and finds
**repeating charges at a regular cadence** (monthly ±a few days, or yearly) with
similar amounts (≥3 occurrences). Each detected subscription has: **merchant name +
tile**, **typical amount**, **cadence** (monthly / yearly), **last charge**, **next
expected date**, and a **price-change flag** when the latest charge differs from prior.

Plays to Budgetty's receipt strength — dated, merchant-tagged spending we already
have, grouped into *"Netflix €13.99/month, up €2 since March."*

## Gating (design the teaser)
**Premium feature.** Free users see a **teaser** — how many we found + a **locked
list** → paywall. Premium unlocks the full list, price-hike flags, and the
"Track as bill" action. Design both the **unlocked** and the **locked/teaser** entry.

## Placement & treatment
Entry point is a **"Subscriptions" card on Insights**; the full list is its own
screen pushed from there; tapping a row opens a **detail** sheet. Cards/rows are
quiet content; reserve Liquid Glass *material* for the paywall/teaser chrome and
primary CTAs.

- **iPhone:** Insights card → pushed list → detail sheet.
- **iPad:** Insights card in the adaptive grid; list + detail can sit side-by-side or as a centered sheet.

## Screens / states to draw
1. **Insights entry card — Premium:** *"6 subscriptions · €68/month"* + top 2–3 merchants preview + chevron.
2. **Insights entry card — free (teaser):** *"We found 6 recurring charges"*, list **blurred/locked**, **Unlock** CTA.
3. **Subscriptions list (Premium):** rows — merchant tile, **€amount**, cadence,
   **next ~{date}**, a **price-up badge** where flagged; monthly total at top.
4. **Subscription detail:** charge **history** (dated rows and/or a small amount
   sparkline), a **price-hike callout** (*"Up €2.00 since March"*), actions
   **Track as bill** / **Ignore**.
5. **Empty / not-enough-history:** *"We'll spot recurring charges as you add more receipts"* — intentional, not an error.
6. **Ignored:** how a dismissed subscription reads + how to restore it.

## Copy reference
- **Subscriptions**, **Detected subscriptions**
- *"6 subscriptions · €68/month"*, *"€13.99/month"*, **Yearly**, *"Next ~12 Aug"*
- Price flag: *"Up €2.00 since March"*
- Actions: **Track as bill**, **Ignore**, **Restore**
- Paywall: **Unlock subscription tracking**
- Empty: *"We'll spot recurring charges as you add more receipts"*
- Amounts use the trailing currency **suffix**.

## States to make sure the mockups cover
- Premium entry card **and** the free teaser (locked list).
- Full list with at least one **price-up** badge.
- Detail with charge history + price-hike callout + the two actions.
- Empty state and an ignored/restored affordance.
- **Light and dark**, **iPhone**, and an **iPad** rendering of the list + detail.

## Constraints / keep intact
- **Liquid Glass restraint** — glass on paywall/teaser + CTAs; content rows stay quiet.
- **Reuse merchant emoji tiles + accent tokens**; the price-up badge uses the app's warning amber/red.
- **16-language tolerance**; never design to English width.
- On-device only — no "connect your bank," no network; framed around receipts/transactions we already have.

---

*Source of truth for content & behavior: the Android repo's
`SUBSCRIPTION_DETECTION_DESIGN_REQUEST.md`. iOS build = on-device clustering over the
existing transactions store; **Track as bill** creates a recurring bill (`isIncome =
false`) that then feeds Safe to spend; list/flags gate on the same `isPremium` check.*
