import SwiftUI

/// Native mapping of the canonical ZenithUI semantic token layer.
/// Primitive values mirror `zenith-ui/public/tokens.css`; views consume these semantic roles.
enum ZenithDesign {
    enum Palette {
        static let base = Color(hex: 0x131A18)
        static let baseSubtle = Color(hex: 0x202B27)
        static let baseRaised = Color(hex: 0x193830)
        static let content = Color(hex: 0xD1FAF0)
        static let muted = Color(hex: 0x55A882)
        static let brand = Color(hex: 0x58EFC9)
        static let brandHover = Color(hex: 0x1DE7B4)
        static let warm = Color(hex: 0xFFC19D)
        static let error = Color(hex: 0xFDA4AF)
        static let warning = Color(hex: 0xFDE047)
        static let success = Color(hex: 0x86EFAC)
        static let glass = Color(hex: 0x202B27).opacity(0.72)
        static let glassBorder = Color(hex: 0x9BFBE3).opacity(0.14)
        static let border = Color(hex: 0x9BFBE3).opacity(0.12)
        static let borderStrong = Color(hex: 0x9BFBE3).opacity(0.24)
    }

    enum Space {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
        static let x10: CGFloat = 40
    }

    enum Radius {
        static let small: CGFloat = 4
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let sheet: CGFloat = 12
        static let full: CGFloat = 9_999
    }

    enum Typography {
        // Native font files are not currently distributed in a CoreText-compatible format.
        // These semantic fallbacks preserve ZenithUI's technical/corporate distinction.
        static let technical = Font.system(size: 14, weight: .medium, design: .monospaced)
        static let corporate = Font.system(size: 16, weight: .regular, design: .default)

        static func technical(size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static func corporate(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func technical(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
            .system(style, design: .monospaced, weight: weight)
        }

        static func corporate(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
            .system(style, design: .default, weight: weight)
        }
    }
}

struct ZenithGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = ZenithDesign.Radius.card

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(ZenithDesign.Palette.glass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ZenithDesign.Palette.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
    }
}

private struct ZenithAppSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(ZenithDesign.Typography.corporate)
            .foregroundStyle(ZenithDesign.Palette.content)
            .tint(ZenithDesign.Palette.brand)
            .background(ZenithDesign.Palette.base)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func zenithGlassSurface(cornerRadius: CGFloat = ZenithDesign.Radius.card) -> some View {
        modifier(ZenithGlassSurface(cornerRadius: cornerRadius))
    }

    func zenithAppSurface() -> some View {
        modifier(ZenithAppSurface())
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
