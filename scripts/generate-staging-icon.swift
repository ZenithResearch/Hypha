#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let canvasSize: CGFloat = 1_024
private let brandTop = NSColor(
    calibratedRed: 155.0 / 255.0,
    green: 251.0 / 255.0,
    blue: 227.0 / 255.0,
    alpha: 1
)
private let brandBottom = NSColor(
    calibratedRed: 2.0 / 255.0,
    green: 178.0 / 255.0,
    blue: 134.0 / 255.0,
    alpha: 1
)
private let nearBlack = NSColor(
    calibratedRed: 5.0 / 255.0,
    green: 8.0 / 255.0,
    blue: 7.0 / 255.0,
    alpha: 1
)

private let zenithPoints: [CGPoint] = [
    .init(x: 164.698, y: 0),
    .init(x: 98.4224, y: 0),
    .init(x: 0, y: 125.778),
    .init(x: 0, y: 192.501),
    .init(x: 98.4224, y: 192.501),
    .init(x: 0, y: 318.283),
    .init(x: 0, y: 385),
    .init(x: 279, y: 385),
    .init(x: 279, y: 335.363),
    .init(x: 52.4707, y: 335.363),
    .init(x: 164.698, y: 192.501),
    .init(x: 279, y: 192.501),
    .init(x: 279, y: 142.863),
    .init(x: 52.4707, y: 142.863),
]

private let iconSizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

private func markPath() -> CGPath {
    let path = CGMutablePath()
    guard let first = zenithPoints.first else { return path }
    path.move(to: .init(x: 260 + first.x * 1.8, y: 154 + first.y * 1.8))
    for point in zenithPoints.dropFirst() {
        path.addLine(to: .init(x: 260 + point.x * 1.8, y: 154 + point.y * 1.8))
    }
    path.closeSubpath()
    return path
}

private func render(pixels: Int) throws -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext
    let scale = CGFloat(pixels) / canvasSize
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: canvasSize)
    context.scaleBy(x: 1, y: -1)

    let outer = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
        cornerWidth: 224,
        cornerHeight: 224,
        transform: nil
    )
    context.saveGState()
    context.addPath(outer)
    context.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [brandTop.cgColor, brandBottom.cgColor] as CFArray,
        locations: [0, 1]
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvasSize / 2, y: 0),
        end: CGPoint(x: canvasSize / 2, y: canvasSize),
        options: []
    )
    context.restoreGState()

    let inset = CGPath(
        roundedRect: CGRect(x: 56, y: 56, width: 912, height: 912),
        cornerWidth: 196,
        cornerHeight: 196,
        transform: nil
    )
    context.addPath(inset)
    context.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    context.fillPath()
    context.addPath(inset)
    context.setStrokeColor(nearBlack.withAlphaComponent(0.30).cgColor)
    context.setLineWidth(2)
    context.strokePath()

    let mark = markPath()
    context.saveGState()
    context.setShadow(offset: .zero, blur: 24, color: nearBlack.withAlphaComponent(0.42).cgColor)
    context.addPath(mark)
    context.setFillColor(nearBlack.cgColor)
    context.fillPath()
    context.restoreGState()
    context.addPath(mark)
    context.setFillColor(nearBlack.cgColor)
    context.fillPath()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

private func makeICNS(images: [Int: Data]) throws -> Data {
    let representations: [(tag: String, pixels: Int)] = [
        ("ic04", 16),
        ("ic05", 32),
        ("ic11", 32),
        ("ic12", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic13", 256),
        ("ic09", 512),
        ("ic14", 512),
        ("ic10", 1_024),
    ]
    var body = Data()
    for representation in representations {
        guard let image = images[representation.pixels] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        body.append(contentsOf: representation.tag.utf8)
        appendUInt32(UInt32(image.count + 8), to: &body)
        body.append(image)
    }
    var result = Data("icns".utf8)
    appendUInt32(UInt32(body.count + 8), to: &result)
    result.append(body)
    return result
}

private func run() throws {
    guard CommandLine.arguments.count == 2 else {
        throw CocoaError(.fileWriteInvalidFileName)
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let iconset = output.deletingPathExtension().appendingPathExtension("iconset")
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: iconset.path) {
        try fileManager.removeItem(at: iconset)
    }
    if fileManager.fileExists(atPath: output.path) {
        try fileManager.removeItem(at: output)
    }
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

    var images: [Int: Data] = [:]
    for entry in iconSizes {
        let pixels = entry.points * entry.scale
        let suffix = entry.scale == 2 ? "@2x" : ""
        let name = "icon_\(entry.points)x\(entry.points)\(suffix).png"
        let image = try images[pixels] ?? render(pixels: pixels)
        images[pixels] = image
        try image.write(to: iconset.appendingPathComponent(name), options: .atomic)
    }
    try makeICNS(images: images).write(to: output, options: .atomic)
    print("Generated staging icon at \(output.path)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Staging icon generation failed: \(error)\n".utf8))
    exit(1)
}
