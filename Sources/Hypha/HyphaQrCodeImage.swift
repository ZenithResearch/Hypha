import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct HyphaQrCodeImage: View {
    let payload: Data
    var size: CGFloat = 240

    var body: some View {
        Group {
            if let image = Self.render(payload: payload) {
                #if os(macOS)
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                #elseif os(iOS)
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                #endif
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .padding(size * 0.2)
                    .foregroundStyle(ZenithDesign.Palette.error)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous))
        .accessibilityLabel("Secure device setup QR code")
    }

    #if os(macOS)
    private static func render(payload: Data) -> NSImage? {
        guard let cgImage = makeCGImage(payload: payload) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    #elseif os(iOS)
    private static func render(payload: Data) -> UIImage? {
        guard let cgImage = makeCGImage(payload: payload) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif

    private static func makeCGImage(payload: Data) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = payload
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }
}
