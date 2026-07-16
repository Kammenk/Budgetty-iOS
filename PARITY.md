# Budgetty feature parity — Android ⇄ iOS

One row per feature that exists on one platform but not (yet) the other. Read this at the
start of any porting session; update `Status` when a port lands, and append a new section
whenever a feature merges in either repo.

**How to use (for Claude sessions in either repo)**

- **Android repo (reference implementation):** `/Users/kamenkostov/AndroidStudioProjects/Budgetty`
  — `CHANGELOG.md` describes each release; tags `v10.2.0`, `v10.3.0`, `v10.4.0`… mark them
  (`git -C <android> log v10.3.0..v10.4.0` / `git show <commit>` for exact diffs).
- **This repo = the iOS port** (SwiftUI, iOS 26 Liquid Glass). Shared Firebase backend
  `budgetty-96a3d`; the Cloud Functions live in the Android repo's `functions/` and serve
  **both** apps — never duplicate extraction/prompt logic client-side.
- **Port behavior, not UI.** The spec is Android's ViewModels / repositories / data layer.
  iOS visuals follow the Liquid Glass mockups in the Claude Design project — do not copy
  Compose layouts. If a new feature has no iOS mockup, request one (see
  `IOS_DESIGN_REQUEST_*.md` precedent) or adapt the nearest Liquid Glass pattern.
- **Never re-translate strings.** Android `app/src/main/res/values-*/strings.xml` holds 21
  finished locales at full parity — convert mechanically.
- **Workflow:** the Android-side session appends a port brief here when a feature merges;
  the iOS-side session ports it and flips `Status: PORTED (commit)`. Same in reverse for
  iOS-first features.

**Baseline:** iOS reached feature parity with Android on **2026-07-07** (all Phase 1+2
screens, iPad adaptive + landscape, StoreKit 2). Everything below is drift since then.

---

## Android → iOS (pending)

> **Design status 2026-07-14:** `IOS_DESIGN_REQUEST_PARITY.md` (repo root) requests the Liquid
> Glass mockups for every item below that needs one (§5 Home bills, §8 Insights cards/toggle,
> §9 Home customize, §4 quota states, §2 warning dialogs, §10 widgets-optional). Implementation
> of those waits on the mockups; §§1/3/6/7 need no design and can start any time.

### 1. Category taxonomy catch-up — Video Games, Investments, Tips, Delivery + emoji refresh
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — all 4 categories + the 10.2.0 12-emoji refresh; insert-missing seed covers existing installs
**Android:** 10.2.0 (2026-07-08) added Video Games + Investments and refreshed 12 emojis
with muted mockup-hue colors; commit `5eb7592` (2026-07-12) added **Tips** and **Delivery**
so scanned fee/tip line items get real categories.
**Behavior rules:**
- Video Games: normal category, included in the scan enum (server side already deployed).
- Investments: recurring/manual only — **excluded** from the scan enum.
- Tips / Delivery: exist so the extractor's fee/tip line items land somewhere real.
- The server already emits these category names to BOTH apps — until the iOS list matches,
  such items fall back to Other (or worse, fail to map). This is the urgent half.
- Android re-seeds categories on DB open (`onOpen` → `seedCategories`, insert-missing, never
  REPLACE) so existing installs pick up new categories; iOS needs the equivalent for
  existing local stores.
**Android refs:** `app/src/main/java/com/budgetty/app/category/Categories.kt` (canonical
50-cat set, 7 groups + Other), `git show 5eb7592`.
**iOS refs:** `Budgetty/Category/Categories.swift`.
**Update 2026-07-14:** Android localized all 4 names + the delivery/tip line-item labels
(merge `eb9a1b7`: `cat_video_games`/`cat_investments`/`cat_tips`/`cat_delivery` +
`upload_charge_delivery`/`upload_charge_tip` across all 21 values files, display mapping in
`ui/util/CategoryNames.kt`) — when iOS localizes (§6), reuse those finished translations.

### 2. Guided document-scanner capture + dropped-line guard
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — VisionKit doc scanner + blocking dropped-line alert + the soft over-read notice
**Android:** 10.3.0 (2026-07-11), merge `606f0ea`.
**Behavior rules:**
- Capture step uses a guided document scanner (edge detection, deskew, de-glare,
  review/retake) instead of the plain camera; plain camera kept as fallback. iOS
  equivalent: VisionKit `VNDocumentCameraViewController` — do NOT port ML Kit specifics.
- **Dropped-line guard (portable logic):** after extraction, if the sum of item gross
  amounts < the receipt's printed subtotal, show a **blocking** "double-check your items"
  prompt before saving. This is distinct from (and in addition to) the older soft
  price-mismatch notice that shipped in the 07-07 baseline.
**Android refs:** `app/src/main/java/com/budgetty/app/ui/upload/UploadScreen.kt`,
`ui/upload/UploadViewModel.kt`, `data/ingest/ParsedReceipt.kt` (guard fields);
`git diff v10.2.0 v10.3.0`.
**iOS refs:** `Budgetty/Scenes/Scan/` (ReviewView.swift, ReceiptDraft.swift).
**Strings:** +2 (see Android changelog 10.3.0).
**Also (verified 2026-07-14):** iOS has NO price-mismatch messaging at all — not even the
older **soft** PriceMismatchNotice from the 07-07 baseline (grep "mismatch/double-check" = 0
hits; the extractor silently absorbs gaps into extraCharges). Port both tiers together.

### 3. Delivery/tip line items + extra-charges add-on in totals math
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — deliveryAndFees/tip decoded, charge line items materialized, residual math aligned. (Was: PARTIALLY PRESENT — iOS already carried `extraCharges` in the
model, backup, and draft totals (`ReceiptDraft.total = subtotal − discount + additiveCharges`),
derived as the **residual gap** to the printed total in `ReceiptExtractor.swift`. What's missing
is only the `5eb7592` upgrade: decode the new `deliveryAndFees`/`tip` DTO fields, materialize
them as visible "Delivery & fees" / "Tip" line items (needs §1's Tips/Delivery categories
first), and compute extra-charges as the residual after those to avoid double-counting.
The shared server ALREADY returned these fields to iOS scans.)
**Android:** commit `5eb7592` (2026-07-12, shipped in the 10.4.0 build);
server change in `functions/receiptPrompt.js` is deployed (affects both apps today).
**Behavior rules:**
- Extractor now itemizes delivery fees and tips as line items (→ Delivery/Tips categories).
- Totals math (Android DB v17 semantics): headline = `paid` (the printed grand total);
  discounts are netted into every shown total (`paidAdjustmentOf`); delivery/fees/tip are
  an **additive** extra-charges component on top of item sum (`additiveChargesOf`), like
  VAT-on-top (`taxOnTop`) before it. Item sum + tax-on-top + extra charges − discount
  should reconcile to the printed total.
- Verify iOS response decoding tolerates/uses the new DTO fields
  (Android: `data/remote/ReceiptDtos.kt` gained 7 lines).
**Android refs:** `git show 5eb7592` — `data/ingest/HaikuReceiptExtractor.kt` (extraction
client), `data/remote/ReceiptDtos.kt`, `ui/upload/UploadViewModel.kt`.
**iOS refs:** `Budgetty/Data/Remote/ReceiptAPI.swift`, `Scenes/Scan/ReceiptDraft.swift`,
`Scenes/Receipt/ReceiptDetailView.swift`.

### 4. Free-scan quota: 10 scans on the free tier
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — ScanQuota (10 lifetime, consumed on finalize, reset on account deletion) + capture-screen caption/lock states + paywall trigger.
**Android:** quota raised to 10 in `5eb7592`; enforcement in
`app/src/main/java/com/budgetty/app/data/quota/ScanQuota.kt`. Exact semantics (verified
2026-07-14): FREE_LIMIT = 10 is a **lifetime** total, no monthly reset; a scan is consumed
only when the receipt is **finalized/saved** (failed reads and abandoned reviews don't
count); the counter clears only on account deletion. (Known Android caveat: quota is
stored device-level, not per-user — an accepted follow-up there.)
**iOS refs:** none found — likely new code near the scan entry point + paywall trigger.

### 5. Recurring bills on the Home summary card
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — hero-card planned strip per the updated iOS Home mockup
**Android:** 10.4.0 (2026-07-14), merge `fa2ef68` (feature commit `326845b`).
**Behavior rules:**
- "Total spent" card pairs receipt-backed spending with planned recurring bills: a slim
  spent-vs-planned strip, a "Spent" line, a "Bills · planned" line, and a combined
  "With bills" total.
- Bills are clearly marked *planned* (not yet spent); current month only; card collapses
  to the plain total when the user has no recurring bills; large amounts scroll instead
  of truncating.
**Android refs:** `app/src/main/java/com/budgetty/app/ui/home/HomeScreen.kt` (+354),
`ui/home/HomeViewModel.kt`; design = Claude Design "1b planned strip" mockup (Android
Material — request/adapt a Liquid Glass variant for iOS Home).
**Strings:** +3 (changelog 10.4.0).

### 6. Localization — iOS is English-only
**Status:** PORTED `b49dd68` (2026-07-15, sim-verified in Bulgarian) — Localizable.xcstrings, 182 keys × 21 locales converted from Android + cat_* display names + plurals; 69 iOS-only literals remain English (see `LOCALIZATION_TODO.md`)
**Android:** 21 languages at full string parity (commit `f7d2677`), 19 currencies with
region auto-detect.
**Port plan:** introduce a String Catalog, extract hard-coded UI strings, then map
Android keys → iOS keys and convert the 21 finished locales from
`app/src/main/res/values-*/strings.xml` mechanically. Biggest single parity item; do it
before porting features that add strings, or every port doubles the extraction work.

### 7. Unlimited premium custom categories
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — `maxCustomLimit = Int.max`, sheet copy reworded
**Android:** `5eb7592` (2026-07-12) — premium custom categories now **unlimited**
(`MAX_CUSTOM_LIMIT = Int.MAX_VALUE`); free stays at 3.
**iOS refs:** `Budgetty/Category/Categories.swift:28-29`,
`Scenes/Category/CustomCategorySheet.swift` (cap copy at lines ~121-122 mentions the 10-cap —
reword to "unlimited" for premium).

### 8. Insights: missing sections + breakdown toggle + Avg/day stat
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — Highlights, Period comparison, Budget-vs-actual, Biggest purchases, Groups↔All breakdown toggle, Avg/day tile, on-pace caption (iOS now 10 sections)
**Missing on iOS entirely:** HIGHLIGHTS (incl. spending pace), PERIOD_COMPARISON (vs previous
period cards), BUDGET (budget-vs-actual), BIGGEST_PURCHASES. iOS income bundle does cover all
5 income cards (vs-spending, savings rate, fixed/flexible, upcoming bills, by source ✓).
**Also missing:** Breakdown card's all-categories ↔ groups toggle (Android `BreakdownCard` +
`groupOf`, 2026-07-05; iOS donut is groups-only) and the **Avg/day** stat tile (iOS statGrid
has Total spent / Receipts / Avg-per-receipt / Saved only).
**Android refs:** `ui/insights/InsightsSection.kt`, `ui/insights/InsightsScreen.kt`.
**iOS refs:** `Scenes/Insights/InsightsView.swift`, `InsightsCustomize.swift`.
**Design:** Android mockups exist (`InsightsBiggestBills`, `InsightsScreen Variants`, …);
check `iOS Insights Extra Cards.dc.html` for LG coverage, request variants for the rest.

### 9. Home "Customize sections" (show/hide + reorder)
**Status:** PORTED `9f08eef` (2026-07-15, sim-verified iPhone 17 Pro) — HomeCustomize sheet + header pill; week-comparison card added, hidden by default
**Android:** `ui/home/HomeSection.kt` + settings-persisted order/hidden set, phone-only by
design. Mirror the existing iOS `InsightsCustomize` pattern.

### 10. Widgets: 1 type on iOS vs 3 on Android
**Status:** PORTED (2026-07-15, build-verified) — 3 widget types × 2 sizes per the iOS Widgets mockup: Spend Total (spend + top categories), Budget Ring, Recent Receipts; snapshot extended with top categories + receipt count
small+medium). Android has 3 widget types × 2 sizes (Jetpack Glance, 2026-06-30).
Low priority; decide which two remaining types are worth WidgetKit equivalents.

---

## Android → iOS (in flight on Android — do NOT port yet)

- **Insights setup questionnaire** — ✅ **PORTED to iOS 2026-07-16** (branch `insights-setup-quiz`).
  Post-signup one-time setup quiz: 6 questions + a currency step + closing summary (8 screens),
  armed at sign-up (`SettingsKey.quizPending`), gated in `BudgettyApp` between Login and RootView.
  `Scenes/Onboarding/InsightsQuiz.swift` (model + answer→section mapping, adapted to the coarser
  iOS `InsightSection`) and `InsightsQuizView.swift` (Liquid Glass v2 UI, from mockup
  `iOS Insights Setup.dc.html`). Finish applies hidden/order + seeds currency/income/monthly
  budget; skip just clears the flag. Sim-verified iPhone (goal/currency/income-reveal/done).
  **Localized 2026-07-16** — 55 new keys × 15 target locales added to `Localizable.xcstrings`
  (413 keys total), terminology matched to the existing glossary; sim-verified in German
  (`Frage %lld von 7`) and Swedish (`Inkomst inställd — 2 400,00 €/månad`).
- **Per-user local data isolation** — one local DB file per Firebase uid (Android
  `UserDatabaseManager`), fixing cross-account data bleed on shared devices. Same branch.
  When it merges: check whether the iOS local store has the same bleed (receipt data was
  account-agnostic on Android; iOS likely mirrors that).
- **Account trim + full paywall benefit list + no AI wording** — Android branch
  `account-paywall-cleanup` (`6547e73` code, `af23d0f` onboarding AI, `6df1ef9` paywall
  compact-height; emulator-verified en+de on Pixel_6 + Pixel_Tablet, **not merged**).
  ⚠️ **Do not mirror mechanically — the iOS side of every point below differs.** iOS findings
  spot-checked 2026-07-16 against this repo.

  **a. Inert toggles — applies, except Face ID.** Android deleted Push notifications /
  Biometric / Analytics because each wrote a boolean nothing ever read.
  - `Notifications` (`Scenes/Account/AccountView.swift:148`) — **inert here too**: no
    `UNUserNotificationCenter` / `requestAuthorization` anywhere → remove.
  - `Analytics` (`AccountView.swift:230`) — **inert here too**: no analytics SDK → remove.
  - `Face ID` (`AccountView.swift:226`) — ⚠️ **REAL on iOS. Keep it.** `LAContext` +
    `evaluatePolicy` in `Scenes/Lock/BiometricLockView.swift`, wired via `LockGate { RootView() }`
    (`BudgettyApp.swift:81`). Android had no biometric dependency at all — this is a genuine
    platform divergence, not drift. So iOS **keeps a Privacy & Security section** (Face ID only)
    where Android deleted it, and `iOS Biometric Lock.dc.html` stays live where the Android
    `BiometricLockScreen.dc.html` is being retired.
  - Currency already sits under Preferences on iOS (`AccountView.swift:152`) → no move needed.
  - `Contact support` → **"Contact us"** + second line "Report an issue, suggest a feature, or
    just say hello", and the mail subject goes neutral ("Budgetty feedback"). ⚠️ On iOS a key IS
    its English text, so this **renames a key** — migrate all 16 locale entries in
    `Localizable.xcstrings`, don't strand the old one (see §6 mechanics).

  **b. Paywall — iOS is in worse shape than Android was.** `Scenes/Paywall/PaywallView.swift:36-40`
  already uses the title+subtitle `Feature` shape Android just adopted, but **3 of its 5 claims
  are wrong**:
  - "Cloud backup & sync / Your data safe and on all devices" — **does not exist** (same phantom
    Android had). Product decision was to **keep it, demoted to a muted "Coming soon" row** with
    a clock instead of a check — not to delete it.
  - "Home screen widgets / Spending at a glance" — **not premium-gated** on iOS (no premium check
    near the widget code) and free on Android. This advertises a free feature as paid → drop it.
  - "10 custom categories / vs. 3 on the free plan" — **factually wrong**:
    `Categories.maxCustomLimit = Int.max` (`Category/Categories.swift:29`) = unlimited. It both
    undersells the product and quotes a number that doesn't exist.
  - "Unlimited scans" ✅ real (`ScanQuota.freeLimit = 10`, `App/Settings.swift:31`) and "Accent
    color themes" ✅ real — but iOS has **8 tints** vs Android's 3 (Sage/Ocean/Plum), so Android's
    `paywall_benefit_themes_detail` does **not** transfer verbatim.
  - **Recurring bills**: Android's 4th unlock is unlimited recurring bills (free cap 3,
    `RecurringRepository.FREE_RECURRING_LIMIT`). No equivalent cap found on iOS — **confirm the
    gate exists** before listing it, or the same "advertise what you don't enforce" bug appears.
  - The principle worth copying, not the strings: **one shared benefit list** feeding every
    layout, each row = title + the free-tier limit, every number **interpolated from the constant
    that enforces it** so a retuned cap can't leave stale copy.

  **c. Onboarding AI wording — applies as-is.** iOS names AI twice,
  `Scenes/Onboarding/OnboardingView.swift:20` ("AI reads every item & category") and `:22` ("AI
  pulls every line item and assigns a category — you just review."). Android reworded so Budgetty
  itself is the sentence's subject. ⚠️ The **privacy policy's AI limited-use disclosure naming
  Anthropic must stay** — required store disclosure, product copy only.

  **d. Login brand panel.** Android's dropped "Snap a receipt — AI reads it" and "Budget tracking
  & alerts" (alerts were as unimplemented as the notifications toggle — the same phantom sold in
  a second place) and gained a closing "Premium unlocks unlimited scans, categories & bills" line.
  It stays a **pre-auth app pitch, deliberately not a paywall**. Check the iPad login for the same
  AI + alerts wording.

  **Design:** Android's `ACCOUNT_PAYWALL_DESIGN_REQUEST.md` deliberately leaves every `iOS
  *.dc.html` untouched so the mockups keep matching iOS code until this ports. An iOS port needs
  its own request (`IOS_DESIGN_REQUEST_*` precedent) covering `iOS Account`, `iOS Paywall`,
  `iOS Login`, `iOS Support & About` — and, unlike Android, **not** `iOS Biometric Lock`.

## iOS → Android (pending)

### A. Date format preference (Account → Preferences)
**Status:** DONE on Android (Android `b2cc450`, 2026-07-15, build-verified not device-run).
Correction: the tracker's earlier "NOT ON ANDROID" was stale — Android already had the full
preference (`DateFormatOption` enum with 4 options, SettingsStore key, Account picker
`account_date_format`, `AppFormats.datePattern` set in MainActivity, applied by `formatDate()`
on receipt detail + Home rows). The genuine gap was the year-less **short** formatters
(`formatDayMonth`, `formatDayHeader`) using hard-coded patterns, so History day headers ignored
the choice. `b2cc450` adds `DateFormatOption.dayMonthPattern` + `AppFormats.dayMonthPattern` and
routes History day headers, upload/recurring rows, and Insights trend day labels through it.
NB: Android's 4 options (DAY_MONTH_YEAR / DMY_SLASH / MDY_SLASH / ISO) differ from iOS's
(system / dmy / mdy / dots) — no "System" option on Android; not worth reconciling.

---

## Checked — platform-specific / no action

- **Liquid Glass v2 restyle** (iOS design language; Android keeps Material + Dimens tokens)
- **iPad adaptive/landscape work** (Android tablet equivalents already exist)
- **StoreKit 2 vs Play Billing**, **Play In-App Updates** (platform equivalents)
- **Haiku-first extraction tier** — server-side, shelved 2026-07-13, prod flag off
- **Local PDF extractor / PDFBox removal** (`983830f`) — Android internal cleanup
- **ML Kit Document Scanner dependency** — Android-only tech; iOS uses VisionKit (see §2)
- **Design-project mockups with no code on EITHER platform** (checked 2026-07-14):
  `AlertsInboxScreen`, `EditProfileScreen` (Android uses inline name edit instead),
  `ReceiptViewerScreen` (app stores no receipt images) — mockup-only, no parity action.
- **Trend 7-bar padding / donut leader-line % labels** — Android Material visual choices;
  iOS follows its own Liquid Glass mockups.
- **Category rules, custom date range sheet, History tabs+sort+price-range, tester premium
  unlock (11-tap), Insights customize sheet, income/recurring, period stepper** — spot-checked
  2026-07-14, all present on iOS ✓.

---

*Last synced: 2026-07-16 — added the in-flight **Account trim + paywall benefits + no-AI** brief
(Android `account-paywall-cleanup`, unmerged; NB Face ID is real on iOS and must survive that
port, and the iOS paywall independently carries 3 false claims worth fixing whenever it lands).
Previously 2026-07-15: parity batch `9f08eef` ports §§1-5 and 7-9; REMAINING: §6 localization,
§10 widgets-optional, and the Android-side date-format port — Android `main`/`eb9a1b7`
(+ unmerged `insights-questionnaire`) · iOS `android-parity`/`9f08eef`.*
