import SwiftUI

struct SignInCardView: View {
    let isLoading: Bool
    let loginError: String?
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("You are not logged in")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let error = loginError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Button {
                onSignIn()
            } label: {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(isLoading ? "Connecting…" : "Sign in with GitHub")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color(white: 0.85))
                .font(.system(size: 12, weight: .medium))
            }
            .disabled(isLoading)
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.72, green: 0.25, blue: 0.25).opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.82, green: 0.35, blue: 0.35).opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }
}
