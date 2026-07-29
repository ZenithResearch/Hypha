import SwiftUI

/// Empty timeline content for a newly created encrypted room.
struct HyphaChatEmptyState: View {
    let isEncrypted: Bool

    init(isEncrypted: Bool = true) {
        self.isEncrypted = isEncrypted
    }

    var body: some View {
        VStack(spacing: ZenithDesign.Space.x4) {
            Image(systemName: isEncrypted ? "lock.shield.fill" : "lock.open.trianglebadge.exclamationmark")
                .font(ZenithDesign.Typography.technical(.title, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.brand)
                .accessibilityHidden(true)

            Text(title)
                .font(ZenithDesign.Typography.technical(.headline, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.content)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("matrix.chat.empty-state.title")

            Text(message)
                .font(ZenithDesign.Typography.corporate(.body))
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

    private var title: String {
        if isEncrypted {
            "Your encrypted room is ready"
        } else {
            "This room is not encrypted"
        }
    }

    private var message: String {
        if isEncrypted {
            "Start the conversation. Messages in this room are end-to-end encrypted."
        } else {
            "Messages cannot be sent here. Create or open an encrypted room to chat securely."
        }
    }
}
