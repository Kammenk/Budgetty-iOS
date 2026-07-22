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
- **Account trim + full paywall benefit list + no AI wording** — ⚠️ **NO LONGER IN FLIGHT: merged on
  Android as `a8ef389`** (`6547e73` code, `af23d0f` onboarding AI, `6df1ef9` paywall compact-height;
  emulator-verified en+de on Pixel_6 + Pixel_Tablet). **This is now portable — treat it as pending,
  not blocked.** Everything below still applies.
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
  - ⚠️ **Product gap this exposes:** iOS Premium now honestly unlocks **2** things; Android unlocks
    **4** (it also caps recurring bills at `FREE_RECURRING_LIMIT` and ships 3 real accent tints).
    Closing that is a product decision — build the features, or accept a thinner iOS offer.
  - ⚠️ **Still dishonest elsewhere:** Account's "Accent color" row wears a **Premium** badge and
    pushes the paywall for a feature that doesn't exist (`AccountView.swift:189-203`). Fix with the
    rest of the Account trim.

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

- **Free-tier widget cap: 2 placed widgets** — 🚧 **IN FLIGHT on Android**, branch
  `widget-free-cap` (2026-07-21, build + detekt green, **not yet device-verified, not merged**).
  Widgets were 100% free on both platforms; this makes them the **5th premium gate**.
  **Do not port until the Android branch merges** — but read the API note below first, because
  the enforcement mechanism does **not** port and iOS needs its own design decision.

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

  **Scope note:** §10 above says "1 type on iOS vs 3 on Android" and is **stale twice over** —
  iOS now has 3 (`SpendingWidget`, `BudgetRingWidget`, `RecentReceiptsWidget`) and Android has
  **5** (Budget, Summary, This Week, Scan, Top Categories). Fix §10 when this ports.

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
- **Category rules, custom date range sheet, History tabs+sort+price-range, tester premium
  unlock (11-tap), Insights customize sheet, income/recurring, period stepper** — spot-checked
  2026-07-14, all present on iOS ✓.

---

*Last synced: 2026-07-21 — full audit against both codebases (PARITY.md was 5 days stale and wrong in
one place: the Account/paywall work had already merged on Android). Ported this pass: §11 category
split and §12 per-user data isolation, both on iOS branch `android-parity-cats-user-isolation`. Newly
found and still open: §13 Google Sign-In, §14 the two scan guards, plus §4's Account/paywall port and
the 69 English-only iOS literals in LOCALIZATION_TODO.md. Confirmed NOT gaps: the dual-currency fix
(server-side), Crashlytics (deliberately unmerged on iOS for the App Privacy label), and the
platform-specific tooling. Android `main`/`d0db412` · iOS `main`/`90b3d0d`.*
