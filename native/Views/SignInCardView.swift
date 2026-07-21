import SwiftUI

struct SignInCardView: View {
    let isLoading: Bool
    let loginError: String?
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(DS.Color.textSecondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("You are not logged in")
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                Spacer()
            }

            if let error = loginError {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.destructive)
                        .lineLimit(2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                onSignIn()
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.65)
                            .transition(.opacity)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .transition(.opacity)
                    }
                    Text(isLoading ? "Connecting…" : "Sign in with GitHub")
                        .fontWeight(.semibold)
                        .animation(DS.Animation.default, value: isLoading)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md + 1)
                .background(DS.Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                .foregroundStyle(DS.Color.textPrimary)
                .font(DS.Font.body.medium())
            }
            .disabled(isLoading)
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .help("Sign in with GitHub")
        }
        .padding(.horizontal, DS.Spacing.xl + 1)
        .padding(.vertical, DS.Spacing.lg + 1)
        .background(DS.Color.destructive.opacity(0.45), in: RoundedRectangle(cornerRadius: DS.Radius.lg + 1))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg + 1)
                .stroke(DS.Color.destructive.opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, DS.Spacing.sm + 1)
        .animation(DS.Animation.default, value: loginError != nil)
        .animation(DS.Animation.default, value: isLoading)
    }
}
