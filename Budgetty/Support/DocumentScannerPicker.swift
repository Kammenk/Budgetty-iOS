//
//  DocumentScannerPicker.swift
//  Budgetty
//
//  Thin UIKit bridge to VisionKit's guided document scanner (auto edge-detect, deskew, glare
//  handling and a review/retake step) — the Android app's ML Kit Document Scanner equivalent.
//  Marginal raw-camera shots made the extractor drop or merge lines; the scanner's cleaned page
//  flows through the same upload path. The plain CameraPicker stays as the fallback where
//  VisionKit is unavailable (and the photo picker on the Simulator).
//

import SwiftUI
import VisionKit

struct DocumentScannerPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerPicker
        init(_ parent: DocumentScannerPicker) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // A receipt is one page; extra pages from an over-eager auto-capture are ignored.
            if scan.pageCount > 0 { parent.onImage(scan.imageOfPage(at: 0)) }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
