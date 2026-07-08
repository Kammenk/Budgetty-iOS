# Budgetty iOS — Device Verification Checklist

Things that can't be verified in the Simulator and need a real iPhone + iPad. Run through these
before shipping. Test account: **kamen.kostov94+budgetty@gmail.com / Budgetty2026** (free tier).

Build to a device from Xcode (real signing team, not the "Sign to Run Locally" ad-hoc identity used
for the sim). Use a **Debug** build for most of this; use a **Release/TestFlight** build for the
StoreKit section.

---

## 1. Camera scan (iPhone) — cannot run on Simulator
- [ ] Tap **Scan receipt** → the camera opens (not the photo library).
- [ ] Capture a real receipt → "Reading…" → Review screen with store, date, and line items.
- [ ] Save → it appears on Home "Recent receipts" and in History.
- [ ] Poor photo (blurry/angled) → the "Couldn't read the receipt" state with **Try again**.
- [ ] Confirm the camera permission prompt text reads correctly on first use.

## 2. Real auth (iPhone) — Firebase, no anonymous
- [ ] Fresh install → **Login** screen (not skipped).
- [ ] Sign **up** a new throwaway email → lands in the app; Account shows the email + initials.
- [ ] Sign out → back to Login. Sign **in** with the test account → succeeds.
- [ ] "Forgot Password?" → enter the email → confirmation alert; reset email arrives.
- [ ] Wrong password → inline error message (not a crash).

## 3. Widgets (iPhone + iPad) — WidgetKit, cannot place on Simulator home
- [ ] Long-press Home Screen → **+** → search "Budgetty" → the widget gallery shows Small + Medium.
- [ ] Add the **Small** spend/budget widget → shows this month's total + budget bar with real data.
- [ ] Add the **Medium** recent-receipts widget → shows recent receipts.
- [ ] Scan/add a receipt in-app → widget updates within a refresh cycle (or after reopening the app).
- [ ] Repeat on iPad Home Screen.

## 4. iPad adaptive layout (on-device, both orientations)
- [ ] Portrait: floating top tab bar; tap the expand glyph → sidebar expands to a plain label list
      (Home/History/Insights/Budget) with Scan + Account in the footer, **no dashboard card**.
- [ ] **Scan receipt** accessory pill is reachable in both orientations.
- [ ] Rotate to **landscape**:
  - [ ] History → **two-pane**: receipts list on the left, selected receipt detail on the right;
        tapping a row updates the right pane (doesn't push).
  - [ ] Insights → three columns of cards.
  - [ ] Budget → income | recurring side by side, denser category grid.
  - [ ] Home / Paywall → content centered, not edge-to-edge.
- [ ] Split View / Slide Over (multitask with another app) → layout degrades gracefully to a
      single readable column when narrow.

## 5. StoreKit / subscriptions — needs App Store Connect + sandbox
Prereq (account owner): in **App Store Connect**, create a subscription group with two auto-renewing
products whose IDs exactly match the app:
`com.budgetty.premium.yearly` and `com.budgetty.premium.monthly`. Sign the **Paid Apps** agreement
(banking + tax). Create a **Sandbox tester** Apple ID.
- [ ] On device, sign in to the Sandbox account (Settings → App Store → Sandbox, or when prompted).
- [ ] Open the Paywall → real localized prices load for Yearly/Monthly.
- [ ] Tap **Subscribe** → the system purchase sheet appears → confirm → app flips to Premium
      (Account shows "Premium", paywall shows "You're Premium ✓").
- [ ] Delete + reinstall → **Restore purchases** re-grants Premium.
- [ ] Verify the 11-tap tester unlock (Support & About → tap version 11×) still works independently.

## 6. Biometric lock (device with Face ID / Touch ID)
- [ ] Enable Face ID lock in Account → background/reopen → biometric prompt gates the app.
- [ ] Cancel/fail → stays locked; success → unlocks.

## 7. General smoke
- [ ] Light + dark mode across all tabs.
- [ ] Currency + language changes apply app-wide.
- [ ] No console errors on launch; scan round-trips to the live Cloud Function.

---

Notes:
- The local `Budgetty.storekit` config only affects **Run** in Xcode; a TestFlight/Release build
  uses real App Store / sandbox StoreKit, so it won't interfere.
- Simulator-verified already (no need to re-check on device unless something looks off): all screen
  layouts in portrait, the adaptive tab bar chrome, and that the StoreKit products load.
