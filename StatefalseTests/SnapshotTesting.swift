import Foundation
import Testing
import SwiftUI
import AppKit

/// Lightweight snapshot testing without external dependencies.
/// Renders SwiftUI views to images and compares against reference files.
enum SnapshotTesting {
    /// GitHub Actions macOS runners have no GUI session; ImageRenderer can
    /// crash the test runner there. Validate snapshots on dev machines only.
    static let isCI = ProcessInfo.processInfo.environment["CI"] != nil

    static var referenceDirectory: URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SnapshotTests/
            .deletingLastPathComponent()  // StatefalseTests/
            .appendingPathComponent("ReferenceImages")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    static func assertSnapshot<V: View>(of view: V, named name: String) {
        guard !isCI else { return }

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else {
            Issue.record("Failed to render view '\(name)' to image")
            return
        }
        guard let renderedPNG = pngData(from: nsImage) else {
            Issue.record("Failed to encode '\(name)' to PNG")
            return
        }

        let referenceURL = referenceDirectory
            .appendingPathComponent("\(name).png")

        guard let existingData = try? Data(contentsOf: referenceURL) else {
            try? renderedPNG.write(to: referenceURL)
            Issue.record("First snapshot for '\(name)' saved as reference. Re-run tests to verify.")
            return
        }

        if existingData == renderedPNG { return }  // identical

        try? renderedPNG.write(to: referenceURL.appendingPathExtension("new"))
        Issue.record("Snapshot mismatch for '\(name)'. New image saved to \(referenceURL.path).new")
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
