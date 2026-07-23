import Testing
import SwiftUI
@testable import BlameTheGuilty

@MainActor
struct SnapshotTests {
    @Test func emptyState() {
        let view = VStack {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.gray)
            Text("No pull requests")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 200, height: 100)
        .background(.black)
        SnapshotTesting.assertSnapshot(of: view, named: "empty_state")
    }

    @Test func badgeCIReady() {
        let view = Text("CI READY")
            .badge("CI READY", color: .green)
            .padding()
            .background(.black)
        SnapshotTesting.assertSnapshot(of: view, named: "badge_ci_ready")
    }

    @Test func badgeCIFail() {
        let view = Text("CI FAIL")
            .badge("CI FAIL", color: .red)
            .padding()
            .background(.black)
        SnapshotTesting.assertSnapshot(of: view, named: "badge_ci_fail")
    }

    @Test func badgeApproved() {
        let view = Text("APPROVED")
            .badge("APPROVED", color: .green)
            .padding()
            .background(.black)
        SnapshotTesting.assertSnapshot(of: view, named: "badge_approved")
    }

    @Test func prRowTitle() {
        let view = VStack(alignment: .leading, spacing: 4) {
            Text("Fix authentication bug in login flow")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                Text("myorg/mainapp")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.gray)
                Text("→")
                    .foregroundStyle(.gray)
                Text("main")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 220, height: 50)
        .padding()
        .background(.black)
        SnapshotTesting.assertSnapshot(of: view, named: "pr_row_title")
    }

    @Test func segmentedPicker() {
        let view = Picker("", selection: .constant(0)) {
            Text("Details").tag(0)
            Text("Commits").tag(1)
            Text("Files").tag(2)
            Text("Checks").tag(3)
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
        .padding()
        .background(.black)
        SnapshotTesting.assertSnapshot(of: view, named: "segmented_picker")
    }
}
