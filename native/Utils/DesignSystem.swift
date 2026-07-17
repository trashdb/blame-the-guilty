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

        // Surfaces
        static let cardBackground = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.55)
        static let cardHover = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.8)
        static let fieldBackground = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.35)
        static let divider = SwiftUI.Color(nsColor: .separatorColor).opacity(0.25)

        // Row backgrounds
        static let rowBackground = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.2)
        static let rowHover = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.35)

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
    func actionButton(_ label: String, color: SwiftUI.Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.caption.semibold())
                .foregroundStyle(color)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.sm + 1)
                .background(DS.Color.badgeBackground(color), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(DS.Color.badgeBorder(color), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .contentShape(Rectangle())
    }

    /// Solid filled button
    @ViewBuilder
    func solidButton(_ label: String, color: SwiftUI.Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.caption.semibold())
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Spacing.xl + 2)
                .padding(.vertical, DS.Spacing.sm + 1)
                .background(disabled ? color.opacity(0.4) : color, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .contentShape(Rectangle())
        .disabled(disabled)
    }

    /// Link button → opens URL
    @ViewBuilder
    func linkButton(_ label: String, url: URL) -> some View {
        actionButton(label, color: .blue) {
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
        .cursor(.pointingHand)
        .contentShape(Rectangle())
    }

    /// Styled text field used in Settings/forms
    @ViewBuilder
    func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(DS.Font.mono(12))
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.divider, lineWidth: 1)
            )
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

// MARK: - Hover Effect Modifier
struct HoverEffectModifier<S: ShapeStyle>: ViewModifier {
    let cornerRadius: CGFloat
    let shapeStyle: S
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? 1.02 : 1.0)
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

// MARK: - Section Header Font
extension DS.Font {
    static let section = SwiftUI.Font.system(size: 11, weight: .semibold)
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


