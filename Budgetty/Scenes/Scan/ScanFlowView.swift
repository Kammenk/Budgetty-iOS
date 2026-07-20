//
//  ScanFlowView.swift
//  Budgetty
//
//  The receipt-scan vertical: capture (camera on device, photo library otherwise) → "reading" →
//  editable review → save. Extraction goes through `AppServices.receiptExtractor` (real backend in
//  release; stub on DEBUG so the Simulator can exercise the whole flow).
//

import SwiftUI
import SwiftData
import PhotosUI
import StoreKit

struct ScanFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    private enum Phase: Equatable { case capture, reading, review, failed(String) }
    @State private var phase: Phase = .capture
    @State private var draft = ReceiptDraft()
    @State private var isManual = false

    @State private var showCamera = false
    @State private var showDocScanner = false
    @State private var showLibrary = false
    @State private var pickedItem: PhotosPickerItem?

    @AppStorage(SettingsKey.premium) private var premium = false
    @AppStorage(SettingsKey.scanQuotaUsed) private var scansUsed = 0
    @State private var showPaywall = false

    /// Free scans remaining; AI capture is gated on it (manual entry never is).
    private var scansLeft: Int { max(0, ScanQuota.freeLimit - scansUsed) }
    private var quotaExhausted: Bool { !premium && scansLeft == 0 }

    var body: some View {
        content
            .onAppear(perform: maybeAutostart)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { handle($0) }.ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showDocScanner) {
                DocumentScannerPicker { handle($0) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickedItem, matching: .images)
            .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        handle(image)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .capture: captureView
        case .reading: ReadingView()
        case .review: ReviewView(draft: draft, onCancel: { dismiss() }, onSave: save)
        case .failed(let message): failedView(message)
        }
    }

    // MARK: - Capture

    private var captureView: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    circleButton("xmark") { dismiss() }
                    Spacer()
                    Text("Scan Receipt").font(.headline).foregroundStyle(.white)
                    Spacer()
                    circleButton("bolt.fill") {}
                }
                .padding(.horizontal, 20).padding(.top, 8)

                // Free-tier allowance, right under the title (mockup): quiet caption, photo+file only.
                if !premium && scansLeft > 0 {
                    Text("\(scansLeft) of \(ScanQuota.freeLimit) free scans left (photo or file). Manual entry is always free.")
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.top, 6)
                }

                viewfinder
                    .overlay { if quotaExhausted { exhaustedCard } }
                    .padding(.horizontal, 28).padding(.top, 16)

                Text("Position the receipt, then capture")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 14)

                Button("Enter manually") { startManual() }
                    .font(.subheadline).foregroundStyle(.white)
                    .padding(.top, 10)

                Spacer()

                // Capture controls ride ONE glass slab (mockup: gallery · shutter · flash in a single
                // rounded glass bar), not separate floating buttons.
                HStack {
                    // Gallery
                    Button { showLibrary = true } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20)).foregroundStyle(.white.opacity(0.9))
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(quotaExhausted).opacity(quotaExhausted ? 0.35 : 1)
                    Spacer()
                    // Shutter — the capture primary; solid white so it reads as the hero control.
                    // Guided document scanner first (edge-detect/deskew/de-glare + retake); plain
                    // camera where VisionKit is unsupported; photo picker on the Simulator.
                    Button {
                        if DocumentScannerPicker.isAvailable { showDocScanner = true }
                        else if CameraPicker.isAvailable { showCamera = true }
                        else { showLibrary = true }
                    } label: {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                            .overlay(Circle().fill(.white).frame(width: 56, height: 56))
                    }
                    .disabled(quotaExhausted).opacity(quotaExhausted ? 0.35 : 1)
                    Spacer()
                    // Flash
                    Button {} label: {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20)).foregroundStyle(.white.opacity(0.9))
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                // Dark-tinted glass so the slab reads like the mockup's smoked bar, not bright chrome.
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: .rect(cornerRadius: 44))
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private var viewfinder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.white.opacity(0.04))
            .frame(height: 360)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [6]))
                    .foregroundStyle(.white.opacity(0.3))
                    .overlay {
                        // The align hint yields to the quota takeover card riding this frame.
                        if !quotaExhausted {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 30)).foregroundStyle(.white.opacity(0.5))
                                Text("Align receipt in frame")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(30)
            )
            // Camera corner brackets (mockup): four L-shaped ticks framing the capture area.
            .overlay(
                CornerBrackets(length: 26)
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(14)
            )
    }

    /// Four L-shaped corner ticks framing the viewfinder (the mockup's camera brackets).
    private struct CornerBrackets: Shape {
        var length: CGFloat
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
            p.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
            p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
            return p
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Failure

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
                .foregroundStyle(Palette.warn)
            Text("Couldn't read the receipt").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button { phase = .capture } label: {
                Text("Try again").font(.headline)
                    .ctaPill(height: 50)
            }
            .frame(maxWidth: 220)
            Button("Cancel") { dismiss() }.foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
    }

    // MARK: - Actions

    private func handle(_ image: UIImage) {
        phase = .reading
        Task {
            do {
                let result = try await AppServices.receiptExtractor.extract(image)
                let d = ReceiptDraft(from: result)
                applyRules(to: d)
                draft = d
                phase = .review
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Apply learned name→category rules to the freshly extracted items.
    private func applyRules(to draft: ReceiptDraft) {
        guard let rules = try? context.fetch(FetchDescriptor<CategoryRule>()), !rules.isEmpty else { return }
        let map = Dictionary(rules.map { ($0.name, $0.category) }, uniquingKeysWith: { a, _ in a })
        for it in draft.items {
            if let cat = map[CategoryRule.key(it.name)] { it.category = cat }
        }
    }

    private func startManual() {
        let d = ReceiptDraft()
        d.date = .now
        d.addItem()
        draft = d
        isManual = true
        phase = .review
    }

    /// The quota-exhausted takeover riding the viewfinder (mockup): lock badge, message, Premium CTA.
    private var exhaustedCard: some View {
        VStack(spacing: 0) {
            Circle().fill(.white.opacity(0.18))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "lock")
                        .font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.bottom, 14)
            Text("You've used all \(ScanQuota.freeLimit) free scans")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .padding(.bottom, 6)
            Text("Go Premium to scan more — manual entry is always free.")
                .font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center).lineSpacing(2)
                .padding(.bottom, 18)
            Button { showPaywall = true } label: {
                Text("Go Premium").font(.headline)
                    .ctaPill(height: 50)
            }
        }
        .padding(22)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func save() {
        draft.persist(into: context, isManual: isManual)
        // Only a successful, finalized scan counts against the free quota — failed reads and
        // abandoned reviews never got here, and manual entry is always free. The rating gate rides
        // the exact same guard: a finalized scan is both what burns a free scan and what can earn a
        // review prompt; manual entry and edit re-saves are neither.
        let earnedReview = !isManual && ReviewGate.recordSuccessfulScan()
        if !isManual { scansUsed += 1 }
        dismiss()
        if earnedReview {
            ReviewGate.onPromptRequested()
            // Fire *after* the sheet has finished dismissing — asking mid-transition lets the system
            // alert fight the sheet animation. The action captures the active scene, so it still
            // presents once this view is gone.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                requestReview()
            }
        }
    }

    private func maybeAutostart() {
        #if DEBUG
        if phase == .capture, ProcessInfo.processInfo.environment["SCAN_PHASE"] == "review" {
            handle(UIImage())
        }
        #endif
    }
}

/// The "reading…" interstitial while extraction runs.
private struct ReadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Reading your receipt…").font(.headline)
            Text("Pulling out items, prices and categories").font(.subheadline)
                .foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
    }
}
