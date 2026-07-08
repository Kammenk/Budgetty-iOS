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
    @State private var busy = false

    private enum Plan { case yearly, monthly }
    @State private var plan: Plan = .yearly

    private var selectedProduct: Product? {
        store.product(plan == .yearly ? StoreManager.yearlyID : StoreManager.monthlyID)
    }
    /// Real localized price when products loaded; static fallback otherwise (e.g. Simulator with no
    /// StoreKit configuration).
    private func price(_ id: String, fallback: String) -> String {
        store.product(id)?.displayPrice ?? fallback
    }

    private struct Feature: Identifiable {
        let id = UUID(); let symbol: String; let title: String; let subtitle: String
    }
    private let features = [
        Feature(symbol: "camera.fill", title: "Unlimited scans", subtitle: "Scan as many receipts as you want"),
        Feature(symbol: "paintpalette.fill", title: "Accent color themes", subtitle: "Personalise the look with 8 tints"),
        Feature(symbol: "icloud.fill", title: "Cloud backup & sync", subtitle: "Your data safe and on all devices"),
        Feature(symbol: "square.grid.2x2.fill", title: "Home screen widgets", subtitle: "Spending at a glance, on your home"),
        Feature(symbol: "tag.fill", title: "10 custom categories", subtitle: "vs. 3 on the free plan"),
    ]

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
                        VStack(spacing: 20) {
                            featuresColumn
                            plansColumn
                        }
                    }
                }
                .padding(20)
            }
            .adaptiveReadableWidth(wide ? 900 : Dimens.contentMaxWidth)
        }
        .trackWideLandscape($wide)
        .background(Palette.groupedBackground)
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var featuresColumn: some View {
        VStack(spacing: 14) { ForEach(features) { featureRow($0) } }
    }

    private var plansColumn: some View {
        VStack(spacing: 10) {
            planCard(.yearly, title: "Yearly", detail: "€2.50 / month",
                     price: price(StoreManager.yearlyID, fallback: "€29.99"),
                     sub: "billed annually", badge: "BEST VALUE · SAVE 37%")
            planCard(.monthly, title: "Monthly", detail: "Billed each month",
                     price: price(StoreManager.monthlyID, fallback: "€3.99"), sub: nil, badge: nil)
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.2))
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "dollarsign").font(.system(size: 34, weight: .bold)).foregroundStyle(.white))
                .padding(.bottom, 16)
            Text("Budgetty Premium").font(.title2).fontWeight(.bold).foregroundStyle(.white)
            Text("Unlock everything · Cancel anytime")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Palette.heroGradient)
    }

    private func featureRow(_ f: Feature) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.tintSoft)
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: f.symbol).font(.system(size: 17)).foregroundStyle(Palette.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.callout).fontWeight(.semibold).foregroundStyle(Palette.label)
                Text(f.subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer()
        }
    }

    private func planCard(_ p: Plan, title: String, detail: String, price: String, sub: String?, badge: String?) -> some View {
        let selected = plan == p
        return Button {
            plan = p
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Palette.label)
                    Text(detail).font(.caption).foregroundStyle(Palette.secondaryLabel)
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
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button { Task { await subscribe() } } label: {
                ZStack {
                    if busy { ProgressView().tint(.white) }
                    else { Text(premium ? "You're Premium ✓" : "Subscribe").font(.headline) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(premium || busy || selectedProduct == nil)
            Button("Restore purchases") { Task { await store.restore() } }
                .font(.subheadline).foregroundStyle(Palette.tint)
            Text("No free trial · cancel anytime")
                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .background(.bar)
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
