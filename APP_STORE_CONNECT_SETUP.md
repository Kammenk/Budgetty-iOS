# App Store Connect — Subscription Setup

Set up Budgetty Premium's auto-renewing subscriptions. The **Product IDs must match the app code
exactly** (`StoreManager.swift`) or the app can't find the products.

| Field | Yearly | Monthly |
|---|---|---|
| **Product ID** (permanent — cannot be changed) | `com.budgetty.premium.yearly` | `com.budgetty.premium.monthly` |
| Duration | 1 Year | 1 Month |
| Price | €59.99 | €5.99 |

⚠️ **These must match Google Play, and Play is the reference.** Play sells the same two products at
**EUR 59.99 / EUR 5.99**. Verify against the Play Console before changing either store — **never**
against `Budgetty.storekit` or paywall copy, which are local fixtures. Getting this backwards once
put the wrong prices live (2026-07-22).

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

**Both**
- [ ] **Tax Category** — required on each subscription. Easy to miss: App Store Connect doesn't name
      the field it's waiting on, so the product just sits at *Missing Metadata* and is never returned
      to the app. Pick the category that matches how you sell (Budgetty is an app subscription, not
      a physical good or a regulated service) — confirm with your accountant if in doubt, since it
      drives what tax Apple collects on your behalf.

⚠️ Product IDs are permanent once saved — triple-check the spelling.

## 3. Pricing
- [ ] Each subscription → **Subscription Prices → Edit Price → "Recalculate prices for all countries
      or regions"** → base region **Germany (EUR)** → **€59.99** (yearly) / **€5.99** (monthly).
      App Store Connect fills the other 174 regions.

⚠️ **Apple's price is the customer-facing, tax-INCLUSIVE figure** (the separate *Proceeds* column is
what you receive). Play is the opposite — its box takes a tax-*exclusive* number, which is why the
same €59.99 is entered there as `49.99`. Don't copy a figure between the two consoles.

The paywall no longer hardcodes anything: `PlanPricing` derives both the "/ mo" line and the saving
badge from the loaded `Product`s, so re-pricing here can't leave stale copy. Note the saving differs
per storefront because Apple's price points aren't proportional (the same ladder is ≈ −16% in USD and
≈ −29% in EUR) — which is precisely why it must stay derived and never be restated as a literal.

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
- ⚠️ **`Budgetty.storekit` is a TEST FIXTURE, not a record of what customers pay.** It's kept at
  €59.99 / €5.99 to mirror production, but it is what the Simulator reads — so a sim run can never
  contradict it, and it must never be used as evidence of a live price. The same goes for anything
  in the app source. Prices live only in the two store consoles. (Treating this file as a source of
  truth is what put the wrong prices live on 2026-07-22.)
- The app has **no fallback prices**: when StoreKit hasn't loaded the products the paywall renders
  "—" and the Subscribe button is disabled, rather than showing a number nobody is charged.
- If products don't appear on device: check the Paid Apps agreement is Active, the bundle ID
  matches, every required field (including **Tax Category**) is filled, and the subscription status
  is at least "Ready to Submit." A product stuck at *Missing Metadata* is silently omitted from
  `Product.products(for:)` — the paywall simply renders no plans, with no error.
- See `DEVICE_TEST_CHECKLIST.md` for the rest of the on-device pass.
