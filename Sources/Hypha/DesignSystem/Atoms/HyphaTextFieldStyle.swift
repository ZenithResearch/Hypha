import SwiftUI

/// Atomic input treatment shared by authentication and security forms.
struct HyphaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(ZenithDesign.Typography.corporate(size: 15))
            .foregroundStyle(ZenithDesign.Palette.content)
            .padding(.horizontal, ZenithDesign.Space.x4)
            .frame(minHeight: 44)
            .background(ZenithDesign.Palette.baseSubtle)
            .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous)
                    .stroke(ZenithDesign.Palette.borderStrong, lineWidth: 1)
            }
    }
}

/// Atomic validation/status message with stable icon and semantic color.
struct HyphaStatusMessage: View {
    enum Tone {
        case warning
        case error
        case success
    }

    let message: String
    var tone: Tone = .error

    var body: some View {
        Label(message, systemImage: symbol)
            .font(ZenithDesign.Typography.corporate(size: 13, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ZenithDesign.Space.x3)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous))
    }

    private var color: Color {
        switch tone {
        case .warning: ZenithDesign.Palette.warning
        case .error: ZenithDesign.Palette.error
        case .success: ZenithDesign.Palette.success
        }
    }

    private var symbol: String {
        switch tone {
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }
}

typealias ZenithInputStyle = HyphaTextFieldStyle
