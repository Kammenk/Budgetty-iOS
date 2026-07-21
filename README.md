# Budgetty-iOS
Budgeting app that allows you to scan your receipts and logs each transaction so that you can keep track of everything you spend on.

## Building

> [!IMPORTANT]
> **First build after checkout will fail** with:
> ```
> Validate plug-in "SwiftLintBuildToolPlugin" in package "swiftlintplugins"
> ** BUILD FAILED **
> ```
> This is expected, and it is **not** a problem with your simulator or scheme — it fails on every
> destination. Xcode requires a one-time approval before it will run a build-tool plugin that comes
> from a remote Swift package.
>
> **Fix (once per machine):** build in Xcode and click **“Trust & Enable”** on the plugin prompt.
> **From the command line:** pass `-skipPackagePluginValidation`.

SwiftLint runs as an SPM build-tool plugin on the app target, so lint warnings appear inline on every
build. Config: [`.swiftlint.yml`](.swiftlint.yml) (deliberately green — see the comments before
enabling more rules).

```sh
# Build
xcodebuild build -scheme Budgetty -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation

# Unit tests — Swift Testing, driven by Budgetty.xctestplan
xcodebuild test -scheme Budgetty -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation

# Lint standalone (what CI should gate on)
swiftlint lint --strict
```

End-to-end (Maestro) flows and how to run them on either platform: [`.maestro/README.md`](.maestro/README.md).
