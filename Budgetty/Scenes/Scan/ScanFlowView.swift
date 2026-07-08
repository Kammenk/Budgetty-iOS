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

struct ScanFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case capture, reading, review, failed(String) }
    @State private var phase: Phase = .capture
    @State private var draft = ReceiptDraft()
    @State private var isManual = false

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        content
            .onAppear(perform: maybeAutostart)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { handle($0) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickedItem, matching: .images)
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

                viewfinder.padding(.horizontal, 28).padding(.top, 16)

                Text("Position the receipt, then capture")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 14)

                Button("Enter manually") { startManual() }
                    .font(.subheadline).foregroundStyle(.white)
                    .padding(.top, 10)

                Spacer()

                HStack {
                    // Gallery
                    Button { showLibrary = true } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 22)).foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                    // Shutter
                    Button {
                        if CameraPicker.isAvailable { showCamera = true } else { showLibrary = true }
                    } label: {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                            .overlay(Circle().fill(.white).frame(width: 56, height: 56))
                    }
                    Spacer()
                    Color.clear.frame(width: 50, height: 50) // balance
                }
                .padding(.horizontal, 40).padding(.bottom, 44)
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
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 30)).foregroundStyle(.white.opacity(0.5))
                            Text("Align receipt in frame")
                                .font(.footnote).foregroundStyle(.white.opacity(0.5))
                        }
                    )
                    .padding(30)
            )
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.2), in: Circle())
        }
    }

    // MARK: - Failure

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
                .foregroundStyle(Palette.warn)
            Text("Couldn't read the receipt").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Try again") { phase = .capture }
                .buttonStyle(.borderedProminent).tint(Palette.tint)
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

    private func save() {
        draft.persist(into: context, isManual: isManual)
        dismiss()
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
