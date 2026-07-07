import AppKit
import SwiftUI

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

struct NotificationBannerView: View {
    let title: String
    let message: String
    let subtitle: String?
    let hasURL: Bool
    let onDismiss: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if hasURL {
                    Text("Open workflow ↗")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { if hasURL { onOpen() } }
        .cursor(.pointingHand)
    }
}

final class NotificationBanner: NSObject {
    static let shared = NotificationBanner()
    private override init() {}

    private var panel: NSPanel?
    private var timer: Timer?

    func show(title: String, body: String, subtitle: String?, actionURL: URL?) {
        present(title: title, body: body, subtitle: subtitle, actionURL: actionURL)
    }

    private func present(title: String, body: String, subtitle: String?, actionURL: URL?) {
        dismiss()

        guard let screen = NSScreen.main else { return }

        let width: CGFloat  = 340
        let height: CGFloat = actionURL != nil ? 100 : 86
        let margin: CGFloat = 16

        let x = screen.visibleFrame.maxX - width - margin
        let y = screen.visibleFrame.maxY - height - margin

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelKey.screenSaverWindow.rawValue) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = false

        let bannerView = NotificationBannerView(
            title: title,
            message: body,
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

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
