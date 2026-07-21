# Budgetty-iOS
Budgeting app that allows you to scan your receipts and logs each transaction so that you can keep track of everything you spend on.

## Building

No special flags or setup — open in Xcode and build, or:

```sh
# Build
xcodebuild build -scheme Budgetty -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Unit tests — Swift Testing, driven by Budgetty.xctestplan
xcodebuild test -scheme Budgetty -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Lint (what CI should gate on)
swiftlint lint --strict
```

## Linting

SwiftLint runs from the **command line only** — it is deliberately *not* wired into the build.
Config: [`.swiftlint.yml`](.swiftlint.yml) (deliberately green today; see the comments before
enabling more rules). Install with `brew install swiftlint`.

> [!NOTE]
> An earlier iteration ran SwiftLint as an SPM build-tool plugin for inline warnings. It was removed:
> Xcode requires a per-machine trust approval before running a build-tool plugin from a remote
> package, and when that approval prompt doesn't appear, **every build fails on every destination**
> with `Validate plug-in "SwiftLintBuildToolPlugin"` — which misleadingly looks like a broken
> simulator or scheme. Running lint from CI/CLI gets the same enforcement without breaking a fresh
> checkout. Don't re-add the plugin without solving that trust gate first.

End-to-end (Maestro) flows and how to run them on either platform: [`.maestro/README.md`](.maestro/README.md).
