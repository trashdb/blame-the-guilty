import Foundation
import XCTest
import SwiftUI
import AppKit

/// Lightweight snapshot testing without external dependencies.
/// Renders SwiftUI views to images and compares against reference files.
enum SnapshotTesting {
    static var referenceDirectory: URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SnapshotTests/
            .deletingLastPathComponent()  // BlameTheGuiltyTests/
            .appendingPathComponent("ReferenceImages")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    static func assertSnapshot<V: View>(
        of view: V,
        named name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else {
            XCTFail("Failed to render view to image", file: file, line: line)
            return
        }

        let referenceURL = referenceDirectory
            .appendingPathComponent("\(name).png")

        if let existingData = try? Data(contentsOf: referenceURL),
           let existingImage = NSImage(data: existingData),
           let existingTiff = existingImage.tiffRepresentation,
           let newTiff = nsImage.tiffRepresentation {
            // Compare by raw data
            if existingTiff == newTiff { return }  // identical
            // Images differ — save new and fail
            saveImage(nsImage, to: referenceURL.appendingPathExtension("new"))
            XCTFail(
                "Snapshot mismatch for '\(name)'. New image saved to \(referenceURL.path).new",
                file: file, line: line
            )
        } else {
            // First run — save reference
            saveImage(nsImage, to: referenceURL)
            XCTFail(
                "First snapshot for '\(name)' saved as reference. Re-run tests to verify.",
                file: file, line: line
            )
        }
    }

    private static func saveImage(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
