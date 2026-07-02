import SwiftUI
import AppKit

// MARK: - Visual Effect (frosted glass background)

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Main Alert View

struct PunishmentAlertView: View {
    let title: String
    let body: String
    let subtitle: String?
    let onDismiss: () -> Void

    @State private var pulse = false

    private let crimsonGradient = LinearGradient(
        colors: [Color(red: 0.82, green: 0.10, blue: 0.10), Color(red: 0.52, green: 0.04, blue: 0.04)],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        ZStack {
            VisualEffectBackground()

            VStack(spacing: 0) {
                headerBar
                content
                footerButton
            }
        }
        .frame(width: 420, height: 370)
        .onAppear { pulse = true }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text("Blame the Guilty")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("CI/CD Punishment System")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.70))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(crimsonGradient)
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 16) {
            // Pulsing icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(pulse ? 0.06 : 0.15))
                    .frame(width: 90, height: 90)
                    .scaleEffect(pulse ? 1.14 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, Color(red: 0.6, green: 0.0, blue: 0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.top, 26)

            // Text block
            VStack(spacing: 5) {
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Text(body)
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.80))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 28)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Footer

    private var footerButton: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                    Text("I'll fix it immediately 🫡")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 11)
                .background(Capsule().fill(crimsonGradient))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 14)
        }
    }
}

