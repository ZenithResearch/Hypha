#if os(iOS)
import AVFoundation
import CoreImage
import SwiftUI
import UIKit

struct HyphaQrScannerView: UIViewControllerRepresentable {
    let onPayload: @MainActor (Data) -> Void
    let onFailure: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> HyphaQrScannerViewController {
        HyphaQrScannerViewController(onPayload: onPayload, onFailure: onFailure)
    }

    func updateUIViewController(_ uiViewController: HyphaQrScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: HyphaQrScannerViewController, coordinator: Void) {
        uiViewController.stop()
    }
}

final class HyphaQrScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ca.zenithresearch.hypha.qr-camera")
    private let onPayload: @MainActor (Data) -> Void
    private let onFailure: @MainActor (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var deliveredPayload = false

    init(
        onPayload: @escaping @MainActor (Data) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        self.onPayload = onPayload
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        authorizeAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func authorizeAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureCapture()
                } else {
                    self.fail("Camera access is required to scan the secure setup code.")
                }
            }
        case .denied, .restricted:
            fail("Camera access is disabled. Allow camera access in Settings to scan the secure setup code.")
        @unknown default:
            fail("The camera is unavailable.")
        }
    }

    private func configureCapture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    throw HyphaQrScannerError.cameraUnavailable
                }
                let input = try AVCaptureDeviceInput(device: camera)
                let output = AVCaptureMetadataOutput()
                session.beginConfiguration()
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    throw HyphaQrScannerError.configurationFailed
                }
                session.addInput(input)
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: sessionQueue)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()

                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    preview.frame = view.bounds
                    view.layer.insertSublayer(preview, at: 0)
                    previewLayer = preview
                }
                session.startRunning()
            } catch {
                fail("The QR scanner could not start.")
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !deliveredPayload,
              let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              code.type == .qr,
              let payload = HyphaQrPayloadDecoder.payload(from: code) else { return }
        deliveredPayload = true
        session.stopRunning()
        Task { @MainActor [onPayload] in onPayload(payload) }
    }

    private func fail(_ message: String) {
        Task { @MainActor [onFailure] in onFailure(message) }
    }
}

private enum HyphaQrScannerError: Error {
    case cameraUnavailable
    case configurationFailed
}

private enum HyphaQrPayloadDecoder {
    static func payload(from code: AVMetadataMachineReadableCodeObject) -> Data? {
        if let descriptor = code.descriptor as? CIQRCodeDescriptor,
           let bytes = decodeByteSegments(
               descriptor.errorCorrectedPayload,
               symbolVersion: descriptor.symbolVersion
           ),
           !bytes.isEmpty {
            return bytes
        }
        guard let value = code.stringValue else { return nil }
        return value.data(using: .isoLatin1) ?? value.data(using: .utf8)
    }

    private static func decodeByteSegments(_ data: Data, symbolVersion: Int) -> Data? {
        var reader = BitReader(data: data)
        var output = Data()
        while let mode = reader.read(4), mode != 0 {
            switch mode {
            case 0b0111: // ECI; the following byte segment remains the payload authority.
                guard let first = reader.read(8) else { return nil }
                if first & 0x80 == 0 { continue }
                if first & 0xC0 == 0x80 {
                    guard reader.read(8) != nil else { return nil }
                } else if first & 0xE0 == 0xC0 {
                    guard reader.read(16) != nil else { return nil }
                } else {
                    return nil
                }
            case 0b0100: // Byte mode used by Matrix QR payloads.
                let countBits = symbolVersion <= 9 ? 8 : 16
                guard let count = reader.read(countBits) else { return nil }
                for _ in 0..<count {
                    guard let byte = reader.read(8) else { return nil }
                    output.append(UInt8(byte))
                }
            default:
                return nil
            }
        }
        return output.isEmpty ? nil : output
    }

    private struct BitReader {
        let data: Data
        var bitOffset = 0

        mutating func read(_ count: Int) -> Int? {
            guard count >= 0, bitOffset + count <= data.count * 8 else { return nil }
            var value = 0
            for _ in 0..<count {
                let byte = data[data.index(data.startIndex, offsetBy: bitOffset / 8)]
                let bit = (byte >> UInt8(7 - (bitOffset % 8))) & 1
                value = (value << 1) | Int(bit)
                bitOffset += 1
            }
            return value
        }
    }
}
#endif
