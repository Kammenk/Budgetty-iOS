//
//  OnboardingView.swift
//  Budgetty
//
//  First-run intro carousel (4 pages) from the mockup: illustration, title/body, page dots, and a
//  Continue → Get Started CTA. Completing (or Skip) sets the onboarded flag so the app shows RootView.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @State private var step = 0

    private struct Page { let symbol: String; let caption: String; let title: String; let body: String; let cta: String }
    private let pages = [
        Page(symbol: "camera.fill", caption: "Snap a photo of any receipt",
             title: "Snap any receipt",
             body: "Point your camera at any paper or digital receipt. We handle the rest.", cta: "Continue"),
        Page(symbol: "sparkles", caption: "Budgetty reads every item & category",
             title: "We read & categorise it",
             body: "Budgetty pulls every line item and assigns a category — you just review.", cta: "Continue"),
        Page(symbol: "chart.bar.fill", caption: "Track budgets & see where it goes",
             title: "Track your spending",
             body: "See where your money goes with budgets, charts and insights.", cta: "Continue"),
        Page(symbol: "dollarsign", caption: "Your personal finance tracker",
             title: "Ready to go",
             body: "Start scanning receipts and take control of your finances today.", cta: "Get Started"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.body).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.horizontal, 24).padding(.top, 8)

            TabView(selection: $step) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                    pageView(page).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            dots.padding(.bottom, 20)

            Button(action: advance) {
                Text(pages[step].cta)
                    .font(.headline)
                    .ctaPill(height: 54)
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
        // Keep the flow a centered readable column on iPad (no-op on iPhone, which is narrower)
        // so the CTA and pages don't stretch edge-to-edge.
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
    }

    private func pageView(_ page: Page) -> some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(colors: [Palette.tintSoft, Palette.card],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 220, height: 220)
                .overlay(
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Palette.tint)
                            .frame(width: 80, height: 80)
                            .overlay(Image(systemName: page.symbol).font(.system(size: 36)).foregroundStyle(.white))
                        Text(page.caption).font(.caption).foregroundStyle(Palette.secondaryLabel)
                            .multilineTextAlignment(.center).padding(.horizontal, 16)
                    }
                )
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Palette.separator, lineWidth: 0.5))
            Spacer()
            VStack(spacing: 12) {
                Text(page.title).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                Text(page.body).font(.body).foregroundStyle(Palette.secondaryLabel)
                    .multilineTextAlignment(.center).frame(maxWidth: 280)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 28)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Palette.tint : Palette.separator)
                    .frame(width: i == step ? 20 : 7, height: 7)
                    .animation(.easeInOut, value: step)
            }
        }
    }

    private func advance() {
        if step < pages.count - 1 { withAnimation { step += 1 } } else { finish() }
    }

    private func finish() { onboarded = true }
}
