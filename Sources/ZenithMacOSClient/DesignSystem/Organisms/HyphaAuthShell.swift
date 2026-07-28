import SwiftUI

/// Authentication organism that owns spacing, glass surface, navigation, and responsive scrolling.
struct HyphaAuthShell<Content: View>: View {
    let title: String
    let message: String
    let symbol: String
    let back: (() -> Void)?
    let isBackDisabled: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        message: String,
        symbol: String = "lock.shield.fill",
        back: (() -> Void)? = nil,
        isBackDisabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.back = back
        self.isBackDisabled = isBackDisabled
        self.content = content
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ZenithDesign.Palette.base,
                    ZenithDesign.Palette.baseRaised.opacity(0.62),
                    ZenithDesign.Palette.base,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: ZenithDesign.Space.x6) {
                    if let back {
                        HStack {
                            HyphaButton(
                                title: "Back",
                                systemImage: "chevron.left",
                                variant: .quiet,
                                action: back
                            )
                            .disabled(isBackDisabled)
                            .accessibilityIdentifier("matrix.auth.back")
                            Spacer()
                        }
                    }

                    HyphaAuthHeader(title: title, message: message, symbol: symbol)
                    content()
                }
                .padding(ZenithDesign.Space.x8)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
