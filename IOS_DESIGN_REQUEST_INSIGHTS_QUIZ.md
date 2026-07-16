# Budgetty iOS — Insights Setup Questionnaire

**Design brief for Claude design.** Produce the visual mockups for a new first-run flow that iOS doesn't have yet: the **post-signup Insights setup questionnaire**. This already ships on Android (approved + built); this brief ports the *design* to the iOS **Liquid Glass** language so it can then be implemented natively in SwiftUI.

Deliver **light + dark**, **iPhone**, plus **iPad** where noted. Mockups as HTML/CSS in the Budgetty iOS design project, consistent with the existing Liquid Glass mockups — match the **Onboarding** and **Login** screens most closely, since this gate sits right beside them in the first-run flow.

---

## What this flow is

A **one-time, full-screen gate** shown **once, right after a user creates their account** (between sign-up and landing in the app). It asks a short, friendly set of questions and uses the answers to pre-tailor the **Insights** screen (which sections show, and their order) and to optionally seed the user's **currency**, **monthly income**, and **spending budget**. Everything it sets is reversible later in the app, so the tone is light and low-stakes — never a form the user can fail.

- **8 screens total:** 7 setup steps + a closing "you're all set" screen.
- Every step can be **skipped** (Skip clears the gate and drops the user into the app); the closing screen has no Skip.
- Most questions **auto-advance** the instant an option is tapped (brief selected-state flash, then slide to the next step). Two questions reveal an optional amount field and wait for a **Continue** button instead.
- **Back** returns to the previous step (chevron top-left, and hardware/edge back). The first step has nothing to go back to.

Tone: calm, encouraging, money-serious but friendly. Ships in **16 languages**, so **layouts must tolerate long translated strings** — never design to English width; option labels and titles must wrap gracefully.

---

## Shared layout & chrome (applies to every step)

A single **centered content column** on a calm full-screen background that uses the app's ambient Liquid Glass glows (same background treatment as Onboarding/Login). No tab bar, no nav bar — this is a focused gate.

- **iPhone:** column fills the width with standard screen padding; question content sits toward the top.
- **iPad:** column is **width-capped (~520pt) and centered**, and the question block is **vertically centered** in the column (lots of breathing room on the sides).

**Top bar** (fixed height so it never jumps as elements come and go), left→right:
1. **Back chevron** — shown from step 2 onward (hidden on step 1 and on the closing screen).
2. **Segmented progress bar** — **7 thin capsule segments**, equal width, filling the row. Segments up to and including the current step are **accent-filled**; the rest are a quiet outline color. Fill animates as steps advance. (The closing screen shows all 7 filled.)
3. **Skip** — quiet text button, trailing. Shown on all 7 question steps; **hidden on the closing screen**.

**Step header** (shared by all question steps), stacked:
- A small **overline**: "Question X of Y" (e.g. *Question 3 of 7*). On Android this is uppercase tracking; for iOS use a quiet caption in the app's muted label color — designer's call on caps vs. title-case, keep it understated.
- **Title** — large, extra-bold, tight tracking (the question).
- **Subtitle** — one muted supporting line.

**Option cards** (the answers), stacked vertically with small gaps:
- A quiet rounded card (concentric radius), comfortable row height (≈56pt iPhone / ≈64pt iPad), containing: a **rounded-square emoji chip badge** on the leading edge, the **label** (semibold, wraps to 2 lines if needed), and a trailing **check badge** slot.
- **Unselected:** neutral surface card, emoji chip slightly raised from the card, no ring, check hidden (but its slot is reserved so the label never reflows).
- **Selected:** card fills with a **soft accent-tinted surface**, gains a **2pt accent ring**, the emoji chip lightens toward the background, label goes bold, and the **trailing check badge** appears (accent circle, white checkmark).
- Reserve the Liquid Glass *material* for the CTA pill and progress chrome — **option cards are content, keep them as clean tinted cards, not glass** (Liquid Glass restraint: don't over-glass content).

**Primary CTA**, where present (amount steps + closing screen): the app's signature **glass pill button**, full-width, standard button height — reuse the existing `ctaPill` treatment from Onboarding/Paywall.

---

## The 8 screens

Design each as its own mockup (a state of the shared shell above).

### 1 · Goal — *Question 1 of 7* · auto-advances
- **Title:** What's your main goal with Budgetty?
- **Subtitle:** This shapes your Insights — change anytime.
- **Options (4):**
  - 🔍 See where my money goes
  - 🎯 Stick to a budget
  - 📅 Keep bills & subscriptions in check
  - 🪙 Save more each month
- No back chevron (first step). Show one option in its **selected** state in the mockup so the selected treatment is visible.

### 2 · Currency — *Question 2 of 7* · auto-advances
A pick-a-currency list. Same header pattern, then **two labeled groups**:
- **Title:** Which currency do you use?
- **Subtitle:** Used for every amount in the app — change anytime in Account.
- Small uppercase-ish **section label** "Suggested for your region", then **one emphasized pinned row** (the device-region default, e.g. EUR) styled slightly raised.
- Section label "All currencies", then the remaining rows.
- **Currency row:** a compact card (shorter than an option card) with a **symbol badge** (€, £, kr, zł, Kč, lei, etc. — badge shrinks its glyph for 2–3 char symbols), the **currency code** (bold, e.g. EUR), and the **localized currency name** (muted, e.g. *Euro*). Selected state = accent tint + ring, same language as the option cards.
- iOS supports **9 European currencies** (EUR, GBP, CHF, SEK, NOK, DKK, PLN, CZK, RON) — show the pinned one plus a scrolling list of the rest. This step scrolls.

### 3 · Income (+ optional amount) — *Question 3 of 7*
- **Title:** Do you want to track income too?
- **Subtitle:** Income unlocks savings and cash-flow cards.
- **Options (2):**
  - 💰 Yes — income and spending  ← reveals the amount field
  - 🧾 No — just my spending  ← auto-advances
- When **"Yes"** is selected, the card stays selected and an **inline amount field reveals below** (expand + fade), and the step waits for **Continue** (does not auto-advance):
  - Field **label:** Your monthly income (roughly)
  - **Amount input:** big bold number with the **currency symbol as a trailing suffix** (Budgetty renders "2,400 €", never "€2,400"); rounded field with a subtle border; decimal keyboard; empty is fine.
  - **Helper** under it: Optional — you can add exact income sources later.
  - **Continue** glass pill (full width) below.
- **Deliver two mockups:** (a) the two options unselected/one selected; (b) "Yes" selected with the revealed amount field + Continue, showing a sample value like `2,400 €`.

### 4 · Bills — *Question 4 of 7* · auto-advances
- **Title:** Any recurring bills or subscriptions to watch?
- **Subtitle:** Rent, streaming, gym — anything regular.
- **Options (2):**
  - 🔁 Yes, I have recurring payments
  - ✨ Not really

### 5 · Budget (+ optional amount) — *Question 5 of 7*
- **Title:** Do you plan to set a spending budget?
- **Subtitle:** Budgets add progress tracking to Insights.
- **Options (3):**
  - ✅ Yes  ← reveals the amount field
  - 🤔 Maybe later  ← auto-advances
  - ❌ No  ← auto-advances
- **"Yes"** reveals the same inline-amount pattern as step 3:
  - Field **label:** Monthly spending budget
  - **Helper:** Optional — switch to a weekly budget later in the Budget tab.
  - **Continue** pill.
- **Deliver two mockups** again: options state, and "Yes" + amount field state (e.g. `1,500 €`).

### 6 · Detail — *Question 6 of 7* · auto-advances
- **Title:** How much detail do you like?
- **Subtitle:** You can always dig deeper later.
- **Options (2):**
  - 🌅 Just the big picture
  - 🔬 All the details

### 7 · Entry — *Question 7 of 7* · auto-advances
- **Title:** How will you mostly add expenses?
- **Subtitle:** Just curious — it helps us tune things.
- **Options (3):**
  - 📷 Scanning receipts
  - ⌨️ Typing them in
  - 🤝 A bit of both

### 8 · Closing — "You're all set!" (no Skip, no back chevron, all 7 progress segments filled)
A celebratory summary, vertically centered, with the CTA pinned toward the bottom.
- **Celebration glyph:** a rounded-square badge in the accent/primary-container color with a large **🎉**.
- **Title:** You're all set!
- **Body (muted, centered):** Insights are tailored to you — they'll fill in as you add your first receipts.
- **Summary card** — a single rounded surface card, one **row per meaningful answer** (emoji + short semibold label), divided by hairlines. Rows are generated from the answers; design the card with a representative full set, e.g.:
  - 🎯 Budget-focused layout
  - 💱 Currency — EUR
  - 💰 Income set — 2,400 €/month
  - ✅ Monthly budget — 1,500 €
  - 🌅 Big-picture view
- **Footnote (small, muted, centered):** Change anytime in Insights → ⋮ → Customize sections.
- **Primary CTA (glass pill, full width):** Get started
- **Bills hand-off hint** (only shown when the user answered "Yes" to bills) — a small centered semibold line under the CTA: Next: add your recurring bills in the Budget tab
- **Deliver at least one mockup**; optionally a second "minimal answers" variant with a shorter summary card (e.g. only a layout row + "Spending only — income cards off").

---

## Copy reference (all summary-row / label strings)

For the closing card, rows come from these (the amount ones interpolate a formatted value):
- Goal → *Spending-overview layout* / *Budget-focused layout* / *Bills-first layout* / *Savings-focused layout*
- Currency → *Currency — {CODE}*
- Income → *Income set — {amount}/month* (if amount given) / *Income & spending tracked* / *Spending only — income cards off*
- Budget → *Monthly budget — {amount}* (only when an amount was given)
- Bills → *Bills & subscriptions off* (only shown when "Not really")
- Detail → *Big-picture view* / *Detailed view*

Other copy: Skip = **Skip**, Continue = **Continue**, closing CTA = **Get started**, back label = **Back**.

---

## States to make sure the mockups cover
- **Unselected vs. selected** option card (tinted fill, accent ring, emoji-chip lightening, trailing check).
- **Progress bar** at an early step (few filled) and at the closing screen (all filled).
- **Revealed amount field** with the currency-suffix input + Continue (steps 3 and 5).
- **Currency step** scrolling list with the pinned "suggested" row emphasized.
- **Closing screen** with a full summary card, and the conditional **bills hint**.
- Everything in **light and dark**, **iPhone**, and an **iPad** rendering of at least one question step + the currency step + the closing screen (centered ~520pt column).

## Constraints / keep intact
- **Liquid Glass restraint:** glass material only on the CTA pill and the progress/skip chrome; option and summary cards are quiet content cards.
- **Keep the emoji + accent color system;** don't invent a new palette — reuse the app's tint and surface tokens.
- **16-language tolerance** — flexible, wrapping layouts; no fixed English-width labels; titles can be 2–3 lines.
- **Reversible & low-stakes tone** — this pre-fills the same values the in-app Customize-sections menu, Account (currency), and Budget tab edit; nothing here is permanent.

---

*Source of truth for content & behavior: the shipped Android implementation — `app/src/main/java/com/budgetty/app/ui/quiz/InsightsQuiz.kt` (question set, options, answer→section mapping) and `InsightsQuizScreen.kt` (layout, states, animations) in the Budgetty Android repo. This brief captures that flow; the visual language is the iOS Liquid Glass redesign.*
