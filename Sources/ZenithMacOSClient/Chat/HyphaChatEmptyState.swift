import SwiftUI

/// Empty timeline content for a newly created encrypted room.
struct HyphaChatEmptyState: View {
    var body: some View {
        VStack(spacing: ZenithDesign.Space.x4) {
            Image(systemName: "lock.shield.fill")
                .font(ZenithDesign.Typography.technical(size: 30, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.brand)
                .accessibilityHidden(true)

            Text("Your encrypted room is ready")
                .font(ZenithDesign.Typography.technical(size: 20, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.content)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("matrix.chat.empty-state.title")

            Text("Start the conversation. Messages in this room are end-to-end encrypted.")
                .font(ZenithDesign.Typography.corporate(size: 14))
                .foregroundStyle(ZenithDesign.Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("matrix.chat.empty-state.message")
        }
        .padding(ZenithDesign.Space.x8)
        .frame(maxWidth: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matrix.chat.empty-state")
    }
}
