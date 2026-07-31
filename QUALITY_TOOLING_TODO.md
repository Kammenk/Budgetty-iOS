# iOS Quality & Tooling TODO

Companion to the Android-side work. This is the **iOS half**, written to be worked in parallel — nothing
here depends on an Android change landing first.

Audited 2026-07-20 against `testflight-prep`. See [PARITY.md](PARITY.md) for feature drift; this doc is
strictly about **tooling**: crash reporting, tests, linting, instrumentation, ratings.

---

## Where we are

The honest summary: **this project has no quality tooling at all.**

| Category | State |
|---|---|
| Crash reporting | ❌ none — Firebase is Auth + Core only |
| Test target | ❌ **does not exist** (scheme has an empty `<Testables>`) |
| Snapshot tests | ❌ |
| Linter / formatter | ❌ no `.swiftlint.yml`, and **zero** run-script build phases |
| CI | ❌ no `.github/`, no `fastlane/`, no `ci_scripts/` |
| Logging | ❌ no `OSLog`/`Logger` — exactly one `print()` in 10,690 lines |
| Perf instrumentation | ❌ no MetricKit, no signposts |
| Accessibility | ⚠️ 4 `accessibilityLabel` in 3 files; **zero `accessibilityIdentifier` anywhere** |
| In-app review | ❌ never prompted |

Build settings worth knowing before you touch anything:

- `IPHONEOS_DEPLOYMENT_TARGET = 26.0` — iOS 26 only, so every modern API is fair game. No availability checks needed.
- `SWIFT_VERSION = 5.0` — Swift 5 language mode, **no strict concurrency**.
- `objectVersion = 77` + synchronized folders — **you can drop a `.swift` file into a folder and Xcode picks it up. No pbxproj surgery.** New *targets* still need the Xcode UI.
- `ENABLE_USER_SCRIPT_SANDBOXING = YES` — this **will** block a SwiftLint build phase until you handle it.
- 69 Swift files, ~10.7k lines, 2 targets (`Budgetty`, `BudgettyWidgetExtension`).

### ⚠️ Repo gotchas

- **You are on branch `testflight-prep`, not `main`** — it has unpushed commits (app icon, privacy manifests, target → 26.0). Per our workflow each task gets its own branch; check where you are before starting.
- **`build/` exists in the working tree.** It's gitignored but on disk, and contains the entire Firebase SPM checkout graph. **Every tool you configure must exclude it** or SwiftLint/tests will try to process the whole Firebase SDK.
- Only one file imports Firebase: [FirebaseBootstrap.swift](Budgetty/Auth/FirebaseBootstrap.swift). Keep it that way.

---

## Priority order

Ordered easiest → hardest. Items 1–3 are independently shippable in an afternoon.

### 1. In-app review prompt — ~30 min, zero dependencies ⭐ start here

Highest rating impact per line of code on this list, and iOS makes it trivial.

```swift
import StoreKit

@Environment(\.requestReview) private var requestReview
```

**Trigger point is already isolated:** [ScanFlowView.swift:288](Budgetty/Scenes/Scan/ScanFlowView.swift) `save()`.
That function only runs on a **successful, finalized scan** — failed reads and abandoned reviews never
reach it. That is exactly the "happy moment" the prompt wants.

```swift
private func save() {
    draft.persist(into: context, isManual: isManual)
    if !isManual { scansUsed += 1 }
    dismiss()
    // then: maybe ask for a review
}
```

Rules to respect:

- **Do not prompt on the first scan.** Gate on something like ≥3 successful scans and ≥3 days since install, persisted via `@AppStorage` (add keys to [Settings.swift](Budgetty/App/Settings.swift) alongside the existing `SettingsKey` values).
- Don't prompt inside the sheet — fire it **after** `dismiss()` lands, or the system alert fights the sheet transition.
- Apple hard-caps this at **3 prompts per user per 365 days** and may silently suppress it. You request; the system decides. Never treat it as guaranteed shown.
- **Never gate it behind a "do you like the app?" question.** That's a policy violation on Play and Apple discourages it. Ask everyone, unconditionally, at a good moment.
- It does nothing in DEBUG on device and shows an un-submittable dialog in the simulator. Don't chase that as a bug.

**Done when:** a fresh install that completes N scans sees the prompt exactly once, and a `#if DEBUG` env override exists to force it for verification.

---

### 2. Crashlytics — ~1–2 h

Right now a tester crash on TestFlight tells us **nothing**. This is the biggest real gap on iOS,
because it's also the platform with zero tests catching anything before release.

1. Xcode → the existing `firebase-ios-sdk` SPM entry → add the **`FirebaseCrashlytics`** product to the `Budgetty` target. No new package, no version bump — 11.15.0 already resolves it.
2. `import FirebaseCrashlytics` in [FirebaseBootstrap.swift](Budgetty/Auth/FirebaseBootstrap.swift). It already guards on `GoogleService-Info.plist` and calls `FirebaseApp.configure()` at line 31 — hook in right after, inside the same guard so a missing plist stays a no-op.
3. **Add the `upload-symbols` run script build phase.** Without it every crash is unsymbolicated hex and the whole exercise is pointless. Note this is the project's *first* build phase — see the `ENABLE_USER_SCRIPT_SANDBOXING` note above.
4. Set `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` for **Release** (verify — TestFlight needs real dSYMs).
5. Add a temporary force-crash button behind `#if DEBUG` to confirm reports land, then remove it.

**Blocked on a product decision, same as Android:** whether collection is default-on with an opt-out
toggle in [AccountView.swift](Budgetty/Scenes/Account/AccountView.swift). Europe-only user base → GDPR
applies. Recommendation is default-on + a real toggle, matching whatever Android ships so the two
don't diverge.

**Also required before release:** the App Privacy nutrition label in App Store Connect must declare
Crash logs / Diagnostics. Android has an equivalent Data safety change pending. Do not ship
Crashlytics without it.

**Done when:** a deliberate crash in a Release/TestFlight build appears in the Firebase console with a
symbolicated stack trace.

---

### 3. SwiftLint — ~1–2 h (mostly triage)

```yaml
# .swiftlint.yml
excluded:
  - build          # ← non-negotiable, or you lint the entire Firebase SDK
  - design
  - .build
```

Add it via SPM plugin or a run-script phase. **`ENABLE_USER_SCRIPT_SANDBOXING = YES` will fail the
build** — either add the SwiftLint binary to the phase's input/output file lists properly, or flip the
setting for that target. Don't disable sandboxing repo-wide without thinking about it.

Expect a large first-run warning count. Land the config and a rule set that passes **first**, then
tighten rule-by-rule. A linter that's red on day one gets ignored forever.

**Done when:** `swiftlint` exits clean on a fresh checkout and runs as part of the build.

---

### 4. `accessibilityIdentifier` pass — ~2–3 h, mechanical

**This is a prerequisite for items 5 and 6**, so it's worth doing even though it ships no user-visible
feature. Right now there is not a single stable selector in the app — any UI test or Maestro flow would
have to match on localized display strings, which breaks the moment someone runs it in German.

Add `.accessibilityIdentifier("...")` to the interactive elements on the main journeys:

| Screen | File |
|---|---|
| Login | [LoginView.swift](Budgetty/Scenes/Auth/LoginView.swift) |
| Root tabs / dock | [RootView.swift](Budgetty/Scenes/RootView.swift) |
| Home | [HomeView.swift](Budgetty/Scenes/Home/HomeView.swift) |
| Scan flow | [ScanFlowView.swift](Budgetty/Scenes/Scan/ScanFlowView.swift), [ReviewView.swift](Budgetty/Scenes/Scan/ReviewView.swift) |
| History | [HistoryView.swift](Budgetty/Scenes/History/HistoryView.swift) |
| Budget | [BudgetView.swift](Budgetty/Scenes/Budget/BudgetView.swift) |
| Insights | [InsightsView.swift](Budgetty/Scenes/Insights/InsightsView.swift) |
| Paywall | [PaywallView.swift](Budgetty/Scenes/Paywall/PaywallView.swift) |

Use a shared naming scheme — `scan.save`, `home.recentReceipts`, `login.email` — and **use the same
strings Android uses for its test tags**, so one Maestro flow can drive both platforms.

While you're in these files: the real `accessibilityLabel` coverage is 4 labels total, which is a
genuine VoiceOver problem, not just a testing one. Icon-only buttons (the `circleButton` helpers in
ScanFlowView, the dock) need labels regardless.

**Done when:** every control on the launch → scan → save journey has a stable identifier, and none of
them are localized strings.

---

### 5. Unit test target — ~half a day to stand up

There is nothing to extend, so this is "create a target" work, not "write a test" work.

- New target → **Swift Testing** (`import Testing`, `@Test`), not XCTest. New project, no legacy to carry.
- Wire it into the shared scheme's `<Testables>` (currently empty).
- Add a `.xctestplan` so CI has one thing to invoke.

Best first targets — pure logic, no UI, highest bug-per-line risk:

- [Money.swift](Budgetty/Model/Money.swift) — currency math. Test rounding and the 9 supported European currencies.
- [ReceiptDraft.swift](Budgetty/Scenes/Scan/ReceiptDraft.swift) — the `droppedShortfall` logic in `ReviewView` implies real edge cases here.
- [Categories.swift](Budgetty/Category/Categories.swift) — the canonical 50-category set, and the rule-matching in [CategoryRule.swift](Budgetty/Model/CategoryRule.swift) (Cyrillic-safe keys — Android had a bug here).
- [AppDate.swift](Budgetty/Support/AppDate.swift) — period/range math feeding Insights.

⚠️ **Note for parity:** Android's equivalent bug class — the receipt article-count guard rejecting
multi-buy receipts, and the dual-currency BG euro-changeover double-count — both live in the *extraction
pipeline*, which is server-side and shared. But the **client-side guards** are ported per-platform.
Check whether [ReceiptExtractor.swift](Budgetty/Scenes/Scan/ReceiptExtractor.swift) carries the same
guard logic Android does, and if so, port Android's regression cases. That's the single highest-value
test on this list.

**Done when:** `xcodebuild test` runs green from the command line.

---

### 6. Maestro E2E — ~half a day for a first flow, longer for a suite

The strategic reason to care: **one YAML flow drives both iOS and Android.** Given we maintain
PARITY.md by hand, a shared Maestro suite turns feature-parity from a markdown promise into something
CI actually checks.

- Needs item 4 (identifiers) first.
- The hard part is **auth** — the app gates on Firebase sign-in. Either use the existing
  `SKIP_AUTH=1` DEBUG env hook ([BudgettyApp.swift:54](Budgetty/BudgettyApp.swift)) or drive the real
  test account. The `SKIP_AUTH` route is far less flaky.
- Useful existing DEBUG hooks to build flows on: `ONBOARDING=skip`, `QUIZ=skip`, `SCAN_PHASE=review`,
  `USE_STUB_EXTRACTOR=1`. **`USE_STUB_EXTRACTOR=1` is the important one** — it makes scan flows
  deterministic and offline, with no API cost per test run.
- First flow: launch → skip onboarding → home renders → open scan → stub extract → save → receipt
  appears in History.

**Done when:** one flow passes on an iOS simulator, and the same YAML (or a near-identical sibling)
passes on an Android emulator.

---

### 7. MetricKit — ~2 h, do after Crashlytics

First-party, no dependency. Gives real-user launch times, hang rates, memory, and disk writes.

Xcode Organizer already shows this aggregated, so **the marginal value is lower than it looks** — take
it only once Crashlytics is in and you want per-build correlation. Apple flags hang rate red above 1%
of sessions, and anything over 250 ms counts as a hang.

Worth pairing with an `OSLog`/`Logger` adoption pass, since the app currently has no logging at all —
that's a bigger day-to-day debugging win than the metrics themselves.

---

### 8. Snapshot tests via swift-snapshot-testing — ~1 day, ongoing cost

Needs item 5 first. Real value given the Liquid Glass work (visual regressions are exactly what this
catches), but golden images need a review process and repo storage, and they'll churn hard while the
design is still moving. **Defer until the Liquid Glass redesign is settled.**

---

### 9. CI on macOS runners — hardest item here

Deliberately last. iOS CI needs macOS runners plus code signing, and signing is **already a known
blocker** — automatic signing demands a Development profile even for Release archives, which needs ≥1
registered device, and the team currently has zero. **Do not start this until an iPhone has been
plugged in once and the archive path works locally.**

Build-and-test-only CI (no signing, no archive) is achievable sooner and still catches compile breaks
and failing tests. That's the version to aim for first.

---

### Not now: Swift 6 language mode

The project targets iOS 26 but runs `SWIFT_VERSION = 5.0` with no strict concurrency, so SwiftData and
SwiftUI concurrency bugs surface as runtime flakiness instead of compile errors. Genuinely worth fixing
eventually.

But it is **not** the quick build-setting flip it appears to be — turning it on across a SwiftData +
`@Observable` codebase surfaces a large diagnostic count, and fixing those means real changes to actor
isolation in the model layer. Do it as its own dedicated branch, not folded into another task, and not
during the release push.

Reasonable middle step: set strict concurrency to **`minimal` → `targeted`** and clear those first.

---

## Suggested parallel split

If Android and iOS are being worked simultaneously:

| Do in lockstep (decide once, apply to both) | Independent |
|---|---|
| Crashlytics opt-out UX + privacy declarations | Everything else on this list |
| In-app review trigger conditions (N scans, M days) | |
| Test-tag / accessibility-identifier naming scheme | |

Those three need one decision each, applied identically to both platforms — otherwise we get drift
that PARITY.md has to track forever.
