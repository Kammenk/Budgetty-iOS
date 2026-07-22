# Strings still English-only (need native translations or an Android key)

Generated with the l10n port. These iOS literals had no matching finished Android
translation, so they render in English in all 21 locales until translated.

- ` \(compareNoun.hasPrefix("vs ") ? "than" : "than") \(compareNoun.replacingOccurrences(of: "vs ", wit` — InsightsExtraCards.swift:186
- `Align receipt in frame` — ScanFlowView.swift:162
- `Apply to other “\(itemName)” items?` — CategoryMemorySheet.swift:27
- `Backup` — AccountView.swift:111
- `Bills are planned — not yet spent.` — HomeView.swift:259
- `Budgetty \(Self.appVersion) · Made with ❤️` — AccountView.swift:81
- `Budgetty is locked` — BiometricLockView.swift:26
- `Check your email` — LoginView.swift:84
- `Choose a receipt to see its details.` — HistoryView.swift:125
- `Clear` — HistoryFilters.swift:47
- `Customize` — HomeView.swift:95
- `Date Range` — DateRangeSheet.swift:44
- `Day` — RecurringSheet.swift:50
- `Delete Receipt` — ReceiptDetailView.swift:163
- `Delete this category?` — CustomCategorySheet.swift:66
- `Delete this receipt?` — ReceiptDetailView.swift:47
- `Enter Passcode` — BiometricLockView.swift:46
- `Face ID` — AccountView.swift:226
- `Go Premium to scan more — manual entry is always free.` — ScanFlowView.swift:274
- `How dates appear on receipts and lists.` — AccountView.swift:369
- `Item name` — ReviewView.swift:265
- `Left over` — IncomeCards.swift:43
- `Medium` — WidgetsView.swift:33
- `Merge keeps your current data and adds the backup. Replace deletes everything first.` — AccountView.swift:109
- `New` — CategoryPickerSheet.swift:111
- `New alerts will show up here.` — NotificationsView.swift:37
- `Nothing spent \(period.contextNoun)` — InsightsView.swift:671
- `Notifications` — AccountView.swift:148
- `Period: \(period.friendlyLabel)` — InsightsView.swift:300
- `Position the receipt, then capture` — ScanFlowView.swift:97
- `Pulling out items, prices and categories` — ScanFlowView.swift:311
- `Remember this change?` — CategoryMemorySheet.swift:26
- `Remove budget` — BudgetAmountSheet.swift:36
- `Reset password` — LoginView.swift:76
- `Review Receipt` — ReviewView.swift:106
- `Review items` — ReviewView.swift:77
- `Save receipt · \(draft.total.formatMoney())` — ReviewView.swift:227
- `Select a receipt` — HistoryView.swift:123
- `Send link` — LoginView.swift:79
- `Set a \(period.rawValue.lowercased()) budget` — BudgetView.swift:182
- `Set budget` — BudgetView.swift:380
- `Sign out of Budgetty?` — AccountView.swift:91
- `Signed in` — AccountView.swift:127
- `Small` — WidgetsView.swift:27
- `Subtotal` — ReviewView.swift:222
- `Tap Scan to add your first one` — HomeView.swift:416
- `Tap to show or hide a section. Use Edit to drag and reorder. Applies on iPhone.` — InsightsCustomize.swift:95
- `Totals don't quite match — items add up to **\(draft.subtotal.formatMoney())**, the receipt shows **` — ReviewView.swift:180
- `Touch & hold your Home Screen, tap ＋, and search “Budgetty” to add these.` — WidgetsView.swift:45
- `Unlock everything · Cancel anytime` — PaywallView.swift:112
- `Unlock with Face ID` — BiometricLockView.swift:37
- `Use Face ID to continue` — BiometricLockView.swift:27
- `Violet` — AccountView.swift:190
- `We'll email you a link to reset your password.` — LoginView.swift:82
- `You're all caught up` — NotificationsView.swift:35
- `You're keeping \(Int(rate * 100))% of your income this month.` — IncomeCards.swift:77
- `You've spent ` — InsightsExtraCards.swift:183
- `You've used all \(ScanQuota.freeLimit) free scans` — ScanFlowView.swift:271
- `Your preferred language for Budgetty.` — AccountView.swift:414
- `\((b.amount - spent).formatMoney()) remaining` — BudgetView.swift:174
- `\(Int((frac * 100).rounded()))% used` — InsightsExtraCards.swift:246
- `\(Int(frac * 100))% of monthly budget` — HomeView.swift:191
- `\(monthReceipts.count) receipts · \(Self.daysProgress())` — HomeView.swift:180
- `\(period.rawValue) budget` — BudgetView.swift:157
- `\(spent.formatMoney()) spent · \(Int(frac * 100))%` — BudgetView.swift:172
- `\(subCount) sub-budget\(subCount == 1 ? "" : "s")` — BudgetView.swift:384
- `of budget` — WidgetsView.swift:79
- `you@example.com` — LoginView.swift:120
- `−\(receipt.discount.formatMoney()) saved` — ReceiptDetailView.swift:70

## Added 2026-07-22 (premium parity pass)

The two `NotificationsView.swift` entries above are gone — that screen was deleted along with the
inert Notifications toggle, so its strings went with it.

These are now proper catalog keys (they were bare Swift literals before), still English-only:

- `billed annually` — PaywallView.swift · plan card
- `Billed each month` — PaywallView.swift · plan card
- `Tints buttons, highlights and the spending card.` — AccountView.swift · accent picker footer
- `Violet (default)` / `Sage` / `Ocean` / `Plum` — Accent.swift · accent names.
  **Android ships these untranslated too** (`AccentTheme`'s labels are hardcoded English in
  `AppSettings.kt`), and the colour names stay English inside Android's own translations of
  "Sage, Ocean and Plum" — so this is parity, not drift. Only "(default)" really wants translating.

Everything else this pass added came from Android's finished translations (the paywall benefit rows,
`BEST VALUE`, `Upgrade to add more`, `%@ / mo`) and is complete in all 15 target locales.

## Support & About rewire, 2026-07-22

Nothing new to translate. The rows that went away (`FAQ`, `Suggest a feature`) take their keys with
them, and the one row that gained a subtitle reuses Android's finished
`account_contact_subtitle` — "Report an issue, suggest a feature, or just say hello", 15 locales.

The support email's subject line ("Budgetty feedback") is **deliberately English on both platforms**:
it's a triage token in an inbox, not user-facing copy, and localizing it would only make filtering
harder. Android hardcodes it the same way.

## The widget extension is entirely English (pre-existing)

`BudgettyWidget/` has no string catalog of its own — `Localizable.xcstrings` belongs to the app
target — so every string the extension draws ships in English: the widget titles and descriptions in
the system picker, `of budget`, `Set a budget`, `No spending yet`, and now `Widget locked` /
`Unlock more widgets` on the locked card. Fixing it means adding a catalog resource to the widget
target, which needs project-file work rather than a code change. The app-side equivalents of the
locked-card copy *are* translated (`WidgetsView`'s slots card), so the strings themselves already
exist in 15 locales — they just can't be reached from the extension's bundle.
