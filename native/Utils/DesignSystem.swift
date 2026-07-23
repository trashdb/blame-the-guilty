import AppKit
import SwiftUI

// MARK: - Design System
enum DS {
    // MARK: - Typography
    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 20, weight: .bold)
        static let title = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 12)
        static let small = SwiftUI.Font.system(size: 11)
        static let caption = SwiftUI.Font.system(size: 10)
        static let tiny = SwiftUI.Font.system(size: 9)
        static let micro = SwiftUI.Font.system(size: 8)

        static func mono(_ size: CGFloat) -> SwiftUI.Font {
            SwiftUI.Font.system(size: size, design: .monospaced)
        }
        static func bold(_ size: CGFloat) -> SwiftUI.Font {
            SwiftUI.Font.system(size: size, weight: .bold)
        }
        static func semibold(_ size: CGFloat) -> SwiftUI.Font {
            SwiftUI.Font.system(size: size, weight: .semibold)
        }
        static func medium(_ size: CGFloat) -> SwiftUI.Font {
            SwiftUI.Font.system(size: size, weight: .medium)
        }
    }

    // MARK: - Professional Color Palette
    enum Color {
        // Text
        static let textPrimary = SwiftUI.Color(nsColor: .labelColor)
        static let textSecondary = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let textTertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)

        // Surfaces — use primary.opacity for cross-mode compatibility
        static let cardBackground = SwiftUI.Color.primary.opacity(0.05)
        static let cardHover = SwiftUI.Color.primary.opacity(0.1)
        static let fieldBackground = SwiftUI.Color.primary.opacity(0.06)
        static let divider = SwiftUI.Color(nsColor: .separatorColor).opacity(0.3)

        // Row backgrounds
        static let rowBackground = SwiftUI.Color.primary.opacity(0.04)
        static let rowHover = SwiftUI.Color.primary.opacity(0.08)

        // Accent — a refined blue
        static let accent = SwiftUI.Color(red: 0.2, green: 0.45, blue: 0.95)
        static let accentDim = SwiftUI.Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.12)
        static let destructive = SwiftUI.Color(red: 0.85, green: 0.25, blue: 0.25)
        static let success = SwiftUI.Color(red: 0.2, green: 0.7, blue: 0.35)
        static let warning = SwiftUI.Color(red: 0.9, green: 0.55, blue: 0.1)

        // Status — refined
        static let statusGreen = SwiftUI.Color(red: 0.2, green: 0.7, blue: 0.35)
        static let statusRed = SwiftUI.Color(red: 0.85, green: 0.25, blue: 0.25)
        static let statusOrange = SwiftUI.Color(red: 0.9, green: 0.55, blue: 0.1)
        static let statusBlue = SwiftUI.Color(red: 0.2, green: 0.45, blue: 0.95)
        static let statusPurple = SwiftUI.Color(red: 0.6, green: 0.35, blue: 0.85)
        static let statusGray = SwiftUI.Color(red: 0.5, green: 0.5, blue: 0.5)
        static let statusYellow = SwiftUI.Color(red: 0.85, green: 0.75, blue: 0.15)

        // Badge helpers
        static func badgeBackground(_ color: SwiftUI.Color) -> SwiftUI.Color {
            color.opacity(0.12)
        }
        static func badgeBorder(_ color: SwiftUI.Color) -> SwiftUI.Color {
            color.opacity(0.25)
        }

        // Semantic aliases
        static let badgeGreen = statusGreen
        static let badgeRed = statusRed
        static let badgeOrange = statusOrange
        static let badgeBlue = statusBlue
        static let badgePurple = statusPurple
        static let badgeGray = statusGray
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 5
        static let md: CGFloat = 7
        static let lg: CGFloat = 9
        static let xl: CGFloat = 11
        static let xxl: CGFloat = 16
        static let section: CGFloat = 14
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 5
        static let md: CGFloat = 7
        static let lg: CGFloat = 9
        static let xl: CGFloat = 14
    }

    // MARK: - Animation
    enum Animation {
        static let `default` = SwiftUI.Animation.spring(duration: 0.28)
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let popover = SwiftUI.Animation.spring(duration: 0.38)
        static let hover = SwiftUI.Animation.easeInOut(duration: 0.12)
        static let appear = SwiftUI.Animation.spring(duration: 0.35)
    }
}

// MARK: - Reusable Components
extension View {
    /// Standard badge: compact colored label on tinted background
    @ViewBuilder
    func badge(_ label: String, color: SwiftUI.Color) -> some View {
        Text(label)
            .font(DS.Font.tiny.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(DS.Color.badgeBackground(color), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(DS.Color.badgeBorder(color), lineWidth: 1)
            )
    }

    /// Card container with background, border, shadow
    @ViewBuilder
    func card<Content: View>(
        color: SwiftUI.Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.badgeBackground(color), in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.badgeBorder(color), lineWidth: 1)
            )
    }

    /// Ghost action button (outlined)
    @ViewBuilder
    func actionButton(_ label: String, color: SwiftUI.Color, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.caption.semibold())
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.sm + 1)
                .background(DS.Color.badgeBackground(color), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(DS.Color.badgeBorder(color), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .contentShape(Rectangle())
        .cursor(.pointingHand)
        .ifLet(help) { $0.help($1) }
    }

    /// Solid filled button
    @ViewBuilder
    func solidButton(_ label: String, color: SwiftUI.Color, disabled: Bool = false, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.caption.semibold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.xl + 2)
                .padding(.vertical, DS.Spacing.sm + 1)
                .background(disabled ? color.opacity(0.4) : color, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .contentShape(Rectangle())
        .cursor(.pointingHand)
        .disabled(disabled)
        .ifLet(help) { $0.help($1) }
    }

    /// Link button → opens URL
    @ViewBuilder
    func linkButton(_ label: String, url: URL, help: String? = nil) -> some View {
        actionButton(label, color: .blue, help: help) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Toolbar icon button with consistent sizing
    @ViewBuilder
    func toolbarButton(icon: String, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(DS.Spacing.md)
                .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .ifLet(help) { $0.help($1) }
        .hoverEffect()
        .contentShape(Rectangle())
        .cursor(.pointingHand)
    }

    /// Styled text field used in Settings/forms
    @ViewBuilder
    func styledTextField(_ placeholder: String, text: Binding<String>, help: String? = nil, error: Binding<String?>? = nil) -> some View {
        let hasError = error?.wrappedValue != nil
        let borderColor: SwiftUI.Color = hasError ? DS.Color.destructive : DS.Color.divider
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.Font.mono(12))
                .foregroundStyle(hasError ? DS.Color.destructive : DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(borderColor, lineWidth: hasError ? 1.5 : 1)
                )
                .ifLet(help) { $0.help($1) }
            if let error, let msg = error.wrappedValue {
                Text(msg)
                    .font(DS.Font.tiny)
                    .foregroundStyle(DS.Color.destructive)
                    .padding(.leading, DS.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// URL text field with red border when the value isn't a valid URL
    @ViewBuilder
    func urlTextField(_ placeholder: String, text: Binding<String>, required: Bool = true, help: String? = nil, error: Binding<String?>? = nil) -> some View {
        let urlValid = !required || text.wrappedValue.isEmpty || URL(string: text.wrappedValue) != nil
        let hasError = error?.wrappedValue != nil || !urlValid
        let borderColor: SwiftUI.Color = hasError ? DS.Color.destructive : DS.Color.divider
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.Font.mono(12))
                .foregroundStyle(hasError ? DS.Color.destructive : DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(borderColor, lineWidth: hasError ? 1.5 : 1)
                )
                .ifLet(help) { $0.help($1) }
            if hasError, let error, let msg = error.wrappedValue {
                Text(msg)
                    .font(DS.Font.tiny)
                    .foregroundStyle(DS.Color.destructive)
                    .padding(.leading, DS.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Section header label
    @ViewBuilder
    func sectionHeader(_ label: String, color: SwiftUI.Color = .blue) -> some View {
        Text(label)
            .font(DS.Font.section)
            .foregroundStyle(color)
    }

    /// Add hover effect with scale + background
    @ViewBuilder
    func hoverEffect<S: ShapeStyle>(cornerRadius: CGFloat = DS.Radius.md, shapeStyle: S = DS.Color.rowHover) -> some View {
        self.modifier(HoverEffectModifier(cornerRadius: cornerRadius, shapeStyle: shapeStyle))
    }
}

// MARK: - Flow Layout (wrapping HStack)
struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0 else { return .zero }
        var y: CGFloat = 0
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                y += currentRowHeight + spacing
                currentX = 0
                currentRowHeight = 0
            }
            currentRowHeight = max(currentRowHeight, size.height)
            currentX += size.width + spacing
        }
        y += currentRowHeight
        return CGSize(width: width, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var y: CGFloat = bounds.minY
        var currentX: CGFloat = bounds.minX
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                y += currentRowHeight + spacing
                currentX = bounds.minX
                currentRowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: y), proposal: .unspecified)
            currentRowHeight = max(currentRowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

// MARK: - Popover Transition
extension View {
    @ViewBuilder
    func popoverTransition() -> some View {
        self.transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    /// Animate a binding-toggled popover with standard spring
    @ViewBuilder
    func animatedPopover<V: Identifiable>(item: Binding<V?>, @ViewBuilder content: @escaping (V) -> some View) -> some View {
        self.background {
            Color.clear
                .popover(item: item) { value in
                    content(value)
                        .popoverTransition()
                }
                .animation(DS.Animation.popover, value: item.wrappedValue != nil)
        }
    }

    @ViewBuilder
    func animatedPopover<P>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> P) -> some View where P: View {
        self.background {
            Color.clear
                .popover(isPresented: isPresented) {
                    content()
                        .popoverTransition()
                }
                .animation(DS.Animation.popover, value: isPresented.wrappedValue)
        }
    }
}

// MARK: - Hover Effect Modifier
struct HoverEffectModifier<S: ShapeStyle>: ViewModifier {
    let cornerRadius: CGFloat
    let shapeStyle: S
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovering ? AnyShapeStyle(shapeStyle) : AnyShapeStyle(.clear))
            )
            .onHover { hovering in
                withAnimation(DS.Animation.hover) {
                    isHovering = hovering
                }
            }
        }
    }

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }

    /// Use addCursorRect for native controls where onHover doesn't fire (e.g. Picker with .menu).
    func nativeCursor(_ cursor: NSCursor) -> some View {
        self.overlay(NativeCursorOverlay(cursor: cursor).allowsHitTesting(false))
    }
}

// MARK: - Native cursor overlay for controls where onHover is unreliable
private struct NativeCursorOverlay: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> NSView {
        NativeCursorView(cursor: cursor)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }
}

private class NativeCursorView: NSView {
    let cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let w = window, newSize != .zero {
            w.invalidateCursorRects(for: self)
        }
    }
}

// MARK: - Keyboard Shortcuts
extension View {
    /// Close the current panel/window when Esc is pressed
    func closeOnEscape(_ action: @escaping () -> Void) -> some View {
        self.onExitCommand(perform: action)
    }

    /// ⌘W to close the current panel/window
    func closeOnCmdW(_ action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut("w", modifiers: .command)
                .labelsHidden()
                .hidden()
        )
    }
}

// MARK: - Empty State
extension View {
    @ViewBuilder
    func emptyState(_ message: String, icon: String = "tray") -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(DS.Color.textTertiary)
            Text(message)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, DS.Spacing.xxl)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - IfLet Helper
extension View {
    @ViewBuilder
    func ifLet<V>(_ value: V?, transform: (Self, V) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Font Instance Helpers
extension SwiftUI.Font {
    func bold() -> SwiftUI.Font { weight(.bold) }
    func semibold() -> SwiftUI.Font { weight(.semibold) }
    func medium() -> SwiftUI.Font { weight(.medium) }
}

// MARK: - Badge Color Animation
extension View {
    @ViewBuilder
    func animatingBadge(color: SwiftUI.Color) -> some View {
        self
            .foregroundStyle(color)
            .animation(DS.Animation.fast, value: color)
    }
}

// MARK: - Section Header Font
extension DS.Font {
    static let section = SwiftUI.Font.system(size: 11, weight: .semibold)
}

// MARK: - Accessibility
extension View {
    /// Disables animations when Reduce Motion is enabled
    func reduceMotionDisabled() -> some View {
        self.modifier(ReduceMotionModifier())
    }
}

struct ReduceMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : DS.Animation.default, value: UUID())
    }
}

// MARK: - Accessible Button Helpers
extension View {
    /// Action button with VoiceOver label
    @ViewBuilder
    func accessibleAction(_ label: String, hint: String, color: SwiftUI.Color, action: @escaping () -> Void) -> some View {
        actionButton(label, color: color, action: action)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }

    /// Solid button with VoiceOver label
    @ViewBuilder
    func accessibleSolid(_ label: String, hint: String, color: SwiftUI.Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        solidButton(label, color: color, disabled: disabled, action: action)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Accessible Badge
extension View {
    @ViewBuilder
    func accessibleBadge(_ label: String, color: SwiftUI.Color, hint: String? = nil) -> some View {
        badge(label, color: color)
            .accessibilityLabel(label)
            .ifLet(hint) { $0.accessibilityHint($1) }
    }
}

// MARK: - PR Status Colors
extension DS.Color {
    static func statusColor(for pr: PullRequest, draft: Bool) -> SwiftUI.Color {
        if pr.isMerged { return statusPurple }
        if draft { return statusGray }
        switch pr.ciStatus {
        case "waiting": return statusOrange
        case "failed":  return statusRed
        case "review":  return statusBlue
        default:        return statusGreen
        }
    }

    static func statusLabel(for pr: PullRequest, draft: Bool) -> String {
        if pr.isMerged { return "MERGED" }
        if draft { return "DRAFT" }
        switch pr.ciStatus {
        case "waiting": return "WAITING"
        case "failed":  return "FAIL"
        case "review":  return "REVIEW"
        default:        return "READY"
        }
    }
}

// MARK: - PR Mergeable / CI Status
extension DS.Color {
    static func mergeableColor(_ state: String?) -> SwiftUI.Color {
        guard let state else { return statusGray }
        switch state {
        case "clean":        return statusGreen
        case "behind":       return statusOrange
        case "dirty":        return statusRed
        case "unstable":     return statusYellow
        case "has_hooks":    return statusBlue
        case "unknown":      return statusGray
        default:             return statusGray
        }
    }

    static func mergeableLabel(_ state: String?) -> String {
        guard let state else { return "UNKNOWN" }
        switch state {
        case "clean":        return "READY TO MERGE"
        case "behind":       return "BEHIND BASE"
        case "dirty":        return "HAS CONFLICTS"
        case "unstable":     return "CHECKS FAILING"
        case "has_hooks":    return "PENDING"
        case "unknown":      return "CHECKING…"
        default:             return state.uppercased()
        }
    }
}


