# Budgetty iOS — App lock: PIN + biometric

**Design brief for Claude design.** Produce the visual mockups for an optional
**App lock**: a **PIN** plus **Face ID / Touch ID** that gates the app on launch.
It's a privacy feature — Budgetty holds a full picture of someone's spending, income
and bills, and the user is never signed out. **Android gets the identical feature**
(Android repo's `APP_LOCK_DESIGN_REQUEST.md`); this brief renders it in the iOS
**Liquid Glass** language for a native SwiftUI build.

Deliver **light + dark**, **iPhone**, plus **iPad** where noted. Mockups as
HTML/CSS in the Budgetty iOS design project — match **Onboarding / Login** for the
full-screen lock, and the **Account / Settings** screen for the toggles.

> **Note for iOS:** the app already has a **Face ID** toggle in Settings (it's real
> on iOS today). This feature **absorbs and completes it** — add a **PIN fallback**
> (for when biometrics fail or aren't enrolled) and an **auto-lock delay**, so iOS
> matches Android's full app-lock. Don't design a second, separate biometric toggle —
> evolve the existing one into this Security group.

## How it works
- **Enable** in Settings: **App lock** on → **set a PIN** (enter, confirm) →
  optionally enable **Face ID / Touch ID**.
- **Lock screen** on **cold start** and on **return to foreground after the auto-lock
  delay**: a **numeric keypad** for the PIN + a **biometric affordance** that fires the
  system prompt (auto-triggered when biometric is on).
- **Auto-lock** delay: **Immediately / After 1 minute / After 5 minutes.**
- **Forgot PIN?** — the user is always signed in, so recovery = **re-authenticate** to reset the PIN.
- Native: **LocalAuthentication** (`LAContext`) for biometrics; PIN stored **hashed** in the Keychain — nothing leaves the device.

## Screens / states to draw
1. **Settings — Security group (off):** the **App lock** toggle off.
2. **Settings — Security group (on):** expanded — **Change PIN**, **Use Face ID / Touch ID**, **Auto-lock** (Immediately / 1 min / 5 min).
3. **Set PIN:** create — keypad + PIN dots, *"Set a PIN"*; **confirm** step (*"Confirm your PIN"*); **mismatch** (*"PINs don't match"*).
4. **Lock screen (PIN):** full-screen gate — Budgetty mark, *"Enter PIN"*, PIN dots, keypad, a **Face ID / Touch ID** icon, a **Forgot PIN?** link.
5. **Lock screen — wrong PIN:** *"Wrong PIN, try again"*, dots shake / redden.
6. **Biometric prompt moment:** the lock screen with the system Face ID sheet up.
7. **Auto-lock picker:** the three delay options.

## Copy reference
- **App lock**, *"Require a PIN to open Budgetty"*
- **Set a PIN**, **Confirm your PIN**, *"PINs don't match"*
- **Enter PIN**, *"Wrong PIN, try again"*
- **Use Face ID / Touch ID**
- **Auto-lock** — **Immediately** / **After 1 minute** / **After 5 minutes**
- **Forgot PIN?**

## States to make sure the mockups cover
- Security group off vs on (with the sub-rows + auto-lock picker).
- Set-PIN + confirm + mismatch.
- Lock screen: PIN entry, wrong-PIN error, and the biometric prompt moment.
- **Light and dark**, **iPhone**, and an **iPad** rendering of the lock screen + the Security group.

## Constraints / keep intact
- **Liquid Glass restraint** — the lock screen can use the app's ambient glass
  background (like Onboarding/Login); the keypad + dots stay clean and legible.
- **Reuse accent + error tokens**; don't invent a palette.
- **16-language tolerance**; never design to English width.
- **Free feature** — no paywall anywhere in this flow.
- Native + on-device: LocalAuthentication + a hashed PIN in the Keychain.

---

*Source of truth for content & behavior: the Android repo's
`APP_LOCK_DESIGN_REQUEST.md`. iOS build evolves the existing Face ID toggle into a
full App-lock Security group: LocalAuthentication + a hashed-in-Keychain PIN
fallback + auto-lock delay + a lock gate on scene-phase resume.*
