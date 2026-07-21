import SwiftUI

struct LoggedInCardView: View {
    let username: String
    let avatarUrl: String?
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if let avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    default:
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(DS.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("You are logged in as")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("@\(username)")
                    .font(DS.Font.body.medium())
                    .foregroundStyle(DS.Color.textPrimary)
            }

            Spacer()

            Button {
                onSignOut()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(DS.Spacing.sm + 1)
                    .background(DS.Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm + 1))
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .cursor(.pointingHand)
            .help("Sign out")
        }
        .padding(.horizontal, DS.Spacing.xl + 1)
        .padding(.vertical, DS.Spacing.lg + 1)
        .background(DS.Color.success.opacity(0.75), in: RoundedRectangle(cornerRadius: DS.Radius.lg + 1))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg + 1)
                .stroke(DS.Color.success.opacity(0.5), lineWidth: 1)
        )
    }
}
