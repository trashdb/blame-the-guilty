import SwiftUI

struct LoggedInCardView: View {
    let username: String
    let avatarUrl: String?
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    default:
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("You are logged in as")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("@\(username)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.85))
            }

            Spacer()

            Button {
                onSignOut()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Sign out")
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.18, green: 0.35, blue: 0.18).opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.28, green: 0.45, blue: 0.28).opacity(0.5), lineWidth: 1)
        )
        //.padding(.vertical, 6)
    }
}
