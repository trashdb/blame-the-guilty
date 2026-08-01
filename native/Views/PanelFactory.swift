import AppKit

enum PanelFactory {
    static func makePanel(size: CGSize, title: String) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.center()
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        return p
    }

    static func makeWindow(size: CGSize, title: String, position: Position = .center) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = title
        switch position {
        case .center:
            w.center()
        case .topRight:
            if let screen = NSScreen.main {
                let sf = screen.visibleFrame
                w.setFrameOrigin(NSPoint(x: sf.maxX - w.frame.width - 40, y: sf.maxY - w.frame.height - 40))
            } else {
                w.center()
            }
        }
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor.windowBackgroundColor
        w.isOpaque = true
        w.hasShadow = true
        w.hidesOnDeactivate = false
        return w
    }
}

extension PanelFactory {
    enum Position {
        case center, topRight
    }
}
