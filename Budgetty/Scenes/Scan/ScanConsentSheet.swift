//
//  ScanConsentSheet.swift
//  Budgetty
//
//  One-time disclosure shown before the first cloud receipt scan: it names that the photo is sent to
//  a third-party AI service to extract its contents, and asks for explicit consent (App Review
//  5.1.2(i)). Manual entry never triggers it — nothing leaves the device there.
//

import SwiftUI

struct ScanConsentSheet: View {
    /// Called when the user agrees. The caller persists consent and proceeds with the capture.
    var onAccept: () -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 38))
                .foregroundStyle(Palette.tint)
                .padding(.top, 30)

            Text("Receipt scanning & privacy")
                .font(.title3).fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("To read a receipt, Budgetty sends the photo to its secure cloud, where a third-party AI service extracts the store, items and totals. Photos aren't stored after processing. Manual entry stays on your device.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)

            Link("Privacy Policy", destination: Legal.privacyPolicy)
                .font(.subheadline)
                .foregroundStyle(Palette.tint)

            Spacer(minLength: 8)

            Button {
                onAccept()
                dismiss()
            } label: {
                Text("Continue").font(.headline).ctaPill(height: 50)
            }

            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .foregroundStyle(Palette.secondaryLabel)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 28)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
