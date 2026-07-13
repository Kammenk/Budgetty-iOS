# Budgetty iOS — Liquid Glass Adoption

Two documents in one:
- **Part A — Design brief** to hand to Claude design (produces the visual mockups for every screen).
- **Part B — Engineering adoption guide** (the concrete Apple/SwiftUI APIs). This is the spec I implement from once the mockups are approved.

Grounded in Apple's official guidance: *Adopting Liquid Glass*, *Applying Liquid Glass to custom views*, and the *Toolbars* HIG. iOS 26 (WWDC 2025). SwiftUI, native.

> **Core principle from Apple, read first:** Adopting Liquid Glass is **not** a rebuild from scratch. Most of it appears **automatically** when the app is compiled against the iOS 26 SDK with standard system components — bars, sheets, popovers, controls, lists all pick up the material for free. Our job is mostly to **get out of the system's way**: remove custom backgrounds/tints that fight the material, adopt a few opt-in behaviors, and apply *custom* glass **sparingly** to a small number of signature elements. Liquid Glass exists to bring focus to **content** — overusing it on custom controls is explicitly called out as a subpar experience.

---

# Part A — Design brief (for Claude design)

## Goal
Redesign **every existing Budgetty iOS screen** in the Liquid Glass language. Visual/material refresh, **not** an IA change — same screens, same flows, same feature set, new material and chrome.

Budgetty is a receipt-scanning budgeting app: photograph a receipt, it's extracted line-by-line in the cloud, and the app tracks spending, income, budgets, and insights. Tone: calm, trustworthy, money-serious but friendly. Default currency EUR. Ships in 20 languages, so **layouts must tolerate long translated strings** (don't design to English width).

## The material, in plain terms
Liquid Glass is a translucent, dynamic material that forms a **distinct functional layer for controls and navigation, floating above the content layer**. It blurs and refracts content behind it, reflects surrounding color/light, and reacts to touch. Content scrolls edge-to-edge underneath the chrome.

Design rules to apply everywhere:
- **Two layers, always separable.** Content layer (data, imagery, charts, receipts) vs. a floating chrome layer (tab bar, nav/toolbars, search, sheets, key buttons). Keep them visually distinct.
- **Content is the hero; chrome is quiet glass.** Emphasis and color come from the data (category hues, charts, receipt imagery), not from heavy card chrome. Reduce opaque panels and hard dividers; separate with translucency, blur, and soft shadow.
- **Be judicious with color in chrome.** Controls and navigation stay legible and defer to content; where color is used, it reads as system-adaptive (light/dark). Don't tint chrome heavily.
- **Concentric, capsule geometry.** Generous radii concentric with the device corners; buttons/pills are capsule; nested containers share a concentric radius relationship. Larger row heights and padding in lists/forms so content breathes.
- **Don't crowd the glass.** Give controls room to move; avoid overlapping/overcrowding chrome.
- **Don't over-glass.** Reserve the glass material for chrome and a *few* key functional controls — never on every content card. This is the single most important restraint.
- **Adaptive & accessible.** Correct in light and dark automatically; must degrade gracefully under Reduce Transparency, Increase Contrast, and Reduce Motion (solid, legible fallbacks — no effect that becomes illegible when transparency is off).
- **Title-style capitalization** in section headers (not ALL CAPS).

## Signature behaviors to show in the mockups
- **Floating tab bar that recedes on scroll** (minimizes on scroll-down, expands on scroll-up). Search, if in the tab bar, sits as its **own trailing section**.
- **Toolbars as glass**, items **grouped by function** (max ~3 groups), symbols over text, one **prominent** primary action (e.g. Done/Save) on the trailing edge.
- **Sheets as glass:** increased corner radius; half-sheets inset from the display edges so content peeks through beneath; full-height sheets become more opaque to hold focus.
- **Controls come alive on interaction** (slider/toggle knobs turn to glass; buttons morph into menus/popovers). Show the extra-large control size where labels need room.
- **iPad:** tab bar adapts into a **sidebar**; split-view master/detail with an optional **inspector**; **background-extension** so hero imagery appears to run edge-to-edge beneath the sidebar.

## Screens to redesign
Deliver **light + dark**, **iPhone**, plus **iPad / landscape** where the app is adaptive.

**Core / Phase 1**
1. **Tab shell** — floating glass tab bar; **Scan** as the prominent primary action; tab bar recedes on scroll; search as its own trailing tab section if present.
2. **Home** — dashboard: balance/summary, recent receipts, quick actions. Lighten cards; let summary numbers dominate; glass toolbar.
3. **History** — receipts/items list with search, sort, filters, price-range, date-range. Glass search field (bottom on iPhone), filter chips as capsules, day-header grouping, compact single-row receipts.
4. **Scan** — live camera capture → extraction/loading → result. **The signature flow**: viewfinder edge-to-edge, glass capture controls floating over it, a genuinely delightful "extracting your receipt" state, then results.
5. **Insights** — charts (donut/breakdown, trends), highlights, spending pace, top stores, income cards. Charts carry the color; surrounding chrome quiet.
6. **Budget** — single period (Monthly/Weekly), per-category budgeting, income & recurring bills; live-saving inputs.
7. **Account / Settings** — profile, language, currency, preferences, biometric lock, tester/premium state. Grouped lists in the new material, title-style headers.
8. **Paywall** — premium upsell (StoreKit). High-polish, glass, honest; clear plan cards and CTA.

**Phase 2**
9. **Onboarding** — first-run; showcase the glass aesthetic immediately.
10. **Login** — email/password (no anonymous auth). Clean, trustworthy, glass fields.
11. **Receipt Detail** — line items, totals (subtotal/discount/tax/extra charges/paid), store, category. Editable.
12. **Category Picker** — 3-column card grid, full-screen.
13. **Custom Category** create/edit + **Category Memory / rules** ("remember this store → category").
14. **"See all" categories sheet** — emoji-tile rows.
15. **Transaction sheets** — add/edit (glass detented sheets).
16. **Manual Entry** — add a receipt/expense by hand.
17. **Notifications** — settings/permissions.
18. **Support** — help/contact.
19. **Biometric Lock** — Face ID gate.
20. **Widgets gallery** — in-app preview/picker (3 types × 2 sizes); also refresh the **widget designs themselves**.

## Constraints / keep intact
- **Keep the brand + category color system** — muted, mockup-derived category hues with emoji icons. Recompose presentation; don't recolor the palette.
- **Keep IA and flows** — same screens/navigation/features. No new backend assumptions; no receipt-image storage.
- **20-language tolerance** — flexible, wrapping layouts; no fixed English-width labels.
- **Accessibility first** — contrast over glass, Dynamic Type, Reduce Transparency/Motion fallbacks.

## Recommendations (add these)
- **Ship a one-page material system first** — glass levels (chrome vs. control vs. sheet), radius scale, capsule button spec, spacing, elevation, and the reduced-transparency fallbacks. Every screen references it so the set stays coherent. Highest-leverage single deliverable.
- **Make Scan the hero moment** — floating capture controls over the viewfinder + a reassuring processing state. (The app currently shows one generic error for all scan failures; a graceful loading + retry/error state is a real quality win.)
- **Design the empty/loading/error states**, not just happy paths — cold-start skeletons, "no receipts yet," per-period empty Insights, scan-failed retry.
- **Modernize charts** with Swift Charts + quiet-chrome/loud-data (donut with outside % labels on leader lines, padded trend bars).
- **Refresh the app icon** as a **layered** design for Icon Composer (solid, overlapping, semi-transparent shapes; light/dark/clear/tinted variants) and refresh widgets to match.
- **Define the motion language once** — tab-bar recede, sheet morph-from-source, capture-button bloom — each with a Reduce-Motion variant.

---

# Part B — Engineering adoption guide (implement from this)

Order of operations when the mockups land. Do the "free" and "opt-in" tiers first; they deliver ~80% of the look. Reserve custom glass for the short list in Tier 3.

### Tier 0 — Baseline (free with the SDK)
- Build against the **iOS 26 SDK** in the latest Xcode; run on iOS 26. Standard SwiftUI components adopt Liquid Glass automatically.
- **Do NOT** set `UIDesignRequiresCompatibility` in Info.plist — that key opts *out* and freezes the old look. We want in.
- Audit and **remove custom backgrounds/appearances** on `NavigationStack`, `NavigationSplitView`, `TabView`, toolbars, sheets, and popovers. Custom fills/tints fight the material and the scroll-edge effect. Let the system own those backgrounds; use `ScrollEdgeEffectStyle` only if we need to distinguish the bar from content.
- Review standard controls (`Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, `TextField`) for new shapes/sizes and crowding; fix layouts that now overlap.
- Lists/forms: adopt **grouped `Form`** style; switch section headers to **title-style capitalization**.

### Tier 1 — Navigation opt-ins
- Tab bar recede: `TabView { … }.tabBarMinimizeBehavior(.onScrollDown)`.
- Search tab: `Tab(role: .search) { … }` so the system pins it to the trailing end.
- iPad adaptive: make the `TabView` **sidebar-adaptable**; use `NavigationSplitView` for master/detail and `inspector(isPresented:content:)` for the inspector panel. We already ship iPad adaptive layouts — migrate them onto these APIs.
- Hero imagery under sidebar/inspector: `backgroundExtensionEffect()`.
- Audit content **safe areas** next to sidebar/inspector so underlying content peeks correctly.

### Tier 2 — Toolbars, menus, sheets
- Group toolbar items by function (aim ≤3 groups); separate groups that share a background with `ToolbarSpacer` (or a fixed spacer). Keep text-labeled buttons in their own section so adjacent labels don't visually merge.
- Prefer **borderless SF Symbols** for actions (with an **accessibility label on every icon**); reserve text for actions symbols can't express (e.g. Edit).
- One **prominent** primary action (`.prominent`) on the trailing edge (Done/Save/Submit).
- Use standard **Back/Close** symbols; large title where it aids orientation (`prefersLargeTitles`).
- Hide the **toolbar item**, not its inner view, when hiding (`hidden(_:)`), or you get empty slots.
- Action sheets originate from their source control: `confirmationDialog(…)` with the source set.
- Sheets/popovers: remove custom visual-effect backgrounds; verify content isn't clipped by the larger corner radius and that peek-through around inset half-sheets looks right.

### Tier 3 — Custom glass (sparingly — the short list)
Apply real glass only to a few signature, non-standard elements. Candidates: the **Scan capture controls** over the viewfinder, and possibly a floating quick-action cluster. Everything else should ride Tiers 0–2.
- Base: `.glassEffect()` (regular variant, Capsule by default).
- Shape: `.glassEffect(in: .rect(cornerRadius: …))` for larger, non-capsule elements.
- Tint + interactivity: `.glassEffect(.regular.tint(.color).interactive())` (use **system** colors so it adapts).
- Glass buttons: `.buttonStyle(.glass)` / `.glassProminent`.
- **Performance + morphing:** wrap multiple glass elements in a `GlassEffectContainer(spacing:)`; give each a `glassEffectID(_:in:)` (with a `@Namespace`) so they morph during transitions; use `glassEffectUnion(id:namespace:)` to fuse several shapes into one at rest. Apply `.glassEffect()` **after** other appearance modifiers.
- Every custom glass element must have a **Reduce Transparency / Reduce Motion** fallback (solid, legible, no morph).

### Tier 4 — App icon & widgets
- Rebuild the app icon as **layered** artwork (foreground/mid/background), solid overlapping semi-transparent shapes, no baked-in blur/shadow/masking. Compose in **Icon Composer**; preview default/dark/clear/tinted against the updated grids; keep elements centered to avoid clipping.
- Refresh Glance-equivalent widget designs toward the material.

### Verification per screen
- Light + dark; iPhone + iPad/landscape.
- Toggle **Reduce Transparency**, **Increase Contrast**, **Reduce Motion** — confirm legible fallbacks.
- Dynamic Type at large sizes; longest-language strings.
- Profile custom-glass screens (Scan) for rendering cost; ensure `GlassEffectContainer` is used where multiple glass shapes coexist.

---

## Status
- [x] Brief written (this file).
- [x] Mockups from Claude design — delivered (`iOS Budgetty.dc.html` "Liquid Glass v2" + `iOS Material System.dc.html`, 25 screens, project `5b8c8470-…`).
- [~] Implementation — in progress on branch `liquid-glass-v2`, Part B tier order. Landed so far:
  - Tier 0: tint tokens refreshed to spec (`#6B50A8` light / `#C4AEFF` dark; `--tint-bg` .10/.14) in `Palette.swift`. Codebase already clean of material-fighting backgrounds; deployment target iOS 26.5 so baseline glass is free.
  - Tier 1: `TabView.tabBarMinimizeBehavior(.onScrollDown)`; Scan bottom-accessory upgraded to `.buttonStyle(.glassProminent)` (RootView).
  - Tier 3: Scan capture controls (close/flash/gallery/shutter) now real `.glassEffect(.regular.interactive())` inside a `GlassEffectContainer` (ScanFlowView).
  - Verified on iPhone 17 Pro simulator, **dark** appearance: Home, Scan capture, Insights all render correct glass chrome + intact category hues; build succeeds.
  - Remaining: per-screen polish pass against individual mockups, iPad/landscape + Reduce Transparency/Motion fallbacks, Tier 4 layered app icon & widget refresh.
