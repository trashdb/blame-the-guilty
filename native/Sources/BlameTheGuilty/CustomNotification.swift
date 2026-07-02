import AppKit
import SwiftUI

// MARK: - Frosted glass background

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Banner SwiftUI view

struct NotificationBannerView: View {
    let title: String
    let body: String
    let subtitle: String?
    let hasURL: Bool
    let onDismiss: () -> Void
    let onOpen: () -> Void

    @State private var hovered = false

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(alignment: .top, spacing: 10) {
                // Warning icon
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                    .padding(.top, 1)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(body)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if hasURL {
                        Text("Click to open workflow ↗")
                            .font(.system(size: 10))
                            .foregroundColor(.blue.opacity(0.8))
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 0)

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scaleEffect(hovered && hasURL ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { if hasURL { onOpen() } }
        .cursor(hasURL ? .pointingHand : .arrow)
    }
}

// MARK: - Cursor modifier helper

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Banner controller

final class NotificationBanner: NSObject {
    static let shared = NotificationBanner()
    private override init() {}

    private var panel: NSPanel?
    private var timer: Timer?

    func show(title: String, body: String, subtitle: String?, actionURL: URL?) {
        DispatchQueue.main.async { [weak self] in
            self?.present(title: title, body: body, subtitle: subtitle, actionURL: actionURL)
        }
    }

    private func present(title: String, body: String, subtitle: String?, actionURL: URL?) {
        dismiss()

        guard let screen = NSScreen.main else { return }

        let width: CGFloat  = 340
        let height: CGFloat = actionURL != nil ? 100 : 86
        let margin: CGFloat = 16

        // Top-right corner, just below the menu bar
        let x = screen.visibleFrame.maxX - width - margin
        let y = screen.visibleFrame.maxY - height - margin

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.isReleasedWhenClosed = false

        let bannerView = NotificationBannerView(
            title: title,
            body: body,
            subtitle: subtitle,
            hasURL: actionURL != nil,
            onDismiss: { [weak self] in self?.dismiss() },
            onOpen: { [weak self] in
                if let url = actionURL { NSWorkspace.shared.open(url) }
                self?.dismiss()
            }
        )

        let hosting = NSHostingView(rootView: bannerView)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        p.contentView = hosting

        p.orderFrontRegardless()
        self.panel = p

        // Auto-dismiss after 8 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
    }
}

