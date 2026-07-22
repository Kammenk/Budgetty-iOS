//
//  PaywallView.swift
//  Budgetty
//
//  Budgetty Premium paywall from the mockup: violet hero, feature list, Yearly/Monthly plan cards,
//  and a subscribe CTA. Purchases run through StoreManager (StoreKit 2); prices come from the loaded
//  products with a static fallback. The hidden 11-tap tester unlock stays as a separate path.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @AppStorage(SettingsKey.premium) private var premium = false
    @State private var wide = false
    /// Short screen — every iPhone in portrait. Drives the dense hero/spacing below.
    @State private var shortScreen = false
    @State private var busy = false

    private enum Plan { case yearly, monthly }
    @State private var plan: Plan = .yearly

    private var selectedProduct: Product? {
        store.product(plan == .yearly ? StoreManager.yearlyID : StoreManager.monthlyID)
    }
    /// Real localized price from StoreKit. Until the product loads there is no honest price to
    /// show — and the CTA is disabled in exactly that case — so it renders as a dash rather than a
    /// number we made up. (Happens on a Simulator with no StoreKit configuration selected.)
    private func price(_ id: String) -> String {
        store.product(id)?.displayPrice ?? "—"
    }

    /// The yearly plan's cost per month, in the product's own currency and locale.
    ///
    /// Derived, never typed. This line used to read a hardcoded "€2.50 / month" — arithmetic on a
    /// €29.99 that App Store Connect is free to change, which would have made the paywall quietly
    /// lie. Same defect `PremiumBenefits` exists to prevent, one screen over.
    private var yearlyPerMonth: String? {
        guard let yearly = store.product(StoreManager.yearlyID) else { return nil }
        return PlanPricing.perMonth(yearly: yearly.price).formatted(yearly.priceFormatStyle)
    }

    /// What the yearly plan saves against paying monthly for a year, rounded down. Nil unless both
    /// products are loaded *and* yearly is genuinely cheaper — if the pricing ever stops being a
    /// saving, the badge drops the claim instead of inventing one.
    private var yearlySavingsPercent: Int? {
        guard let yearly = store.product(StoreManager.yearlyID),
              let monthly = store.product(StoreManager.monthlyID) else { return nil }
        return PlanPricing.savingsPercent(yearly: yearly.price, monthly: monthly.price)
    }

    // What Premium unlocks lives in `PremiumBenefits` so every surface agrees and each number comes
    // from the constant enforcing it — see the audit note there for why this list shrank.
    private let features = PremiumBenefits.all

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                Group {
                    if wide {
                        // iPad landscape: features on the left, plans on the right.
                        HStack(alignment: .top, spacing: 28) {
                            featuresColumn.frame(maxWidth: .infinity)
                            plansColumn.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: shortScreen ? 14 : 20) {
                            featuresColumn
                            plansColumn
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, shortScreen ? 14 : 20)
            }
            .adaptiveReadableWidth(wide ? 900 : Dimens.contentMaxWidth)
        }
        .ignoresSafeArea(edges: .top) // hero runs under the status bar (mockup)
        .trackWideLandscape($wide)
        .trackCompactHeight($shortScreen)
        .background(Palette.groupedBackground)
        // Mockup chrome: no title bar — the violet hero runs to the very top with a glass close
        // button floating over it.
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) { closeButton }
        .safeAreaInset(edge: .bottom) { footer }
    }

    /// Glass close circle over the hero (mockup: white-alpha circle with an ✕).
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier(A11y.Paywall.close)
        .padding(.trailing, 16)
        .safeAreaPadding(.top, 8)
    }

    private var featuresColumn: some View {
        VStack(spacing: shortScreen ? 10 : 14) { ForEach(features) { featureRow($0) } }
    }

    private var plansColumn: some View {
        VStack(spacing: 10) {
            planCard(.yearly, title: "Yearly",
                     detail: yearlyPerMonth.map { String(localized: "\($0) / mo") },
                     price: price(StoreManager.yearlyID),
                     sub: String(localized: "billed annually"),
                     badge: bestValueBadge)
            planCard(.monthly, title: "Monthly", detail: String(localized: "Billed each month"),
                     price: price(StoreManager.monthlyID), sub: nil, badge: nil)
        }
    }

    /// Quantifies the saving only when it can be computed from the loaded products. The number is
    /// appended as a bare "· −37%" rather than a "SAVE 37%" sentence so the badge stays correct in
    /// all 16 languages off one already-translated phrase.
    private var bestValueBadge: String {
        let base = String(localized: "BEST VALUE")
        guard let percent = yearlySavingsPercent else { return base }
        return "\(base) · −\(percent)%"
    }

    // On a phone the hero is what pushes the plan cards under the pinned footer: the offer is the
    // point of this screen, so the ornament gives up the space rather than the thing being sold.
    // Same call Android made on its short-window paywall (6df1ef9) — decoration yields to content.
    // The badge stays large; only its padding and the glyph tile shrink, so the mockup still reads.
    private var hero: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: shortScreen ? 18 : 22, style: .continuous)
                .fill(.white.opacity(0.2))
                .frame(width: shortScreen ? 56 : 72, height: shortScreen ? 56 : 72)
                .overlay(Image(systemName: "dollarsign")
                    .font(.system(size: shortScreen ? 27 : 34, weight: .bold)).foregroundStyle(.white))
                .padding(.bottom, shortScreen ? 10 : 16)
            Text("Budgetty Premium").font(.title2).fontWeight(.bold).foregroundStyle(.white)
            Text("Unlock everything · Cancel anytime")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        // Top padding still has to clear the status bar, since the hero runs to y=0.
        .padding(.top, shortScreen ? 62 : 76).padding(.bottom, shortScreen ? 18 : 28)
        .background(Palette.heroGradient)
    }

    private func featureRow(_ f: PremiumBenefit) -> some View {
        HStack(spacing: 14) {
            // A roadmap row is muted and wears a clock, so it can't be mistaken for something the
            // subscription buys today.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(f.soon ? Palette.fill : Palette.tintSoft)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: f.soon ? "clock" : f.symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(f.soon ? Palette.secondaryLabel : Palette.tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.callout).fontWeight(.semibold)
                    .foregroundStyle(f.soon ? Palette.secondaryLabel : Palette.label)
                Text(f.detail).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer()
        }
        .opacity(f.soon ? 0.65 : 1)
    }

    private func planCard(_ p: Plan, title: LocalizedStringKey, detail: String?, price: String, sub: String?, badge: String?) -> some View {
        let selected = plan == p
        return Button {
            plan = p
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Palette.label)
                    // Nil while StoreKit hasn't loaded the product — the per-month figure is derived
                    // from its price, so there's nothing truthful to put here yet.
                    if let detail { Text(detail).font(.caption).foregroundStyle(Palette.secondaryLabel) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(price).font(.title2).fontWeight(.bold).foregroundStyle(Palette.label)
                    if let sub { Text(sub).font(.caption2).foregroundStyle(Palette.secondaryLabel) }
                }
            }
            .padding(16)
            .background(selected ? Palette.card : Palette.tertiaryBackground,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Palette.tint : Palette.separator, lineWidth: selected ? 2 : 0.5)
            )
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Palette.tint, in: Capsule())
                        .padding(.leading, 16).offset(y: -11)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(p == .yearly ? A11y.Paywall.planYearly : A11y.Paywall.planMonthly)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button { Task { await subscribe() } } label: {
                ZStack {
                    if busy { ProgressView().tint(.white) }
                    else { Text(premium ? "You're Premium ✓" : "Subscribe").font(.headline) }
                }
                .ctaPill()
            }
            // The pill paints its own gradient, so `.disabled` alone leaves it looking tappable —
            // which reads as broken next to a "—" price when StoreKit hasn't loaded the products.
            .opacity(selectedProduct == nil && !premium ? 0.45 : 1)
            .disabled(premium || busy || selectedProduct == nil)
            .accessibilityIdentifier(A11y.Paywall.subscribe)
            Button("Restore purchases") { Task { await store.restore() } }
                .font(.subheadline).foregroundStyle(Palette.tint)
                .accessibilityIdentifier(A11y.Paywall.restore)
            // Required here, not just in Settings: App Review 3.1.2 wants Terms of Use and a privacy
            // policy on the subscription screen itself. This screen is the app's entire monetisation,
            // so their absence is a plausible rejection rather than a nicety.
            HStack(spacing: 6) {
                Link("Terms of Service", destination: Legal.terms)
                Text("·")
                Link("Privacy Policy", destination: Legal.privacyPolicy)
            }
            .font(.caption2)
            .foregroundStyle(Palette.secondaryLabel)
            Text("No free trial · cancel anytime")
                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .background(.bar)
        // Pushed from Account the dock stays on screen; lift the CTA clear of it.
        .aboveFloatingDock()
    }

    /// Real StoreKit 2 purchase of the selected plan. Entitlement changes flow back through
    /// StoreManager, which flips the `premium` flag the rest of the app reads.
    private func subscribe() async {
        guard let product = selectedProduct else { return }
        busy = true
        defer { busy = false }
        if (try? await store.purchase(product)) == true { dismiss() }
    }
}
