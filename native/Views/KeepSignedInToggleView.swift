import SwiftUI

struct KeepSignedInToggleView: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text("Keep me signed in")
                .font(.system(size: 12))

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 6)
    }
}
