import SwiftUI

struct KeepSignedInToggleView: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text("Keep me signed in")
                .font(DS.Font.body)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .cursor(.pointingHand)
        }
        .padding(.horizontal, DS.Spacing.xl + 1)
        .padding(.vertical, DS.Spacing.md + 1)
        .background(DS.Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md + 1))
        .padding(.bottom, DS.Spacing.sm + 1)
    }
}
