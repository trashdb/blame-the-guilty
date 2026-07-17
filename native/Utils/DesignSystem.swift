import SwiftUI

// MARK: - Font Scale
enum DS {
    enum Font {
        /// Section headers, card titles (e.g. "Active PRs")
        static let section = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// Card title text
        static let title = SwiftUI.Font.system(size: 12, weight: .semibold)
        /// Card subtitle, body text
        static let body = SwiftUI.Font.system(size: 11)
        /// Small labels, branch names, secondary info
        static let small = SwiftUI.Font.system(size: 10)
        /// Captions, timestamps, tertiary info
        static let caption = SwiftUI.Font.system(size: 9)
        /// Tiny badges, line numbers
        static let tiny = SwiftUI.Font.system(size: 8)

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

    // MARK: - Semantic Colors
    enum Color {
        // Text
        static let textPrimary = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        static let textTertiary = SwiftUI.Color.gray.opacity(0.6)

        // Surfaces
        static let cardBackground = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.5)
        static let cardHover = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.7)
        static let fieldBackground = SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.3)
        static let divider = SwiftUI.Color(nsColor: .separatorColor).opacity(0.3)

        // Badge semantic
        static let badgeGreen = SwiftUI.Color.green
        static let badgeRed = SwiftUI.Color.red
        static let badgeOrange = SwiftUI.Color.orange
        static let badgeBlue = SwiftUI.Color.blue
        static let badgePurple = SwiftUI.Color.purple
        static let badgeGray = SwiftUI.Color.gray

        // Accent
        static let accent = SwiftUI.Color.blue
        static let destructive = SwiftUI.Color.red
        static let success = SwiftUI.Color.green

        /// Background tint for a badge given its foreground color
        static func badgeBackground(_ color: SwiftUI.Color) -> SwiftUI.Color {
            color.opacity(0.15)
        }
        static func badgeBorder(_ color: SwiftUI.Color) -> SwiftUI.Color {
            color.opacity(0.3)
        }
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 10
        static let xxl: CGFloat = 16
        static let section: CGFloat = 12
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
    }

    // MARK: - Animation
    enum Animation {
        static let `default` = SwiftUI.Animation.spring(duration: 0.25)
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let popover = SwiftUI.Animation.spring(duration: 0.35)
        static let hover = SwiftUI.Animation.easeInOut(duration: 0.12)
    }
}

// MARK: - Reusable Components
extension View {
    /// Standard badge: colored label on tinted background
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

    /// Card-style container with background, overlay, and hover effect
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

    /// Secondary action button (ghost style)
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
    }

    /// Solid action button (filled style)
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
        .disabled(disabled)
    }

    /// Link-style button (opens URL)
    @ViewBuilder
    func linkButton(_ label: String, url: URL) -> some View {
        actionButton(label, color: .blue) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Icon toolbar button with consistent sizing
    @ViewBuilder
    func toolbarButton(icon: String, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.body)
                .foregroundStyle(.secondary)
                .padding(DS.Spacing.md)
                .background(DS.Color.fieldBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .ifLet(help) { $0.help($1) }
        .cursor(.pointingHand)
    }

    /// Standard text field in Settings / forms
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

    /// Section header text
    @ViewBuilder
    func sectionHeader(_ label: String, color: SwiftUI.Color = .blue) -> some View {
        Text(label)
            .font(DS.Font.section)
            .foregroundStyle(color)
    }
}

// MARK: - Helpers
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

// MARK: - PR Status Colors
extension DS.Color {
    static func statusColor(for pr: PullRequest, draft: Bool) -> SwiftUI.Color {
        if pr.isMerged { return .purple }
        if draft { return .gray }
        switch pr.ciStatus {
        case "waiting": return .orange
        case "failed":  return .red
        case "review":  return .blue
        default:        return .green
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

// MARK: - PR Mergeable / CI Status Colors
extension DS.Color {
    static func mergeableColor(_ state: String?) -> SwiftUI.Color {
        guard let state else { return .gray }
        switch state {
        case "clean":        return .green
        case "behind":       return .orange
        case "dirty":        return .red
        case "unstable":     return .yellow
        case "has_hooks":    return .blue
        case "unknown":      return .gray
        default:             return .gray
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
