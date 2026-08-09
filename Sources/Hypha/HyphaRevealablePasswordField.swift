import SwiftUI

struct HyphaRevealablePasswordField: View {
    let title: String
    @Binding var text: String
    let accessibilityIdentifier: String
    var isNewPassword = false
    var onSubmit: (() -> Void)? = nil

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: ZenithDesign.Space.x2) {
            Group {
                if isRevealed {
                    if isNewPassword {
                        TextField(title, text: $text)
                            .textContentType(.newPassword)
                    } else {
                        TextField(title, text: $text)
                            .textContentType(.password)
                    }
                } else {
                    if isNewPassword {
                        SecureField(title, text: $text)
                            .textContentType(.newPassword)
                    } else {
                        SecureField(title, text: $text)
                            .textContentType(.password)
                    }
                }
            }
            .textFieldStyle(HyphaTextFieldStyle())
            .accessibilityIdentifier(accessibilityIdentifier)
            .onSubmit { onSubmit?() }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(width: HyphaPlatform.minimumIconButtonHitSize, height: HyphaPlatform.minimumIconButtonHitSize)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ZenithDesign.Palette.muted)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            .accessibilityIdentifier("\(accessibilityIdentifier).visibility")
        }
        .privacySensitive()
    }
}
