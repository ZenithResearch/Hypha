import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum HyphaPlatform {
    static var minimumControlHeight: CGFloat {
        #if os(iOS)
        44
        #else
        36
        #endif
    }

    static var minimumIconButtonHitSize: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }

    static var localDevicePhrase: String {
        #if os(iOS)
        "this device"
        #else
        "this Mac"
        #endif
    }

    static func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

extension View {
    @ViewBuilder
    func hyphaPlatformRootFrame() -> some View {
        #if os(macOS)
        frame(minWidth: 760, minHeight: 520)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hyphaIdentityInputTraits() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func hyphaScrollableSheetContent() -> some View {
        #if os(iOS)
        ScrollView {
            self
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hyphaMobileSheetPresentation() -> some View {
        #if os(iOS)
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hyphaFixedSheetFrame(width: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width)
        #else
        frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
    }

    @ViewBuilder
    func hyphaFlexibleSheetFrame(
        minWidth: CGFloat,
        idealWidth: CGFloat,
        minHeight: CGFloat,
        idealHeight: CGFloat? = nil
    ) -> some View {
        #if os(macOS)
        frame(
            minWidth: minWidth,
            idealWidth: idealWidth,
            minHeight: minHeight,
            idealHeight: idealHeight
        )
        #else
        frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
    }

    @ViewBuilder
    func hyphaCredentialToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
        #endif
    }
}
