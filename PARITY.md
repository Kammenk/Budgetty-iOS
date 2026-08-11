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

### 10. Widgets: 3 types on iOS vs 5 on Android
**Status:** PORTED (2026-07-15, build-verified) — 3 widget types × 2 sizes per the iOS Widgets mockup: Spend Total (spend + top categories), Budget Ring, Recent Receipts; snapshot extended with top categories + receipt count
**Corrected 2026-07-22:** the old title ("1 type on iOS vs 3") was stale in both numbers. iOS has 3
(`SpendingWidget`, `BudgetRingWidget`, `RecentReceiptsWidget`); Android has **5** — Budget, Summary,
This Week, Scan, Top Categories. The two missing faces (Scan shortcut, This Week) remain low
priority; decide whether they're worth WidgetKit equivalents. Note the free-tier cap (below) counts
faces, so adding a type widens what a free user can choose between, not how many they can place.

---

### 11. Category split — "Subscriptions & Services" → "Subscriptions" + "Services"
**Status:** PORTED (2026-07-21, sim-verified iPhone 17 Pro incl. the upgrade path)
**Android:** `581302f` (2026-07-21). The sub-category was near-indistinguishable from the group
holding it ("Services & Subscriptions"), so it became two: `Subscriptions` 🔁 (reusing the old slot
in `defs`, which keeps its colour — sub-hues walk the list in order) and `Services` 🧰 (appended, for
the same reason). Group name unchanged.
**⚠️ Why this was urgent:** `functions/receiptPrompt.js` is the SHARED prompt and already lists both
new names, so a deployed function emits categories iOS didn't know — they'd fall back to Other.
**iOS:** `Category/Categories.swift` (defs + `cat_*` key map), `Localizable.xcstrings`
(`cat_subscriptions`/`cat_services` added from Android's finished translations, `cat_subscriptions_services`
retired — 16 locales, no re-translation), and `Data/Migrations.swift` +
`BudgettyApp.prepare(_:)`. The name IS the stored reference, so the migration repoints `Category`,
`LineItem`, `Recurring`, `CategoryRule` and the `CAT:<name>` budget key — the iOS counterpart of
Android's `MIGRATION_17_18`. Everything lands on `Subscriptions`, matching Android. Covered by
`BudgettyTests/MigrationsTests.swift` (4 cases incl. the collision and idempotence).

### 12. Per-user local data isolation
**Status:** PORTED (2026-07-21) — was a live data-bleed bug on iOS
**Android:** `UserDatabaseManager` (on main, v10.5.0) — one Room file per Firebase uid.
**iOS was worse than "not ported":** a single `ModelContainer` was built once in `BudgettyApp.init()`
with no uid at all, so two accounts on one device shared receipts, budgets and categories outright.
**iOS:** `Data/UserStore.swift` — `budgetty-u-<uid>.store` per account, `budgetty-anon.store` when
signed out, containers cached per file, legacy `default.store` adopted by the first signed-in account
(sidecars moved too), and `deleteData(for:)` wired into `AuthModel.deleteAccount()`. The container is
`@State` and swapped in `.onChange(of: auth.uid)`, which also seeds/migrates the newly opened store.
**⚠️ Untested:** the actual two-account switch needs a second Firebase account — verified so far are
the uid-named store on a fresh install and the legacy-store adoption + migration on upgrade.

### 13. Third-party sign-in — Apple ✅, Google ✅
**Status:** DONE 2026-07-21. Apple is iOS-first (no Android counterpart); Google reaches parity with
Android's `AuthRepository` Google flow.

**Apple (done).** Fully native — `AuthenticationServices` + `CryptoKit`, no new dependency:
`Auth/AuthModel.swift` (`prepareAppleRequest`/`signInWithApple`, SHA-256 nonce,
`OAuthProvider.appleCredential`) and a `SignInWithAppleButton` under an "or" divider in
`Scenes/Auth/LoginView.swift`, plus the `com.apple.developer.applesignin` entitlement. New
sign-ups arm the setup quiz via `additionalUserInfo?.isNewUser`, matching Android's `e328102`
behaviour for third-party sign-ups. Apple returns name/email **only on the first authorisation**, so
the display name is captured there or never.
- ⚠️ **Two steps outside the repo, both still open:** the **Apple provider must be enabled in the
  Firebase console** (without it the credential exchange fails `operation-not-allowed`), and the App
  ID needs the Sign In with Apple capability (automatic signing usually registers it on the next
  archive). Verified as far as a simulator allows: the system flow engages and the no-Apple-Account
  path shows friendly copy; the actual round trip needs a real Apple Account.
- ⚠️ Once Google lands, Apple becomes **mandatory** under App Review 4.8 — that direction is now safe.

**Google (done).** Native OAuth 2.0 + PKCE via `ASWebAuthenticationSession` — **no GoogleSignIn
SDK**, keeping the prefer-native convention. `Auth/GoogleOAuth.swift` builds the consent URL from the
`CLIENT_ID`/`REVERSED_CLIENT_ID` already in `GoogleService-Info.plist`, verifies `state`, and
exchanges the code for an ID token; `AuthModel.signInWithGoogle` hands that to
`GoogleAuthProvider.credential`. Only the ID token is used — same as Android's
`GoogleAuthProvider.getCredential(idToken, null)` — and `isNewUser` arms the setup quiz.
- Why not the SDK: it needs `CFBundleURLTypes`, and this app target has **no physical Info.plist**
  (`GENERATE_INFOPLIST_FILE = YES`). `ASWebAuthenticationSession` intercepts its own
  `callbackURLScheme`, so nothing has to be registered and no pbxproj surgery was needed.
- Verified on the simulator up to Google's real sign-in page (client id, redirect URI and PKCE all
  accepted; the page names the project, see below) and the cancel path. The signed-in round trip
  needs a real Google account.
- ⚠️ **Follow-up, Google Cloud console:** the OAuth consent screen has no app name set, so the page
  reads "to continue to **project-773376958569**" instead of "Budgetty". Cosmetic but it looks
  untrustworthy at exactly the wrong moment. Set App name + logo under APIs & Services → OAuth
  consent screen.
- ⚠️ **Follow-up, branding:** Google's mark isn't bundled, so the button is a neutral capsule with an
  SF Symbol rather than Google's branded button. Add the official asset to comply with their
  identity guidelines before public release. Android's `e328102` ("show the setup quiz to Google sign-ups too") therefore has
no iOS counterpart to fix; whenever Google sign-in lands, it needs the same `isNewUser`-based arming
of `SettingsKey.quizPending`.

### 14. Scan guards — two Android checks missing on iOS
**Status:** PORTED 2026-07-22 — `Scenes/Scan/ReceiptExtractor.swift` (`validate`) and
`Scenes/Scan/ReviewView.swift` (`inflatedTotal`). All seven thresholds copied verbatim from Android
so a receipt is judged identically on both platforms; `BudgettyTests/ExtractionGuardTests.swift`
pins them, leaning on the cases that must NOT be rejected. Note iOS was missing a **third** guard the
audit hadn't spotted: the money-sanity overshoot check. Ported alongside.
- **Article-count guard.** Android cross-checks the receipt's printed item count against the parsed
  lines/units (`HaikuReceiptExtractor.validateExtraction`; `1d12a44` fixed it over-rejecting multi-buy
  receipts). iOS decodes the field (`Data/Remote/ReceiptAPI.swift:40` `printedItemCount`) and never
  reads it — that is its only reference in the repo. A genuine under-read is silently accepted.
- **Inflated-total warning.** Android `651b638` warns on Review when the total runs far past the item
  sum *with no printed subtotal* — the dual-currency backstop. iOS's two reconciliation checks in
  `Scenes/Scan/ReviewView.swift` are both gated on `printedSubtotal` being present, so this case shows
  nothing and the gap is absorbed into `extraCharges`.
- NB the dual-currency fix itself (`21a1213`) is **server-side** in the shared prompt — iOS gets it
  free, no action.

### 15. Premium offer — iOS unlocked 2 things, Android 4
**Status:** PORTED 2026-07-22 (iOS branch `android-premium-parity`, sim-verified iPhone 17 Pro)

Not drift in a feature so much as a **hole in the product**, surfaced when the paywall was made
honest on 2026-07-21: once the false rows came out, iOS Premium bought unlimited scans and unlimited
custom categories, and nothing else. Android charges for two more things that simply didn't exist
here. Both were built rather than dropping the claim.

- **Recurring-bill cap.** Android caps free users at `RecurringRepository.FREE_RECURRING_LIMIT` (3)
  bills; income is never capped. iOS now has `RecurringQuota.freeLimit`, enforced on the Budget
  screen: the section header shows "3 / 3" and the Add row becomes an "Upgrade to add more" row.
  Nothing persisted, matching Android — the live bill count is the state, so deleting one frees a
  slot.
- **Accent themes.** Android overrides its Material `primary` per `AccentTheme`
  (Violet/Sage/Ocean/Plum). iOS re-points the `Palette.tint` token — the Liquid Glass spec already
  reserves it for exactly what Android overrides (primary action, active tab, links, selected
  states), so one indirection reaches ~80 call sites. `AppTheme` is `@Observable`, not `@AppStorage`:
  SwiftUI's observation tracking then re-renders every view that read the tint, with no `.id()` reset
  that would pop the user out of the picker mid-change. Sage/Ocean/Plum use **Android's exact hexes**.
  - ⚠️ **The non-obvious part, if you touch this:** the hero card and the CTA capsule carry white
    text, and green at the violet gradient's HSB brightness is far lighter to the eye than violet.
    Copying the mockup's numbers to another hue would have shipped a Sage hero at ~1.6:1 contrast.
    They derive by matching the reference colour's **luminance** instead, so every accent is exactly
    as readable as the one the mockups were drawn for. `AccentTests` holds that floor.
  - Divergence from the mockups: the ambient canvas glows stay violet (decorative, and they sit
    behind content rather than under text).

Also in this pass, though not a parity item: the paywall's plan card hardcoded "€2.50 / month" and
"SAVE 37%" beside a StoreKit-supplied price — arithmetic on €29.99/€3.99 that a re-price in App Store
Connect would have quietly falsified. Both now derive from the loaded products (`PlanPricing`,
unit-tested) and the saving is dropped rather than invented when it can't be computed.

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
- **Per-user local data isolation** — ✅ **PORTED to iOS 2026-07-21**, see §12 above. iOS did have
  the same bleed, and worse (one container, no uid at all).
- **Account trim + full paywall benefit list + no AI wording** — ✅ **PORTED 2026-07-22** (iOS branch
  `android-premium-parity`, sim-verified iPhone 17 Pro). Android side merged as `a8ef389`
  (`6547e73` code, `af23d0f` onboarding AI, `6df1ef9` paywall compact-height). The notes below are
  kept because they record *why* each row went the way it did; the ⚠️ product gap they end on is now
  closed — see §15.
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
  - "Unlimited scans" ✅ real (`ScanQuota.freeLimit = 10`, `App/Settings.swift:31`).
  - ⚠️ **CORRECTION (2026-07-21): "Accent color themes" is NOT real either** — this tracker had it
    wrong. There is no accent preference on iOS at all: no key in `SettingsKey`, `Palette.tint` is a
    single hard-coded colour, and Account shows Premium users a static row reading "Violet" with no
    picker. So four of the five original rows were false, not three.
  - **Recurring bills**: Android's 4th unlock is unlimited recurring bills (free cap 3,
    `RecurringRepository.FREE_RECURRING_LIMIT`). No equivalent cap found on iOS — **confirm the
    gate exists** before listing it, or the same "advertise what you don't enforce" bug appears.
  - The principle worth copying, not the strings: **one shared benefit list** feeding every
    layout, each row = title + the free-tier limit, every number **interpolated from the constant
    that enforces it** so a retuned cap can't leave stale copy.
  - ✅ **DONE 2026-07-21 — `Store/PremiumBenefits.swift`.** Widgets row deleted (free, ungated);
    categories row now "Unlimited custom categories / vs `Categories.freeCustomLimit` on the free
    plan"; cloud and accent themes demoted to muted `soon` rows with a clock. Numbers interpolate
    from `ScanQuota.freeLimit` and `Categories.freeCustomLimit`; `BudgettyTests/
    PremiumBenefitsTests.swift` fails if a row claims a number the code doesn't enforce.
  - ⚠️ **Product gap this exposed:** iOS Premium honestly unlocked **2** things; Android unlocked
    **4**. ✅ **CLOSED 2026-07-22 — the features were built rather than the offer thinned** (§15).
  - ⚠️ **Was dishonest elsewhere:** Account's "Accent color" row wore a **Premium** badge and pushed
    the paywall for a feature that didn't exist. ✅ Fixed 2026-07-22 — the row now leads to a real
    picker for Premium users.

  **c. Onboarding AI wording — ✅ DONE on iOS 2026-07-21.** Both mentions on onboarding page 2
  (`Scenes/Onboarding/OnboardingView.swift:20` and `:22`) now read "Budgetty" instead of "AI",
  matching Android's reword (`af23d0f`) where Budgetty itself is the sentence's subject. Verified on
  the simulator via `SIMCTL_CHILD_ONBOARDING=force`. No translation work: this copy is still a Swift
  literal, not in `Localizable.xcstrings` (one of the ~69 English-only iOS literals). The only
  whole-word `AI` left in the iOS bundle is two code comments (`ScanFlowView.swift:34`,
  `Settings.swift:23`); iOS's login panel never carried the AI line Android dropped in §d. ⚠️ The **privacy policy's AI limited-use disclosure naming
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

- **Free-tier widget cap: 2 placed widgets** — ✅ **PORTED 2026-07-22** (iOS branch
  `widget-free-cap`), ⚠️ **ahead of the Android branch merging**. Android's `widget-free-cap`
  (`b2ac479`) is still unmerged and not device-verified, so it was used as the spec by explicit
  decision — **if that branch changes before it merges, re-check this port.** The enforcement
  mechanism did not port; the iOS decision is recorded at the end of this entry.

  **The rule (product):** a free user may have **2 widget instances placed at once**, counted
  per *placed instance* across every type and size — two Budget widgets on two home screens use
  both slots. The cap is **live, not a high-water mark**: remove one from the home screen and the
  slot frees immediately. Existing free users over the cap when this ships get their extras
  locked (the 2 oldest keep working) — user chose this over grandfathering.

  **Android's mechanism (`WidgetQuota.kt`):** nothing is persisted. `AppWidgetManager
  .getAppWidgetIds()` across all 10 providers *is* the state; ids are sorted ascending (the
  system allocates them from an incrementing counter, so ascending == placement order) and the
  first 2 are allowed. Over-cap instances render a locked card deep-linking to the paywall. This
  is what makes removal self-healing with zero migration.

  ⚠️ **The critical bit: Android cannot refuse a placement.** The system widget picker
  (long-press home screen) bypasses the app entirely, so the in-app picker's button gate is a
  courtesy only — the cap is really enforced **at render time**, by the widget drawing a locked
  card instead of its data. iOS has the same property (a user always adds widgets from the home
  screen; there is no `requestPinAppWidget` equivalent at all), so **iOS must also enforce in the
  timeline provider, not in `WidgetsView.swift`.**

  ⚠️ **`WidgetKit` has no per-instance identity — the Android approach does not port.**
  `WidgetCenter.shared.getCurrentConfigurations` gives `[WidgetInfo]`, and `WidgetInfo` exposes
  only `kind`, `family`, and `configuration`. There is **no unique id per placed widget**, so two
  medium Budget Ring widgets are indistinguishable and "lock the 3rd one" is not directly
  expressible. Options, in preference order:
  1. **Cap distinct `(kind, family)` pairs instead of instances** — sort the pairs by a fixed
     order, allow the first 2; duplicates of the same pair share a fate. Closest workable
     analogue, and it keeps removal self-healing. Cost: a user can place three copies of one
     allowed pair for free.
  2. Count-only: if `getCurrentConfigurations().count > 2`, lock *all* of them with a "remove
     some" message. Honest but heavy-handed; avoid.

  Whichever is picked, iOS **diverges from Android's per-instance rule** — record the decision
  here, because the paywall copy must not promise a cap the platform doesn't enforce.

  **Also required on iOS:** the premium flag must be readable from the widget extension (check
  `Budgetty/Widget/WidgetSharing.swift` — the App Group store is the natural home) and timelines
  must be reloaded when the entitlement changes, or a purchase won't unlock anything until the
  next refresh.

  **Scope note:** §10 above says "1 type on iOS vs 3 on Android" and was **stale twice over** —
  iOS has 3 (`SpendingWidget`, `BudgetRingWidget`, `RecentReceiptsWidget`) and Android has **5**
  (Budget, Summary, This Week, Scan, Top Categories). Corrected in §10 on 2026-07-22.

  ---

  **✅ THE iOS DECISION (recorded 2026-07-22, as this entry asked).** Option 1 from the list above:
  **the cap counts distinct faces — `(kind, family)` pairs — not instances.** `WidgetQuota` (in
  `Budgetty/Widget/` and duplicated byte-for-byte in `BudgettyWidget/`, since the two targets can't
  share a file under the synchronized-folder layout, same as `WidgetSnapshot`).

  What this means, and what the copy must therefore never promise:
  - Two *sizes* of one widget are two faces and use both free slots.
  - Three copies of the *same* face are one slot — a free user can place three identical Budget
    Rings. Android, counting instances, would lock the third. **This is the accepted divergence**;
    it's forced by WidgetKit, which gives `WidgetInfo` only kind/family/configuration and no
    per-instance id.
  - Android keeps the *oldest* widgets working (ascending system ids encode placement order). iOS
    surfaces no placement order at all, so a fixed canonical rank (`kindOrder`) decides which two
    stay lit. Arbitrary from the user's side, but deterministic — the same two survive every reload
    instead of flickering — and still self-healing: remove one and its slot frees immediately.
  - Enforced in each widget's **timeline provider** (`LockedWidgetView`), never in `WidgetsView` —
    the home-screen picker never runs app code, so the in-app gate is courtesy only. The gallery's
    `getSnapshot` is deliberately never locked, or the widget picker would preview a padlock.
  - Fails **open**: an empty enumeration, or a missing premium flag in the App Group, renders the
    data. A widget can be asked for a timeline before the system registers it, and locking someone
    out on a half-known state is the worse failure.
  - Entitlement reaches the extension through `WidgetQuota.premiumKey` in the App Group, written by
    `WidgetSharing.publishPremium()`; `StoreManager` calls
    `premiumDidChange()` so a purchase re-renders locked widgets immediately instead of hours later.

  **Locked-card copy differs from Android on purpose.** Android says "Tap to upgrade" because it
  deep-links to the paywall. iOS has no physical Info.plist (`GENERATE_INFOPLIST_FILE = YES`), so no
  custom URL scheme is registered and a tap merely opens the app — the card says "Unlock more
  widgets" instead, which is true. Same reason the Google SDK was ruled out (§13).

  **Not device-verified**, and two things can only be proven there: that
  `WidgetCenter.currentConfigurations()` answers from inside the extension, and that a real purchase
  reloads the timelines. The decision logic itself is unit-tested (`WidgetQuotaTests`).

  **Strings:** 8 new keys on Android × 16 locales (`widgets_slots_used`, `widgets_slots_full`,
  `widgets_slots_unlimited`, `widgets_unlock`, `widget_locked_title`, `widget_locked_body`,
  `paywall_benefit_widgets`, `paywall_benefit_widgets_detail`). The paywall detail line
  **interpolates the enforcing constant** (`WidgetQuota.FREE_LIMIT`) rather than hardcoding "2" —
  keep that on iOS so retuning the cap can't leave the copy stale.

  **Paywall:** this makes **5 real unlocks + 1 "Coming soon"** on Android's shared benefits list.
  iOS's paywall benefit list needs the same new row.

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
- **Category rules, custom date range sheet, History tabs+sort+price-range, Insights customize
  sheet, income/recurring, period stepper** — spot-checked 2026-07-14, all present on iOS ✓.
  (The tester-Premium 11-tap unlock that was listed here was REMOVED from both platforms
  2026-08-06 — see the final section.)

---

*Last synced: 2026-07-21 — full audit against both codebases (PARITY.md was 5 days stale and wrong in
one place: the Account/paywall work had already merged on Android). Ported this pass: §11 category
split and §12 per-user data isolation, both on iOS branch `android-parity-cats-user-isolation`. Newly
found and still open: §13 Google Sign-In, §14 the two scan guards, plus §4's Account/paywall port and
the 69 English-only iOS literals in LOCALIZATION_TODO.md. Confirmed NOT gaps: the dual-currency fix
(server-side), Crashlytics (deliberately unmerged on iOS for the App Privacy label), and the
platform-specific tooling. Android `main`/`d0db412` · iOS `main`/`90b3d0d`.*

*Updated 2026-07-22 — closed the remaining feature gaps. Ported: §15 (the two missing premium gates —
recurring-bill cap and accent themes), the Account trim half of §4, and the free-tier widget cap,
across iOS branches `android-premium-parity` and `widget-free-cap`. Also fixed the paywall's
hardcoded price arithmetic and corrected §10's stale widget counts. All copy came from Android's
finished translations — 15 keys × 15 locales, nothing re-translated; the English-only list in
LOCALIZATION_TODO.md gained the accent names (Android ships those untranslated too) and lost the two
NotificationsView strings with that screen. **Two carried-forward risks:** the widget cap was ported
from Android's `widget-free-cap` branch **before it merged**, so re-check it if that branch moves;
and none of this is device-verified — what's left there is `WidgetCenter.currentConfigurations()`
answering from inside the extension, and a real purchase reloading widget timelines. Remaining known
gaps after this pass: Crashlytics (still deliberately unmerged, blocked on the App Privacy label),
MetricKit + snapshot tests from QUALITY_TOOLING_TODO.md, and the English-only iOS literals.
Android `main`/`fe136cd` · iOS `main`/`1165b6a`.*

*Updated 2026-07-22 (later) — **Crashlytics merged**, closing the last item above. The code was ready
since `089efa6`; what landed now is the disclosure it was waiting on: `PrivacyInfo.xcprivacy` declares
`NSPrivacyCollectedDataTypeCrashData` (not linked — nothing calls `setUserID`; keep it that way or the
manifest and the App Store label both go wrong), and Support & About actually links to the privacy
policy, which required fixing the shared policy's billing sections — they told iOS readers Google Play
handles their subscription (Android repo `23e996d`, **still needs deploying to Firebase Hosting**).
⚠️ **Still gated, and not doable from a repo: the App Store Connect App Privacy label must declare
Diagnostics › Crash Data (App Functionality, not linked, not tracking) before any build is uploaded.**
Found while doing it, not fixed: **every row on Support & About is a no-op** — FAQ, Contact us,
Suggest a feature, Terms of Service, Rate, Share all draw an outward arrow and do nothing; only
Privacy Policy is now wired. Terms is the awkward one — no terms document exists on either platform,
and Apple's guideline 3.1.2 wants Terms + Privacy links on the **subscription screen** too, which the
paywall doesn't have. Android's own FAQ link is also broken (`#faq` is not an anchor on that page).*

*Updated 2026-07-22 (later still) — **Support & About rewired**, and the fix wasn't one-per-row.
`FAQ` pointed at an anchor that has never existed on a page that is only a privacy policy, so it was
**deleted on both platforms** (Android `3221972`) rather than repointed at something equally
unhelpful. `Suggest a feature` was a second mail row with its own subject; Android had already
settled that shape — one **Contact us** whose subtitle names all three reasons to write, which is
also why the subject is neutral — so iOS folded into it (§4a). `Terms of Service` now points at
**Apple's standard EULA** (owner's decision), the agreement that already governs these subscriptions
by default; if a custom one is ever written, `Legal.swift` is the single place to change. The paywall
gained the **3.1.2-required Terms + Privacy links**, which it had been missing entirely — a plausible
rejection for an app monetised solely by auto-renewing subscriptions.
⚠️ **`Rate` and `Share` are still inert on purpose**: both need the App Store id, which cannot exist
until there's a public listing. They no longer draw an outward arrow, since promising a destination
there was the actual defect. Wire them from App Store Connect › App Information › General › Apple ID
once the app is live.
Bonus verification this pass: with StoreKit products actually loading, the derived paywall pricing
proved out end-to-end — $49.99/yr rendered "$4.17 / mo" and "BEST VALUE · −16%" against a $4.99
monthly, both computed, neither typed.*

*Updated 2026-07-23 — **build 8 shipped to TestFlight**, the first build carrying Crashlytics (iOS
`main`/`50cdd54`: `CURRENT_PROJECT_VERSION` → 8 at all six pbxproj sites, plus a string-catalog
re-extraction of the accent/Crashlytics/paywall keys — 9 keys added, none re-translated). This closes
the gate every 07-22 entry above ended on: the App Store Connect **App Privacy label is published**
(verified live on ASC 2026-07-23 — Crash Data + Other Diagnostic Data under Diagnostics, App
Functionality, not linked, not tracking), and the shared privacy policy's Apple-billing fix (`23e996d`)
is deployed to Firebase Hosting — so nothing about crash reporting is undeclared for the store. Build 8
processed clean ("Ready to Submit"), auto-distributed to the Internal group, and is already installed
and running on a tester's iPhone 16 Pro / iOS 26.5.2 — iOS internal testing now has **2 real testers,
no longer zero**. ⚠️ Build 7 was archived 2026-07-22 but never uploaded, so 8 was the first free build
number — check an archive's CFBundleVersion before assuming one is free. No feature-parity change:
build 8 is compliance/tooling, not a new feature. Android `main`/`22009e2` · iOS `main`/`50cdd54`.*

*Port brief 2026-07-25 (updated — now MERGED + RELEASED) — **three period/money-flow changes from a
tester's feedback, all merged to Android `main` and shipped in Android release 10.8.0/vc1080 (tag
`v10.8.0`)**; emulator-verified (Pixel_6), not physical-device-run. Spec'd from the ViewModels/repos.
**All three are now ported to iOS and merged to iOS `main`** — see the "iOS port 2026-07-25" record at the bottom of this brief.*

***1. Money-flow back-projection fix** (Android `bd7bb21`, was branch `fix-money-flow-no-backprojection`).
The Insights "money in vs out" card and History's Budgets snapshot scaled a recurring income/bill by
the *number of months in the selected window*, so a multi-month view (e.g. first half-year) invented
income for months the entry never existed in — a salary added in July showing 6× across Jan–Jun.
Rule (owner-chosen, "count from the date added"): a recurring cadence contributes **only for the
months of the window on/after the entry's `createdAt` month**; before that, nothing. One-offs still
count their full amount once, only if `createdAt` falls in the window. The **current** period still
shows the full expected month (not clipped to today). Android replaced the `periodAmount(window,
monthSpan)` helper with `windowAmount(windowStart, windowEnd)` (in `RecurringMath`) — whole-month
windows count eligible months exactly, partial windows scale active days / 30.4375 — and routed the
Insights money-flow totals through the selected period's actual window instead of `currentMonthRange ×
factor`. Find the iOS analogues of that recurring-scaling math and apply the same `createdAt` clip.
Unit-tested on Android (`RecurringWindowAmountTest`).*

***2. Configurable pay-cycle month — "Month starts on"** (Android `8a49680`, was branch
`custom-month-start-day`). New setting `monthStartDay` (Int 1–31, default 1 = calendar month) so the financial month
begins on the user's pay day. Core helper `PayCycle.month(today, startDay, offset)` → inclusive
start/end dates of the cycle `offset` steps from the one containing `today`; the cycle containing
today starts on this-month's `startDay` once it's arrived, else last-month's; a 29/30/31 pay day
**clamps to the short month's last day** (the same clamp iOS already uses for a bill's due-day).
Thread it through everything that means "month": Home This/Last/Last-3/Last-6 windows, the Insights
**month** stepper + its labels + "days left"/projection, the **monthly budget reset + category bars**,
the recurring plan's current-month anchor, History's budget window, and the home widgets — so every
"month" agrees. **Week, quarter and half-year stay calendar/locale-aligned** (owner scope decision;
flag if iOS wants them shifted too). Wire it reactively so open screens update when the setting
changes. Settings UI: a "Month starts on" row → picker of 1–31 (1 labelled "1 (calendar month)").
Default 1 means existing users see no change until they opt in. Unit-tested (`PayCycleTest`: paging,
the before/after-pay-day boundary, short-month clamping).*

***3. All-time (lifetime) period filter** (Android `7dda9ae`, was branch `all-time-filter`). Home gains an
"All time" preset spanning every recorded transaction through today; its daily-average anchors to the
**first transaction** (not the epoch), and it has **no** period-over-period comparison (previous
window is empty). Insights gains an "All time" entry in the period-stepper dropdown that **reuses the
custom-range window** (earliest transaction → today) — deliberately, so the trend buckets and averages
stay bounded to real data instead of blowing up from 1970. New string `period_all_time`.*

*Released as **Android 10.8.0 / vc1080** on 2026-07-25 (release commit `009c24d`, tag `v10.8.0`, signed
AAB built — pending Play upload to the Closed "Alpha" track). It supersedes 10.7.1/vc1071 (built but
never uploaded) and carries its receipt/breakdown fixes forward. Emulator proof (Pixel_6): pay-cycle
"Month starts on = 15" → Home "This month" 70 → 30; All-time → 370 across all history; a past
half-year showed income 6,000 not 18,000 (salary added mid-window). Play release notes: "Month starts
on" pay-cycle, "All time" view, and the income/bills back-projection fix (full text in the Android
`CHANGELOG.md` 10.8.0 entry). Android `main`/`009c24d` (tag `v10.8.0`) · iOS `main`/`d4cfee3` (all three
ported — see the "iOS port 2026-07-25" note below).*

*iOS port 2026-07-25 — **all three PORTED, MERGED to iOS `main` + pushed `origin/main`** (port code
`d756855`, on the now-merged branch `period-money-flow-parity`; they're interdependent and shipped
together in Android 10.8.0, so a single branch, not three). New
`Budgetty/Support/PayCycle.swift` (a Swift port of Android's `PayCycle`, same five cases) +
`BudgettyTests/PayCycleTests.swift` (**6/6 pass**, mirrors `PayCycleTest`). Build clean; sim-verified
on iPhone 17 Pro with sample data.*

- ***#2 pay-cycle month — full port.*** `SettingsKey.monthStartDay` + an Account → Preferences
  "Month starts on" picker (1–31; "1 (calendar month)"), threaded through `InsightsPeriod.interval`
  (the `.month` case only — week/quarter/half stay calendar-aligned, matching Android's scope), Home
  (`monthReceipts`/`monthLabel`/`daysProgress`), Budget (`spent`/`categorySpent`),
  `CategoryBudgetSheet`, the in-app `WidgetsView` preview, and the published `WidgetSharing` snapshot.
  Reactive via `@AppStorage(SettingsKey.monthStartDay)` in each view; non-view callers read
  `PayCycle.startDay` from `UserDefaults` (the `DateFormatOption.current` pattern). **Proof:** launching
  with `monthStartDay = 28` relabelled the Home hero **July → June 2026** and shifted **25 of 31 → 28
  of 30 days** (Jul 25 sits in the cycle Jun 28–Jul 27); spend unchanged, as every sample receipt falls
  inside it.
- ***#1 became a smaller, honest fix — NOT Android's back-projection fix.*** iOS's money-flow cards
  (`IncomeCards.swift`) are **monthly-only** — income/bills always use `monthlyEquivalent`, never
  scaled by the selected period — so Android's 6×-a-salary back-projection **cannot occur here** and
  there is no `periodAmount`/`windowAmount` to correct. The real (small) iOS bug was that the card was
  fed the *selected period's* spend while income/bills stayed monthly, going incoherent in any
  non-month view. Fix (owner-approved): feed it the current **pay-cycle month's** spend
  (`currentMonthSpent`), a consistent "this month" snapshot in every period. `windowAmount` was
  deliberately **not** ported.
- ***#3 is Insights-only — no Home "All time" preset.*** iOS Home has **no period filter at all**
  (hard-scoped to the current month, no This/Last/Last-3/Last-6 presets like Android), so the Home
  half of the change has no analogue and was not built — adding a Home period filter is a separate
  feature needing a mockup, and PARITY never flagged its absence, so it's treated as intentional iOS
  design. Ported: an **"All time"** item (∞) in the Insights period menu that sets a custom range
  earliest-receipt → today, reusing the custom-range path exactly as Android's Insights entry does.
- **⚠️ Not tap-verified** (the MCP simulator panel's `xcode-select` preflight is stale-blocked on this
  Mac, so no input injection — drove `simctl` screenshots instead): the Account "Month starts on"
  **picker** interaction and the Insights **"All time" menu** item. Both build clean and are
  near-verbatim copies of working patterns (`dateFormatPicker`; the custom-range menu button). A
  physical-device / tap pass is the only remaining verification step (the port merged without it, as
  the branch convention allows).
  Android `main`/`009c24d` · iOS `main`/`2612555` (`d756855` port + `2612555` a pbxproj-comment restore).*

---

## Android → iOS — budgeting/saving parity batch (2026-07-25, owner-directed)

*Owner directive: **budgeting & saving features must be identical on both platforms** — only platform-native
differences may diverge (Sign in with Apple, Face ID lock, Liquid Glass). See the Android memory
`cross-platform-parity-principle-2026-07`. Six items below. #1–#4 make iOS match Android's **existing**
behavior (Android is the spec, no Android change); #5–#6 are **new features added to BOTH** (Android built in
this batch). Port from the Android ViewModels/repos as usual. Designs: mockups needed for #3/#4/#5/#6 — being
created in the Budgetty design project; match the Liquid Glass mockups when they land.*

***1. Money-flow / savings cards → make period-scaled (currently monthly-only).*** iOS `IncomeCards.swift`
computes income/bills from a fixed `monthlyEquivalent` and pairs them with `currentMonthSpent`, so on
quarter / half-year / all-time / custom the cards still show **one month** while the rest of Insights scales.
Android scales them to the selected period: income & bills go through `RecurringMath.windowAmount(windowStart,
windowEnd)` (per-month rate × eligible whole months in the window, **clipped to the entry's `createdAt`
month**; partial windows scale by days ÷ 30.4375), and the paired spend is the selected period's actual spend.
Port that: make money-in-vs-out, savings-rate, where-your-income-goes and income-by-source period-scaled — which
**requires porting the `windowAmount` createdAt-clip** (Android `bd7bb21`) so a multi-month view doesn't
back-project a just-added salary. Upcoming-bills stays date-based. Android ref: `InsightsViewModel.recurringInsights`
+ `ui/util/RecurringMath.windowAmount`.

***2. History "Budgets" tab → make time-scoped (currently a live plan mirror).*** iOS's Budgets tab mirrors the
*current* plan (`monthlyEquivalent`, no window). Android scopes it to the History Date filter: `periodIncome` /
`periodBills` via `windowAmount(windowStart, windowEnd)`, section headers keep the per-month rate. Make iOS
scope to the selected History window the same way. Android ref: `HistoryViewModel` (`budgetPeriod` → `windowAmount`).

***3. Home period filter (iOS has none).*** iOS Home is hard-scoped to the current month (static label,
`HomeView.swift:141`). Android's Home has a period filter — This month / Last month / Last 3 / Last 6 / **All
time** — though on Android it appears **only in the wide/tablet layout** (the phone Home has none either). Add an
equivalent period switcher to iOS Home. **Needs a mockup.** Android ref: `ui/home/DateRangeFilter` (the enum,
incl. `ALL_TIME`) + `PeriodFilterMenu` + the wide `HomeScreen` header.

***4. Widgets → match Android's set (iOS has 3, Android 5).*** iOS: Spend Total, Budget Ring, Recent Receipts.
Android: Budget, Summary, This Week, Scan, Top Categories. Add the missing faces so the sets match. **Needs
mockups.** The free-tier 2-widget cap already ported (per-face on iOS). Android ref: `widget/` (5 providers) +
`WidgetDataProvider`.

***5. Budget rollover / carry-over — NEW, add to BOTH.*** Owner-chosen model: **unspent-only, opt-in toggle,
applies to the overall budget AND each category budget.** When on, at the start of each new period the leftover
(**positive only** — overspend is forgiven, never rolls negative) carries into the next period's available; the
progress bar/limit uses **budget + carried** and a green **"+€X carried over"** line appears. Requires
**persisting each period's carried amount** — budget amounts change without history, so it can't be recomputed;
roll forward at the first open in a new period (accumulate each elapsed period's `max(0, budget + carried −
spent)`, handling multiple skipped periods). **Only the overall MONTHLY budget + category budgets carry — a
weekly overall budget never does.**

**⚠️ Display scope = EVERY budget surface, not just the Budget scene.** This is the part the parity directive
turns on: Android first shipped rollover Budget-screen-only (`274519b`), then threaded the display everywhere as
a follow-up (`c8d8863`) precisely so the two platforms stay identical — don't repeat the narrow first cut on iOS.
Port the effective budget (base + carried) **and** the "+€X carried over" indicator to: the Budget scene (overall
card + per-category rows/tiles, incl. iPad), **Home** budget card, **Insights** budget card (overall + per-
category limits), and the **budget widget**; per-category "+X" labels on the category tiles/rows too. **Carry
applies only to the CURRENT period** — never project the stored balance onto a past/stepped period (matters for
Insights period stepping), and weekly views show no carry.

Android impl (branch `budget-rollover`, on `origin/budget-rollover`, **NOT merged to Android `main`**): backend +
roll-forward math + Budget-screen UI = **`274519b`**; the all-surface display wiring = **`c8d8863`**. The VMs
expose a **setting-gated carried map** (empty when the toggle is off; only ever `MONTHLY` + `CAT:` keys, so weekly
gets no carry for free) and each surface computes `effective = base + carried`. Refs: `ui/util/BudgetRollover`
(pure roll-forward math, unit-tested by `BudgetRolloverTest`), `BudgetRolloverEntity` / `BudgetRolloverRepository`
+ `MIGRATION_18_19` (new `budget_rollover` table keyed by budgetKey, storing carried + periodKey `"yyyy-MM"`),
`BudgetViewModel.rollForwardIfNeeded`, `HomeViewModel.monthlyCarried`, `InsightsViewModel` carried combine +
`InsightsScreen.BudgetSectionCard`, `WidgetDataProvider` (bakes carry into the effective monthly budget), and the
`budget_rollover_enabled` setting. Phone + tablet emulator-verified. iOS: SwiftData model addition (a rollover
store keyed by budget key + period) + the gated-carried plumbing across **all** budget surfaces above.

***6. Recurring "mark as paid" — NEW, add to BOTH (Android `fcc06ff`).*** Each recurring **bill** gets a
tap-to-toggle paid check for its **current occurrence**: paid rows dim their amount, the Payments section shows
"N of M paid", and a paid bill drops off the Insights **"upcoming bills"** list until its next occurrence.
**No transaction is posted** — recurring stays planning-only, so it never double-counts a scanned receipt.
Android derives paid-state from the **reused `lastPosted` timestamp** falling inside the bill's current window
(pay-cycle month for monthly, Mon–Sun week for weekly, calendar year for yearly; a one-off stays paid once set),
so it **auto-resets each cycle with no schema change and no scheduled job**. iOS `Recurring` already has
`lastPosted: Date?` (reserved) — reuse it the same way. Android ref: `ui/util/RecurringMath.isPaidThisCycle`,
`BudgetViewModel.setBillPaid`, `RecurringDao.setLastPosted`, Budget `MoneyRow` paid toggle + `RecurringPaidTest`.

*Status: iOS = all six PENDING. Android = **#5 built** (rollover backend + all-surface display; branch
`budget-rollover` → `origin/budget-rollover`; `274519b` + `c8d8863`; phone + tablet emulator-verified) and **#6
built** (`fcc06ff`, branch `recurring-mark-as-paid`) — **neither merged to Android `main` yet**; #1–#4 are already
Android's shipped behavior (10.8.0). Android `main`/`009c24d`.*

---

# Category & Insights v2 — NEW batch, add all three to iOS (Android `main` merge `4c764f0`)

Merged to Android `main` (branch `category-insights-v2`; `688f122` + iOS doc `98c0e51`; merge `4c764f0`), emulator-verified. **Full iOS design-request + port brief lives at the Android repo root: `IOS_CATEGORY_INSIGHTS_V2_DESIGN_REQUEST.md`** — its "Design request" sections go to Claude Design for the `iOS *.dc.html` Liquid-Glass mockups; its "Port notes" drive the build. Summary:

***1. Insights pie legend.*** Legend rows gain a colored emoji tile + the category % over the muted amount; the donut centre shows the tapped category's emoji; **keep the on-ring % labels**. No model change. Android ref `PieChart.kt`.

***2. Expanded emoji picker.*** The custom-category icon grid becomes a curated **~220-emoji pool in 9 searchable sections** (pinned search; match is **exact-token-first, else prefix** — "car"→vehicles not "carton"). Port the exact list + keywords from Android `EmojiCatalog.kt`; both platforms share one vocabulary.

***3. Sub-categories (user-defined 2-level).*** Nullable **`parent`** per category (Android DB **v20 / `MIGRATION_19_20`**, additive — existing rows NULL, grouping resolves from code). Effective parent = `row.parent ?? codeDefaultParent(name)`; `groupOf` rolls up to it. **Parents are spendable**; re-home **custom AND built-in**; delete→promote children to top-level, rename→cascade, nesting→release own children; **2 levels only**; **organising is FREE** (no new paywall). Picker shows custom primaries as headers with their effective children + a **Parent selector** + built-in **"Move to group"**. Budget screen rolls up own+children (group total = own + children budgets); Insights grouped mode folds custom children into their custom primary **automatically via `groupOf`**. iOS: add nullable `parent` to the SwiftData category model + a migration, port cascades from `UploadViewModel`/`BudgetViewModel` + `Categories` (`parentOf`/`groupOf`/`defaultParentOf`, `budgetGroups`/`effectiveChildren`). ⚠️ v1 limitation: a built-in re-homes into another group but can't become standalone top-level (NULL falls back to its code default group).

*Status: iOS = **all three PORTED** on branch `category-insights-v2` (not yet merged). Android = merged to `main` (`4c764f0`), emulator-verified.*

**iOS port notes (2026-07-30).** Behaviour matches; a few platform-native divergences vs the Android brief:
- **No on-ring % labels** — the iOS donut (`DonutChart`) never had them, so the brief's "keep the on-ring labels" is an Android-only detail. The percentages live in the legend rows and in the donut centre on tap; the donut gained tap-to-select + dim (new — the iOS donut was previously non-interactive).
- **No category ViewModel/repo on iOS** — the cascades (rename→children follow + repoint refs, delete→Other + promote children, nest→release own children) live in a new `CategoryOps` mirroring `Migrations.splitSubscriptionsAndServices`'s name-repoint pattern, not a ported VM.
- **SwiftData migration is lightweight** — `Category` gained a nullable `parent: String?`; the container has no migration plan, so no `VersionedSchema` was needed (vs Android's explicit `MIGRATION_19_20`). `CategoryDTO` in `Backup.swift` carries `parent` for round-trip.
- **DB-aware grouping** — `Categories` gained a lock-guarded stored cache (`setStored`, primed in `BudgettyApp.prepare` + after every mutation) so `groupOf`/`parentOf`/`childNames` honour user overrides and `color(for:)`/`emoji(for:)` resolve custom rows. Widget group sums stay correct because they're computed in-app in `WidgetSharing.update` (cache primed) and baked into the snapshot.
- **Files:** `Category.swift`, `Categories.swift`, `CategoryOps.swift` (new), `EmojiCatalog.swift` (new), `CustomCategorySheet.swift`, `CategoryParentList.swift` (new), `CategoryPickerSheet.swift`, `BudgetView.swift`, `CategoryBudgetSheet.swift`, `DonutChart.swift`, `InsightsView.swift`, `Backup.swift`, `BudgettyApp.swift`, `Localizable.xcstrings` (+17 keys ×15 locales). Tests: `EmojiCatalogTests`, `CategoryHierarchyTests`.
- **Verified:** Debug build clean; 107/107 unit tests pass; **tap-verified on iPhone 17 Pro (dark)** — F1 slice/row tap-select (centre emoji + dim, Groups/All reset), F2 icon search ("gym"→6, "car"→7 dropping carton/carrot), F3 parent picker + nested-custom create (folds under its group in the picker) + context menu (Edit / Move to Group / Set Budget / Delete) + re-home sheet with the current parent pre-checked. (The MCP sim needed `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` on this Mac — the earlier stale-block, cleared 2026-07-30.)*

---

# Future-features batch — build on BOTH platforms in parallel (planned 2026-07-30)

**Unlike every section above, these are NOT built on either platform yet.** They came out
of the 2026-07-25 competitive-gap review and were greenlit 2026-07-30 to be **designed
first, then built on Android and iOS simultaneously** — not Android-first-then-port. So
there is **no reference implementation to port from**: the shared spec for each feature is
its **design-request doc** (written for both platforms 2026-07-30), and both apps build to
it. Budgeting/saving behavior must stay **identical** per the cross-platform parity
directive; only platform-native UI (Material 3 ⇄ Liquid Glass) and platform mechanics
(BiometricPrompt ⇄ LocalAuthentication, `PdfDocument` ⇄ PDFKit) differ.

**Design status 2026-07-30:** design-request docs written for **both** platforms (paths
below). Build began with **Safe to spend** (now ✅ built + merged on Android — see item 1); the other
four are next in the order below. Android **and** iOS mockups for all five are in the Claude Design
project (`5b8c8470-…` — `iOS Safe to Spend` / `iOS Savings Goals` / `iOS Subscriptions` /
`iOS Data Export` / `iOS App Lock`).

**✅ UPDATE 2026-07-31 — ALL FIVE BUILT + MERGED ON iOS** (native SwiftUI + Liquid Glass, ported from
the Android impls where they exist + the shared design docs; ViewModels/repos → SwiftUI views &
SwiftData since iOS has no VM layer; each localized to the 15 non-en locales by mechanical conversion
from Android's finished strings; sim-verified on iPhone 17 Pro). iOS commits:
#1 Safe to spend `8e651c1`, #2 Savings goals `3bd8bf3`, #3 Subscription detection `252dc2d`
(+ 7 ported detector unit tests), #4 CSV & PDF export `33455cf`, #5 App lock `f0344e6`. The
each item's iOS commit + impl notes are now filled in inline below.

**Build order & gating (decided 2026-07-30):**

1. **Safe to spend until payday** — **FREE.** A Home hero number = *income (this pay-cycle)
   − spent so far − bills still unpaid this cycle*; optional per-day; resets each pay-cycle.
   **No new data model** — a new Home view-model derivation over building blocks that
   already ship on both platforms: pay-cycle windows (`PayCycle`), recurring **income**
   (`isIncome`), **unpaid** bills (`RecurringMath`/`isPaidThisCycle`), and spend-so-far.
   Docs: Android `SAFE_TO_SPEND_DESIGN_REQUEST.md` · iOS `IOS_DESIGN_REQUEST_SAFE_TO_SPEND.md`.
   **✅ ANDROID BUILT + MERGED** (`4831bd7`, 2026-07-30): phone + tablet, 4 states (healthy / low /
   over / setup-no-income), 16 locales, Roborazzi goldens. Impl = a new `HomeViewModel` cash-flow
   derivation (`cycleIncome` / `billsStillDue` / `billsPaid` / `safeToSpend` / `daysUntilPayday`,
   reusing `PayCycle` + `RecurringMath.isPaidThisCycle`) + an `internal SafeToSpendCard` in
   `HomeScreen.kt` that replaces the Total-spent card for the current month (period pill suppressed on
   tablet). Design landed as **Variant D "merged card"** — safe-to-spend hero + a Spent / Bills-still-due
   stat strip in one card. **⚠️ Modelling note for the iOS port:** `safe = income − spent − bills STILL
   DUE`; bills already marked paid are NOT re-subtracted (they drop off), and the "getting low" state
   triggers at ≤10 % of cycle income. **✅ iOS BUILT + MERGED** (`8e651c1`): a computed-property
   derivation on `HomeView` (iOS has no VM layer) + a glass `safeToSpendCard` — status wash behind the
   material, an inset Spent/Bills-due/Income list — replacing the Total-spent hero for the current
   pay-cycle month. Income/bills summed via `monthlyEquivalent` (= Android's flat `monthlyAmount`, **not**
   the createdAt-clipped `windowAmount`). Sim-verified light / dark / de.

2. **Savings goals** — **CAPPED-FREE: 1 goal free, unlimited Premium** (same pattern as
   widgets-2 / custom-cats-3 / recurring-3). New model: `SavingsGoal` + `SavingsContribution`
   (`saved = Σ contributions`; **manual tracker — no real balance**). Lives as a section on
   the Budget tab + a goal-detail sheet (ring, contribution history, add/withdraw, edit).
   Docs: Android `SAVINGS_GOALS_DESIGN_REQUEST.md` · iOS `IOS_DESIGN_REQUEST_SAVINGS_GOALS.md`.
   **✅ ANDROID BUILT + MERGED** (`2d7d78d`, 2026-07-30): Budget-tab section (ring cards + empty + the
   1-goal-cap paywall) + a full goal-detail nav screen (`savings_goal/{id}`) — hero ring, Saved/Target/
   Left, contribution history, Add/Withdraw + edit/delete + reached state. **New Room tables
   `savings_goals` + `savings_contributions` (DB v21, `MIGRATION_20_21`, cascade-delete)**; `saved = Σ
   signed contributions`; pace = remaining ÷ whole-months-to-date, "behind" when > recent avg deposit.
   `SavingsRepository` (`FREE_GOAL_LIMIT=1`), `BudgetViewModel` list+create + a per-goal
   `SavingsGoalViewModel`. 16 locales + Roborazzi goldens. **✅ iOS BUILT + MERGED** (`3bd8bf3`):
   SwiftData `SavingsGoal` + `SavingsContribution` (registered in `UserStore.models` **and** the
   `Backup.swift` export/import DTOs), `SavingsMath`, a Budget-tab section + goal-detail **sheet** (iOS
   uses a sheet, not a nav screen) + add/withdraw/create sheets + a searchable emoji picker over
   `EmojiCatalog`; the 1-goal cap gates on the same `isPremium` check. Sim-verified: create → cap-lock +
   unlock nudge → contribution updates the ring 0→25%.

3. **Subscription detection** — **PREMIUM** (free = teaser + locked list). On-device
   clustering over the existing transactions by normalized merchant + cadence; flags price
   hikes; **"Track as bill"** creates a recurring bill that then feeds Safe to spend. Entry
   card on Insights → list → detail. Docs: Android `SUBSCRIPTION_DETECTION_DESIGN_REQUEST.md`
   · iOS `IOS_DESIGN_REQUEST_SUBSCRIPTION_DETECTION.md`.
   **✅ ANDROID BUILT + MERGED** (`29b88e9`, 2026-07-31): pure `SubscriptionDetector` (cluster receipts
   per merchant at a regular monthly/yearly cadence, ≤2 distinct amounts, ≥3 charges; unit-tested) +
   `SubscriptionsViewModel` over transactions+receipts. Insights entry card (new
   `InsightsSection.SUBSCRIPTIONS`) — Premium summary vs a free teaser (real count/total, redacted rows)
   → `subscriptions` route (list + detail + a track-as-bill sheet). Price-hike = latest amount > an
   earlier one (before→after + annual cost). **"Track as bill"** upserts a recurring bill
   (`isIncome=false`, category "Subscriptions"). **New Room table `ignored_subscriptions` (DB v22,
   `MIGRATION_21_22`)** for dismiss/restore. 16 locales + Roborazzi goldens. **✅ iOS BUILT + MERGED**
   (`252dc2d`): `SubscriptionDetector` + `SubscriptionScan` (+ **7 ported detector unit tests**),
   `StoreNormalizer`, a SwiftData `IgnoredSubscription`; Insights entry card (`InsightSection.subscriptions`
   — Premium summary / free teaser) → pushed list → detail (charge history + price-hike) → track-as-bill
   sheet. Sim-verified (needed 3× monthly Netflix receipts seeded to surface it — empty ⇒ card hidden,
   same as Android).

4. **CSV & PDF export** — **PREMIUM.** Human-readable export (CSV spreadsheet + a branded
   one-page PDF statement) beside the existing JSON backup on Account; period/category
   filter via `DateRangeFilter`; **native only** (`PdfDocument` / PDFKit → system share
   sheet). Docs: Android `DATA_EXPORT_DESIGN_REQUEST.md` · iOS `IOS_DESIGN_REQUEST_DATA_EXPORT.md`.
   **✅ ANDROID BUILT + MERGED** (`19128f7`, 2026-07-31): a premium Account row (padlocked for free) →
   an options sheet (CSV/PDF toggle + period dropdown + live count/total + empty guard). CSV = a row
   per receipt; PDF = a native `PdfDocument` statement (header, Total/Income/Net tiles, by-category
   bars, paginated transaction table). Split `ExportBuilder` (pure `buildCore` + CSV, unit-tested) vs
   `DataExporter` (graphics). Shared via the existing FileProvider + `ACTION_SEND`. **No new table.**
   16 locales + a Roborazzi golden of the rendered statement. ⚠️ v1 cut the category multi-select +
   PDF-preview (presets-only period); note for the iOS port. **✅ iOS BUILT + MERGED** (`33455cf`):
   `ExportBuilder` (period aggregation + CSV, mirrors Android's `buildCore`) + `DataExporter`
   (`UIGraphicsPDFRenderer` statement — header, Total/Income/Net tiles, by-category bars, paginated
   transaction table) + an options sheet + a premium-gated Account row (padlocked for free); shared via
   `UIActivityViewController`. Same presets-only cut as Android. Sim-verified (real branded PDF → share sheet).

5. **App lock — PIN + biometric** — **FREE** (we don't paywall security). Optional PIN +
   biometric gate on cold start / resume-after-idle; auto-lock Immediately / 1 min / 5 min;
   forgot-PIN = re-authenticate. Native (BiometricPrompt / LocalAuthentication); PIN stored
   **hashed** (EncryptedSharedPrefs / Keychain). **⚠️ iOS: evolve the existing Face ID
   toggle into this Security group — add a PIN fallback + auto-lock, don't add a second
   biometric toggle.** Docs: Android `APP_LOCK_DESIGN_REQUEST.md` · iOS `IOS_DESIGN_REQUEST_APP_LOCK.md`.

   **✅ ANDROID BUILT + MERGED** (`6d0be9a`, 2026-07-31): `AppLockGate` wraps the whole app —
   cold start always locks, resume re-locks past the idle delay (lifecycle observer). `LockScreen`
   (PIN pad, shake-on-wrong-PIN, biometric auto-prompt, Forgot PIN → sign out + clear lock) +
   `SetPinScreen` (choose → confirm). Salted SHA-256 PIN in `app_settings` prefs (`PinHash`) — no
   `security-crypto` lib. Biometric via framework `BiometricPrompt` (minSdk 28), **no
   `androidx.biometric`**; `USE_BIOMETRIC` perm. Account **Security** group: App-lock toggle →
   set PIN, Change PIN, biometric row (only where hardware enrolled), Auto-lock dropdown. **No new
   Room table** — prefs only, DB stays **v22**. 22 strings × 16 locales; Roborazzi lock/set-PIN
   goldens. **✅ iOS BUILT + MERGED** (`f0344e6`): `PinLock` (salted SHA-256 in the **Keychain** via
   CryptoKit + `SecItem`), `AppLockGate` (cold-start + resume-after-idle via `scenePhase`),
   `LockScreenView` + `SetPinView` over a shared PIN scaffold (shake-on-wrong-PIN, optional biometric
   key), `BiometricAuth` (LocalAuthentication). **Evolved the old Face-ID toggle into an Account Security
   group** (App-lock toggle → set PIN, Change PIN, Use Face ID/Touch ID, Auto-lock) and deleted the old
   `BiometricLockView.swift`. Lock screen sim-verified via the `SHOW_SCREEN=lock` hook (keypad fills the
   dots, wrong PIN rejected). ⚠️ iOS-sim harness quirk: SwiftUI Toggles don't flip via raw simctl taps
   (hits even pre-existing toggles) — verify toggle flows via the debug hook, the binding is standard.

*Status (2026-07-31): **all five BUILT + MERGED on Android** — #1 Safe to spend (`4831bd7`), #8
Savings goals (`2d7d78d`), #9 Subscription detection (`29b88e9`), #5 CSV+PDF export (`19128f7`),
#3 App lock (`6d0be9a`) — each phone+tablet where relevant, 16 locales, Roborazzi. **✅ AND all five
BUILT + MERGED + PUSHED on iOS (2026-07-31)** — native SwiftUI / Liquid Glass, each localized (15
non-en locales, mechanically converted from Android's strings) + iPhone-17-Pro sim-verified: #1
`8e651c1`, #2 `3bd8bf3`, #3 `252dc2d`, #4 `33455cf`, #5 `f0344e6`. **The competitive-features batch is
now CLOSED on both platforms.** (This batch supersedes backlog item "Budget rollover", already shipped
in Android 11.0.0.) Android `main` HEAD = `6d0be9a` (DB **v22**); iOS `main` HEAD = `4f68005` on
`github.com/Kammenk/Budgetty-iOS` (`category-insights-v2` since merged).*

---

## Section refresh — Account toggle chevrons · move Upcoming bills to Home · drop Insights Budget (2026-08-01)

A pre-release UI cleanup, kept in parity where it applies to both platforms:

- **Account toggle rows (Android only):** settings rows with a switch (App lock, Crash reporting) no
  longer render a trailing chevron — the arrow is only for rows that navigate (`SettingRow`, chevron
  gated on `trailing == null`). iOS never had a toggle+chevron row, so no iOS change.
- **Home "this week vs last week" strip (Android only):** removed — `HomeSection.WEEK_COMPARISON` +
  `QuickStatsStrip`/`WeekDeltaLabel` and the backing `lastWeekSpent`/`topCategory` state. iOS keeps its
  `weekComparison` section (hidden by default), unchanged.
- **Insights "Budget" section (both):** removed entirely — gone from the customize menu, no longer
  rendered. Android: `InsightsSection.BUDGET` + `BudgetSectionCard` + helpers; iOS: `InsightSection.budget`
  + `budgetSection` + `BudgetVsActualCard`. Onboarding quiz updated on both (the "budget" goal now boosts
  period-comparison only; the budget-amount seed stays). Budget still lives on the Budget screen.
- **Upcoming bills → Home (both):** moved from Insights to a new Home section directly below the budget
  card. Android: new `HomeSection.UPCOMING_BILLS` (phone + portrait tablet); `UpcomingBill` +
  `nextOccurrenceDays` + `upcomingBills()` extracted to `RecurringMath`, computed in `HomeViewModel`'s
  existing recurring combine. iOS: new `HomeSection.upcomingBills`; the card lifted out of
  `IncomeInsightsCards` into `HomeView` (`recurrings.filter { !isIncome && !isPaidThisCycle }`, due-day
  sorted). Date-based, shown for any period once a bill is unpaid.

**Status (2026-08-01):** BUILT + verified on both — Android on Pixel 6 (branch
`home-insights-section-refresh`, `df7f27b`), iOS on iPhone 17 Pro (branch `home-insights-section-refresh`).
Not yet merged to `main` on either repo (awaiting review).*

## History composite refresh (both) — 2026-08-02

The "dull History" fix, from the composite mockups `History Recommended.dc.html` +
`iOS History Refresh.dc.html` (Liquid Glass). Four additions to the History Receipts/Items tabs:

- **Summary strip** atop each tab: the current month's total, count, delta vs last month (a `×N`
  multiplier past 5× so a near-empty prior month doesn't read as "+1602%"), and a 6-month sparkline
  (last bar = current month). Android `HistorySummaryStrip` in `HistoryScreen.kt`; iOS `summaryStrip`
  + `monthSummary` in `HistoryView.swift`.
- **Magnitude bar** under every row = its share of the month's biggest. Android `MagnitudeBar`; iOS
  `magnitudeBar`.
- **Receipt expand-in-place:** tap reveals top items inline + "Open receipt" (pushes detail). Two-pane
  iPad / landscape tablet still selects the detail pane. Android `ReceiptExpandedPanel`; iOS
  `receiptExpansion` + shared `ReceiptRowView` gains `expandable`/`expanded`.
- **Item price-history:** tap a product bought ≥2× → times bought, average, mini chart of recent buys,
  and where it was cheapest. Per-product aggregation over the unfiltered ledger — Android `productStats`
  in `HistoryViewModel`; iOS `productStats` computed in `HistoryView`. Also dropped Android's dead
  multi-column Items grid. 5 new strings both platforms (reusing vs-last-month / +N-more / item-count),
  all locales.

**Status (2026-08-02):** Android — branch `history-composite-refresh` (`483ac43`), Pixel 6 verified,
pushed. iOS — branch `history-composite-refresh`, build green + iPhone 17 Pro verified (summary strip,
magnitude bars, receipt expand; item price-history correctly gated to ≥2×, not shown on the sparse seed
but the aggregation mirrors the device-verified Android one). Not yet merged on either.*

## Wellbeing coach — score + weekly/monthly coaching (both) — 2026-08-04

A new free feature: a 0–100 financial Wellbeing score with weekly/monthly coaching tips, on a dedicated
full-screen destination (bottom-nav/dock hidden) reached from a live Home banner + a slim Insights row —
deliberately NOT an Insights block. Rule-based, on-device; no new data model beyond dismissed-tip ids.

- **Engine (spec):** Android `WellbeingEngine`/`WellbeingProvider` (`ui/wellbeing/`) — score from ~5
  renormalizing sub-scores (savings 25%, budget adherence 25%, spending trend 15%, subscriptions 15%,
  goals 20%), bands Needs-work/Getting-there/Healthy/Thriving; weekly = a "this week" pace card + tactical
  tips, monthly = the graded score + tips. iOS `Support/WellbeingEngine.swift` + `Support/WellbeingSummary.swift`
  (`WellbeingScan.run` mirrors `WellbeingProvider.build`), reusing existing compute (savings-rate math,
  trend via `InsightsPeriod.previous()`, `SubscriptionScan`, `SavingsMath`, `PayCycle`, `Recurring.windowAmount`).
  17 unit tests each side.
- **UI:** Android `WellbeingScreen`/`WellbeingBanner`/`WellbeingInsightsRow` + `ScoreRing` (phone + tablet:
  capped column + two-up score card — NOT a landscape two-pane). iOS `Scenes/Wellbeing/WellbeingView.swift`
  + `Scenes/Home/WellbeingBanner.swift` — native Liquid Glass (no Wellbeing mockup existed; adapted from
  tokens). New `HomeSection.wellbeing` (between upcomingBills/receipts) + slim Insights row; dismissed-tip
  ids in `@AppStorage`/prefs. 15 locales both sides.

**Status (2026-08-04):** PORTED — both merged to `main`. Android `f65c661` → **11.2.0 / vc1120** (tag
`v11.2.0`, Pixel 6 + Pixel_Tablet verified). iOS `b2a9943` → **build 10** (iPhone 17 Pro sim-verified,
BUILD SUCCEEDED). Neither uploaded to a store yet.

## Removed the 11-tap tester-Premium backdoor (both) + Play language-split fix (Android-only) — 2026-08-06

- **11-tap tester-Premium unlock — REMOVED on both.** The hidden gesture (11 taps on the Account version
  label → grant Premium, added for internal testers) is gone. Android: dropped the gesture +
  `unlockTesterPremium` + `BillingManager.TESTER_PREMIUM_ENABLED`/`KEY_TESTER_PREMIUM` + the `testerPremium`
  OR in `isPremium` + the toast strings ×16 locales (`00000eb` → **11.2.1 / vc1121**, tag `v11.2.1`; signed
  AAB verified tester-free — 0 dex refs / 0 string keys). iOS: dropped the tap gesture in `SupportAboutView`
  + `SettingsKey.testerPremium`; `StoreManager.syncPremiumFlag` now mirrors only the real StoreKit
  entitlement (`10fd81a`, **build 10**, sim BUILD SUCCEEDED). Supersedes the "tester premium unlock (11-tap)
  … present on iOS ✓" note above. ⚠️ Still live in the shipped Android **vc1120** until users update, so the
  removal's store notes were kept generic.
- **Play App Bundle language-split fix — Android-only, NO iOS action.** In-app language switching (Account →
  Language) did nothing on Play (App Bundle) installs because Play delivered only the device-locale strings;
  fixed with `bundle { language { enableSplit = false } }` so every locale ships in the base install (Android
  `0cf2d8d` → 11.1.2/vc1112, carried into 11.2.0+). iOS ships every `.lproj` in the app bundle (the App Store
  doesn't split localizations by device language) and the in-app switch uses an `AppleLanguages` override —
  so there is **no iOS equivalent bug and nothing to port.**

**Status (2026-08-06):** 11-tap removal DONE + pushed on both (`00000eb` / `10fd81a`); Play language fix is
Android-only. Neither the 11.2.1 AAB nor iOS build 10 uploaded yet.

## Safe to Spend reserves paid bills (fix) + "Total spent this cycle" row (both) — 2026-08-10

- **Bug (both platforms):** Safe to spend subtracted only *bills still due*, not *bills already paid*, so
  marking a recurring bill paid moved its amount out of the only subtracted bucket and the figure jumped
  UP by that amount (testers: 2700 → 2790 after paying a 90 bill). Fix = also subtract paid bills:
  `income − spent − billsStillDue − billsPaid`. A due bill is already reserved out of the number, so
  paying it is now net-neutral (2700 → 2700), NOT −90. The user confirmed the reserve model over a
  running-wallet one. Android `HomeViewModel.safeToSpend`; iOS `HomeView.safeToSpend` (whose comment had
  even documented the old "drop off / not re-subtracted" behaviour — corrected).
- **"Total spent this cycle" row (both):** receipts + paid bills, shown only once a bill is marked paid
  (until then it equals the "Spent" figure and is hidden). Android: a new row under the Spent/Bills strip;
  iOS: a new inset-list row between "Bills still due" and "Income this cycle". String
  `safe_to_spend_total_spent` / "Total spent this cycle", 15 locales both sides.
- **Bar (both):** paid bills fold into the solid "spent" segment, so the hatched "still due" / safe share
  is unchanged when a bill is paid; screenshot fixtures reconciled to sum-to-income (Android goldens
  re-recorded).

**Status (2026-08-10):** PORTED — both on their own `safe-to-spend-reserve-paid-bills` branch off `main`.
Android `7a8cce2` PUSHED (unmerged; detekt/tests/Roborazzi green). iOS committed on-branch (sim BUILD
SUCCEEDED), unpushed. Neither merged/uploaded. Related open follow-up: scope for auto-marking recurring
bills as paid on their due date (per-bill "Autopay", compute-on-read) — not yet built.

## Per-bill Autopay: bills auto-mark paid on their due day (both) — 2026-08-10

- **Feature (both platforms):** a recurring bill can be set to Autopay (a switch in the add/edit sheet,
  shown for monthly/weekly bills). Once its due day passes in the current cycle it counts as paid
  automatically — no monthly re-tap. Derived on read (no background job), mirroring the existing
  `isPaidThisCycle` reset; yearly/one-off bills have no computable due date and stay manual.
- **Data:** Android `RecurringEntity.autoPay` (Room v23 migration, column defaults 0); iOS
  `Recurring.autoPay` (SwiftData lightweight migration, defaults false).
- **Logic:** `RecurringMath` gains `isDuePassedThisCycle` + `isEffectivelyPaidThisCycle` (manual OR
  autopay-and-due). Home Safe-to-Spend cash-flow, the Budget paid list/counter, and the Upcoming-bills
  filter all read the effective state — autopay bills fold into paid / total-spent and drop off
  still-due / upcoming. Safe to Spend stays net-neutral (paid and still-due are both subtracted).
- **UI:** the Budget bill row shows a static "Auto" chip (greens once due) instead of the manual paid
  toggle; the sheet gains the Autopay switch. Strings "Autopay" / "Mark as paid automatically on its
  due day" / "Auto" × 15 locales both sides. Unit tests for the due-date / effective-paid math both sides.

**Status (2026-08-10):** DONE both, on branch `recurring-bill-autopay` (stacked on
`safe-to-spend-reserve-paid-bills` — merge that first). Android `ea4e044` (compile + detekt + full unit
tests green). iOS committed on-branch (sim BUILD SUCCEEDED + RecurringPaidTests 12/12 pass). Unpushed.

## Safe-to-spend Home card → spent-first (Total spent hero) (both) — 2026-08-10

- **Design:** Direction C from the "total spent on Home" brief — Android mockup `HomeTotalSpent.dc.html`,
  iOS `iOS Home Total Spent.dc.html` (Liquid Glass). The safe-to-spend card had grown dense; this flips
  it spent-first.
- **Both platforms:** the hero becomes **Total spent this cycle** (discretionary spend + bills already
  paid) in neutral label colour, with a composition caption ("X spending + Y bills paid", else the
  receipt count, else "Nothing spent yet this cycle"). New 4-segment bar / swatch language: solid tint =
  spending, solid secondary/outline = paid bills, hatch = bills still due, status tone = safe. Safe to
  spend demotes to a status-coloured figure (per-day sub); Bills still due gains a "N bills" count.
- **Footer REMOVED** per the user (compactness / screen real estate): the "= income − total spent −
  bills still due" formula is gone; only the overspent one-line warning remains. Setup shows the real
  total-spent hero + add-income prompt (no "—" placeholder).
- **Android:** `SafeToSpendCard`/`SafeToSpendBar`/`SafeToSpendStat` reworked (two-column stat strip);
  `HomeUiState.billsStillDueCount` added. Strings +`safe_to_spend_composition`/`_nothing_yet` + plural
  `safe_to_spend_bills_count`, −5 orphaned, ×16 locales. 7 Roborazzi goldens re-recorded.
- **iOS:** `HomeView.swift` safe-to-spend section reworked into the inset-list idiom (Safe to spend →
  Bills still due → Income this cycle); `billsStillDueCount`/`totalSpentThisCycle` added. xcstrings
  +`%@ spending + %@ bills paid` / `Nothing spent yet this cycle` / `%lld bills`, ×15 locales.

**Status (2026-08-10):** PORTED both, on branch `safe-to-spend-total-spent-first` off `main`.
Android `152cd64` (compile + detekt + lintDebug + Roborazzi green). iOS committed on-branch (sim BUILD
SUCCEEDED + rendered on iPhone 17 Pro). Both unpushed/unmerged.

## Duplicate-receipt save guard: block double-tapping Save (both) — 2026-08-10

- **Tester bug (both platforms):** double-tapping the Save/Finalize button on the receipt review
  screen could create a duplicate receipt (and duplicate line items). The save minted a fresh receipt
  id per call (`System.currentTimeMillis()` on Android, `Date()` on iOS) and only the *edit* path
  deleted old rows first, so a second invocation inserted a whole second receipt. The re-entry window
  is a fast double-tap before the screen switches away, plus the beat after save completes but before
  navigation/dismiss finishes.
- **Fix — re-entrancy guard + disabled button (both):**
  - Android (`UploadViewModel.finalizeUpload`): bail out unless `stage == UploadStage.REVIEW`
    (covers the SAVING and DONE re-entry windows; handlers run sequentially on the main thread and
    `stage` flips synchronously). Save button `enabled = stage == REVIEW`.
  - iOS: `ReceiptDraft.hasSaved` latch — `persist()` guards `!hasSaved` then latches (covers the
    edit path too); `ScanFlowView.save()` also guards `!draft.hasSaved` so the scan-quota increment
    can't double-count; both Save buttons in `ReviewView` get `.disabled(draft.hasSaved)`. A latch,
    not a transient `isSaving`, because the save is synchronous `@MainActor` and the realistic second
    tap lands *after* it completes.
- **No behaviour change** on the happy path — a single Save still writes exactly one receipt.

**Status (2026-08-10):** DONE both, **PUSHED** (unmerged — user opens the PRs). Android
`duplicate-receipt-save-guard` → `origin/Budgetty-Android` (`47f4e7b` fix + `9e7cedc` JVM regression
test, proven to fail without the guard; compile + detekt green; emulator-verified "2.50 € across 1
receipt"). iOS `duplicate-receipt-save-guard` → `origin/Budgetty-iOS` (`53892a6`, sim BUILD SUCCEEDED).
LEFT: open PRs + merge both.

## Code-review blocker fixes — behaviour parity (both) — 2026-08-10

A 12-agent code review of the Android app surfaced 10 blockers; all 10 were fixed on Android
(10 branches off `main`, pushed to `origin/Budgetty-Android`). Five are behaviour/logic bugs that had
an iOS twin — ported here. (The other five are Android-platform-specific: `flowOn` threading,
`enableEdgeToEdge` status-bar contrast, Compose `Text()` hardcoded strings + a Gradle lint guard,
CSV/PDF export ANR, and Compose-tip plurals — no iOS equivalent.)

- **Settings cross-account leak** — `AuthModel.signOut()`/`deleteAccount()` cleared no device-global
  `UserDefaults`, so a shared device leaked the previous account's app-lock PIN + biometric, setup
  quiz, dismissed tips, and Home/Insights layout. Fix: `UserState.clear()` (Settings.swift) called
  from both, covering the Account button and Forgot-PIN paths (both route through `signOut()`).
  *(Android #1.)*
- **Autopay stuck "Auto" chip** — `RecurringSheet` saved `autoPay` gated only on `!isIncome`, so a
  monthly+autopay bill switched to yearly/once kept the flag. Fix: `Recurring.autoPayEligible` /
  `isAutoPayActive` (monthly/weekly bills only), applied on save, edit-sheet load, and the Budget row
  chip. `RecurringPaidTests`. *(Android #3.)*
- **New-user 100/Thriving wellbeing score** — Subscriptions scored a full 100 from a 0% share (no
  data) as the only scored component. Fix: `WellbeingEngine.subscriptionsComponentScore` gates a 0%
  share on `minMonthsForZeroSubs` (2 months). `WellbeingEngineTests`. *(Android #8.)*
- **Case-only category rename** — `CategoryOps.saveCustom` compared names case-insensitively, so a
  case-only rename skipped the reference cascade (iOS edits the row in place, so no duplicate row like
  Android — but refs detached). Fix: compare exactly. *(Android #10.)*
- **Backup drops savings** *(Android #2)* — **no port needed:** iOS `Backup.swift` already serializes
  savings goals + nested contributions in `export`/`restore`, so the bug never existed here.

**Status (2026-08-10):** PORTED (4 code fixes; #2 already correct). iOS on branch
`fix/android-blocker-parity-2026-08` off `main`, **unpushed/unmerged** — sim BUILD SUCCEEDED, the
WellbeingEngine + RecurringPaid test suites green. Android side on 10 branches on
`origin/Budgetty-Android`. LEFT: push iOS branch + open PRs both sides.
