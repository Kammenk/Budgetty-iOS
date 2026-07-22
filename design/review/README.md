# App Review artifacts

## `paywall-review-screenshot.png`

The screenshot attached to **Review Information → Screenshot** on the App Store Connect
subscriptions (app id `6791947528`, group *Budgetty Premium*). App Review looks at this to see what
the subscription actually offers.

Captured 2026-07-22 from `1c207fa`+, **iPhone 17 Pro** simulator, `SHOW_SCREEN=paywall`.

**It was briefly an iPad capture.** On iPhone the Monthly card used to be clipped by the pinned
footer — the benefit list reached six rows and the footer gained the 3.1.2-required Terms/Privacy
links — so the first version of this file was shot on iPad to get the whole offer in frame. That was
treating the symptom: the clipping was a real layout bug on the shipping paywall, not a screenshot
problem. It's fixed (the hero compresses on short screens), so this is a phone capture again, which
is what a reviewer should see.

**It shows USD ($49.99 / $4.99) and that is correct.** The simulator's App Store storefront is US;
Apple generated those from the €59.99 / €5.99 euro base. Sanity: 49.99 ÷ 12 = $4.17 (the "/ mo"
line), and 12 × 4.99 = 59.88, so the saving is 16.5% → the "−16%" badge. Euro storefronts render
€59.99 / €5.99.

### ⚠️ Regenerate this whenever the paywall or the prices change

A stale review screenshot is the same class of problem that already bit this project twice today: it
looks authoritative and nothing fails when it drifts. The one this replaced still showed €29.99 /
€3.99, prices that were never live on the App Store.

```
xcodebuild -project Budgetty.xcodeproj -scheme Budgetty -destination "id=<iphone-udid>" \
  -derivedDataPath build/dd -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
xcrun simctl install <iphone-udid> build/dd/Build/Products/Debug-iphonesimulator/Budgetty.app
SIMCTL_CHILD_SKIP_AUTH=1 SIMCTL_CHILD_ONBOARDING=skip SIMCTL_CHILD_SHOW_SCREEN=paywall \
  xcrun simctl launch <iphone-udid> com.budgetty.Budgetty
xcrun simctl io <iphone-udid> screenshot design/review/paywall-review-screenshot.png
```

Check both plan cards are fully above the footer. If they aren't, the paywall has outgrown the
screen again — fix the layout rather than reaching for a taller device.

Then re-upload it in App Store Connect — the file here is a record of what was submitted, not the
submission itself. **Check the rendered prices against the console before uploading**; never against
`Budgetty.storekit`, which is a Simulator fixture (see `APP_STORE_CONNECT_SETUP.md`).
