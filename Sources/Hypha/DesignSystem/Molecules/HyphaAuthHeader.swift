import SwiftUI

/// Authentication molecule: product identity plus flow-specific title and guidance.
struct HyphaAuthHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    let message: String
    var symbol: String = "lock.shield.fill"

    var body: some View {
        VStack(spacing: horizontalSizeClass == .compact ? ZenithDesign.Space.x2 : ZenithDesign.Space.x3) {
            ZStack {
                Circle()
                    .fill(ZenithDesign.Palette.brand.opacity(0.1))
                    .frame(width: horizontalSizeClass == .compact ? 60 : 74, height: horizontalSizeClass == .compact ? 60 : 74)
                Image(systemName: symbol)
                    .font(.system(size: horizontalSizeClass == .compact ? 28 : 34, weight: .medium))
                    .foregroundStyle(ZenithDesign.Palette.brand)
            }

            Text("Hypha")
                .font(ZenithDesign.Typography.technical(size: 14, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.brand)
                .textCase(.uppercase)
                .tracking(1.4)
            Text("A sovereign client for Zenith")
                .font(ZenithDesign.Typography.corporate(size: 12, weight: .medium))
                .foregroundStyle(ZenithDesign.Palette.muted)

            Text(title)
                .font(ZenithDesign.Typography.technical(size: horizontalSizeClass == .compact ? 24 : 28, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(ZenithDesign.Typography.corporate(size: 15))
                .foregroundStyle(ZenithDesign.Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520)
    }
}
