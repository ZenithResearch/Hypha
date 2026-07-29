import AppKit
import SwiftUI

/// Atomic button variants shared by Hypha product views.
enum HyphaButtonVariant {
    case primary
    case secondary
    case quiet
    case destructive
}

/// Atomic interactive button style with explicit hover, press, focus, disabled, and cursor states.
struct HyphaButtonStyle: ButtonStyle {
    let variant: HyphaButtonVariant

    init(_ variant: HyphaButtonVariant = .primary) {
        self.variant = variant
    }

    func makeBody(configuration: Configuration) -> some View {
        HyphaInteractiveButtonBody(configuration: configuration, variant: variant)
    }
}

private struct HyphaInteractiveButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: HyphaButtonVariant

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var isCursorPushed = false

    var body: some View {
        configuration.label
            .font(ZenithDesign.Typography.corporate(.callout, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, ZenithDesign.Space.x4)
            .frame(minHeight: 36)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous)
                    .stroke(
                        isFocused ? ZenithDesign.Palette.brand : borderColor,
                        lineWidth: isFocused ? 2 : (isHovered && isEnabled ? 1.5 : 1)
                    )
            }
            .shadow(
                color: shadowColor,
                radius: accessibilityReduceMotion ? 0 : (isHovered ? 8 : 0),
                y: 3
            )
            .scaleEffect(
                accessibilityReduceMotion
                    ? 1
                    : (configuration.isPressed ? 0.975 : (isHovered && isEnabled ? 1.012 : 1))
            )
            .opacity(isEnabled ? 1 : 0.58)
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
            .focused($isFocused)
            .onHover { hovering in
                isHovered = hovering && isEnabled
                updateCursor(hovering: hovering)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    isHovered = false
                    releaseCursorIfNeeded()
                }
            }
            .onDisappear { releaseCursorIfNeeded() }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return ZenithDesign.Palette.muted }
        switch variant {
        case .primary:
            return ZenithDesign.Palette.base
        case .secondary, .quiet:
            return isHovered ? ZenithDesign.Palette.brand : ZenithDesign.Palette.content
        case .destructive:
            return ZenithDesign.Palette.base
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return ZenithDesign.Palette.baseRaised }
        switch variant {
        case .primary:
            return configuration.isPressed ? ZenithDesign.Palette.brandHover : ZenithDesign.Palette.brand
        case .secondary:
            return isHovered ? ZenithDesign.Palette.baseRaised : ZenithDesign.Palette.baseSubtle
        case .quiet:
            return isHovered ? ZenithDesign.Palette.baseRaised.opacity(0.85) : .clear
        case .destructive:
            return configuration.isPressed ? ZenithDesign.Palette.error.opacity(0.78) : ZenithDesign.Palette.error
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return ZenithDesign.Palette.border }
        switch variant {
        case .primary:
            return ZenithDesign.Palette.brand
        case .secondary, .quiet:
            return isHovered ? ZenithDesign.Palette.brand : ZenithDesign.Palette.borderStrong
        case .destructive:
            return ZenithDesign.Palette.error
        }
    }

    private var shadowColor: Color {
        guard isEnabled && isHovered else { return .clear }
        switch variant {
        case .destructive:
            return ZenithDesign.Palette.error.opacity(0.2)
        default:
            return ZenithDesign.Palette.brand.opacity(0.16)
        }
    }

    private func updateCursor(hovering: Bool) {
        if hovering && isEnabled {
            guard !isCursorPushed else { return }
            NSCursor.pointingHand.push()
            isCursorPushed = true
        } else {
            releaseCursorIfNeeded()
        }
    }

    private func releaseCursorIfNeeded() {
        guard isCursorPushed else { return }
        NSCursor.pop()
        isCursorPushed = false
    }
}

/// Atomic text/icon button used by auth molecules and organisms.
struct HyphaButton: View {
    let title: String
    var systemImage: String?
    var variant: HyphaButtonVariant = .primary
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(role: variant == .destructive ? .destructive : nil, action: action) {
            HStack(spacing: ZenithDesign.Space.x2) {
                if let systemImage {
                    Image(systemName: systemImage)
                    Text(title)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(HyphaButtonStyle(variant))
    }
}

typealias ZenithPrimaryButtonStyle = HyphaButtonStyle
