# Maestro E2E flows

One YAML drives **both** platforms. The selectors are the shared accessibility identifiers from
[`AccessibilityID.swift`](../Budgetty/Support/AccessibilityID.swift), which are kept identical to
Android's Compose test tags, so the same flow's `assertVisible`/`tapOn` steps resolve on iOS and
Android alike. This turns feature parity from a note in `PARITY.md` into something CI can check.

## The flow

[`receipt_scan.yaml`](receipt_scan.yaml) — the core smoke journey: **launch → Home → open Scan →
(stub) extract → save → the receipt appears in History.** It exercises auth, the scan pipeline, save,
and cross-tab navigation in one pass.

## Test hooks

The flow drives the app entirely through its DEBUG launch hooks, so no network, no camera, and no
flaky sign-in are involved:

| Argument | Effect |
|---|---|
| `SKIP_AUTH=1` | bypass the Firebase login gate |
| `ONBOARDING=skip` | skip first-run onboarding |
| `QUIZ=skip` | skip the post-signup Insights quiz |
| `USE_STUB_EXTRACTOR=1` | canned, offline receipt extraction (deterministic, zero API cost) |
| `SCAN_PHASE=review` | auto-run the stub extraction on scan open (no camera/photo-picker needed) |

**How the arguments reach the app:** Maestro delivers `launchApp.arguments` as *intent extras* on
Android and as *launch arguments* on iOS. iOS can't set process environment variables this way, so the
hooks are read through [`LaunchFlags`](../Budgetty/Support/LaunchFlags.swift), which checks the
environment (Xcode scheme / screenshot scripts) **and** the launch-argument/UserDefaults domain.

## Running

Build + install the app first (Maestro launches an already-installed build), then:

**iOS** (verified — passes on the iOS 26 simulator):
```sh
xcodebuild build -scheme Budgetty -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcrun simctl install "iPhone 17 Pro" <path>/Budgetty.app
maestro --device <sim-udid> test .maestro/receipt_scan.yaml
```

**Android** — the flow is identical except for the app id. Change the header line to
`appId: com.budgetty.app` (the only platform-specific line) and run against an emulator:
```sh
maestro --device emulator-5554 test .maestro/receipt_scan.yaml
```
The Android app already reads these hooks (SKIP_AUTH via a launch/intent extra), so no app change is
needed there.
