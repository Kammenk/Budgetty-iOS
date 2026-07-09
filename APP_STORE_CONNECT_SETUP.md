# App Store Connect — Subscription Setup

Set up Budgetty Premium's auto-renewing subscriptions. The **Product IDs must match the app code
exactly** (`StoreManager.swift`) or the app can't find the products.

| Field | Yearly | Monthly |
|---|---|---|
| **Product ID** (permanent — cannot be changed) | `com.budgetty.premium.yearly` | `com.budgetty.premium.monthly` |
| Duration | 1 Year | 1 Month |
| Price | €29.99 | €3.99 |

Bundle ID: **`com.budgetty.Budgetty`**. StoreKit 2 is used, so **no App-Specific Shared Secret** is
needed.

---

## 0. One-time account setup (do first)
- [ ] Apple Developer Program membership active ($99/yr).
- [ ] **Paid Applications Agreement** signed + **banking + tax** completed — App Store Connect →
      **Business**. Must show **Active**, or subscriptions won't function. (Most common blocker.)
- [ ] App record exists for bundle ID `com.budgetty.Budgetty` (Apps → +).

## 1. Create the subscription group
- [ ] App → **Monetization → Subscriptions → Create** (group).
- [ ] Group **Reference Name:** `Budgetty Premium` (internal only).
- Both plans live in one group so a user holds only one at a time and can upgrade/downgrade.

## 2. Add the two subscriptions (Create twice, inside the group)
**Yearly**
- [ ] Reference Name: `Premium Yearly` (internal)
- [ ] **Product ID:** `com.budgetty.premium.yearly`  ← exact
- [ ] Subscription Duration: **1 Year**

**Monthly**
- [ ] Reference Name: `Premium Monthly`
- [ ] **Product ID:** `com.budgetty.premium.monthly`  ← exact
- [ ] Subscription Duration: **1 Month**

⚠️ Product IDs are permanent once saved — triple-check the spelling.

## 3. Pricing
- [ ] Each subscription → **Subscription Prices → Add** → base region (e.g. Germany/EUR) → closest
      point to **€29.99** (yearly) / **€3.99** (monthly). App Store Connect fills the other regions.

## 4. Localization (shown to users)
- [ ] Each subscription → **Add localization** (English at minimum):
  - Display Name: e.g. "Budgetty Premium (Yearly)" (≤ 30 chars)
  - Description: e.g. "All Premium features, billed annually."
- [ ] Set the **group's** localized display name (e.g. "Budgetty Premium").

## 5. Review information (required to submit)
- [ ] Each subscription: attach a **review screenshot** of the Paywall + optional review notes.

## 6. Submit for review
- [ ] Mark each **Cleared for Sale** / add to availability.
- [ ] The **first** subscription usually must be submitted **attached to an app version** (add them
      to the version's "In-App Purchases and Subscriptions" section, then submit the build). After
      the first, IAPs can be submitted independently.
- Status flow: *Missing Metadata → Ready to Submit → Waiting for Review → Approved*.

## 7. Sandbox tester (for testing)
- [ ] **Users and Access → Sandbox → Test Accounts → +**.
- [ ] Use a brand-new email (e.g. a `+sandbox` alias), NOT a real Apple ID.

## 8. Test on device
- [ ] Products only need to be **"Ready to Submit"** to sandbox-test (not yet Approved).
- [ ] Install a real device build; sign into the Sandbox account (iOS **Settings → App Store →
      Sandbox Account**, or when prompted at purchase).
- [ ] Paywall shows real prices → **Subscribe** → confirm → app flips to Premium.
- [ ] Reinstall → **Restore purchases** re-grants Premium.
- [ ] Confirm the 11-tap tester unlock (Support & About, tap version 11×) still works independently.

---

## Notes
- **Simulator testing needs none of this** — the bundled `Budgetty.storekit` config (selected in the
  shared scheme's Run options) drives the flow in the Simulator. Console + sandbox is only for
  real/TestFlight builds.
- The app's fallback prices and the `.storekit` config already use €29.99 / €3.99, so the paywall
  looks identical whether or not live products load.
- If products don't appear on device: check the Paid Apps agreement is Active, the bundle ID
  matches, and the subscription status is at least "Ready to Submit."
- See `DEVICE_TEST_CHECKLIST.md` for the rest of the on-device pass.
