#if os(macOS)
import CryptoKit
import Foundation
import HyphaCore
import SwiftUI
import WebKit

struct HyphaRoomCanvasView: NSViewRepresentable {
    let package: HyphaRoomTemplatePackage
    let room: MatrixRoomSummary
    let repositorySet: MatrixRoomRepositorySet
    let assets: [HyphaRoomAsset]
    let openAsset: (HyphaRoomAsset) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            package: package,
            room: room,
            repositorySet: repositorySet,
            assets: assets,
            openAsset: openAsset
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(context.coordinator.templateHandler, forURLScheme: "hypha-template")
        configuration.setURLSchemeHandler(context.coordinator.assetHandler, forURLScheme: "hypha-asset")
        configuration.userContentController.add(context.coordinator, name: "hyphaBridge")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(
            package: package,
            room: room,
            repositorySet: repositorySet,
            assets: assets,
            openAsset: openAsset
        )
        context.coordinator.loadIfNeeded(in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown(view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private static let maximumRequestBytes = 64 * 1_024
        private static let maximumRequestsPerMinute = 120
        private static let maximumLayoutStateBytes = 32 * 1_024

        let templateHandler: HyphaCanvasTemplateSchemeHandler
        let assetHandler: HyphaCanvasAssetSchemeHandler

        private var package: HyphaRoomTemplatePackage
        private var room: MatrixRoomSummary
        private var repositorySet: MatrixRoomRepositorySet
        private var assets: [HyphaRoomAsset]
        private var openAsset: (HyphaRoomAsset) -> Void
        private var loadedDigest: String?
        private var requestIDs: [String: Date] = [:]
        private var requestTimes: [Date] = []
        private weak var webView: WKWebView?

        init(
            package: HyphaRoomTemplatePackage,
            room: MatrixRoomSummary,
            repositorySet: MatrixRoomRepositorySet,
            assets: [HyphaRoomAsset],
            openAsset: @escaping (HyphaRoomAsset) -> Void
        ) {
            self.package = package
            self.room = room
            self.repositorySet = repositorySet
            self.assets = assets
            self.openAsset = openAsset
            self.templateHandler = HyphaCanvasTemplateSchemeHandler(package: package)
            self.assetHandler = HyphaCanvasAssetSchemeHandler()
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            loadIfNeeded(in: webView)
        }

        func update(
            package: HyphaRoomTemplatePackage,
            room: MatrixRoomSummary,
            repositorySet: MatrixRoomRepositorySet,
            assets: [HyphaRoomAsset],
            openAsset: @escaping (HyphaRoomAsset) -> Void
        ) {
            if self.package.digest != package.digest || self.room.id != room.id {
                loadedDigest = nil
                requestIDs = [:]
                requestTimes = []
                assetHandler.revokeAll()
            }
            self.package = package
            self.room = room
            self.repositorySet = repositorySet
            self.assets = assets
            self.openAsset = openAsset
            templateHandler.package = package
        }

        func loadIfNeeded(in webView: WKWebView) {
            guard loadedDigest != package.digest else { return }
            loadedDigest = package.digest
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let path = package.manifest.entry.split(separator: "/").map(String.init)
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
                .joined(separator: "/")
            guard let url = URL(string: "hypha-template://package/\(path)") else { return }
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }

        func tearDown(_ webView: WKWebView) {
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "hyphaBridge")
            assetHandler.revokeAll()
            requestIDs = [:]
            requestTimes = []
            self.webView = nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "hyphaBridge",
                  let object = message.body as? [String: Any],
                  JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  data.count <= Self.maximumRequestBytes,
                  let request = try? JSONDecoder().decode(HyphaCanvasBridgeRequest.self, from: data) else {
                reply(.failure(id: "invalid", code: .invalidRequest, message: "The canvas request is invalid."))
                return
            }
            reply(handle(request))
        }

        private func handle(_ request: HyphaCanvasBridgeRequest) -> HyphaCanvasBridgeResponse {
            guard request.version == 1 else {
                return .failure(id: request.id, code: .unsupportedVersion, message: "Canvas bridge version 1 is required.")
            }
            let now = Date()
            requestIDs = requestIDs.filter { now.timeIntervalSince($0.value) <= 600 }
            guard Self.validRequestID(request.id), requestIDs[request.id] == nil else {
                return .failure(id: request.id, code: .invalidRequest, message: "The request identifier is invalid or already used.")
            }
            requestIDs[request.id] = now
            requestTimes.removeAll { now.timeIntervalSince($0) > 60 }
            guard requestTimes.count < Self.maximumRequestsPerMinute else {
                return .failure(id: request.id, code: .rateLimited, message: "The canvas request limit was reached.")
            }
            requestTimes.append(now)
            let capabilities = Set(package.manifest.capabilities)
            guard capabilities.contains(request.method.capability) else {
                return .failure(
                    id: request.id,
                    code: .capabilityDenied,
                    message: "The template did not declare \(request.method.capability.rawValue)."
                )
            }

            switch request.method {
            case .roomGetMetadata:
                return .success(id: request.id, result: .object([
                    "name": .string(room.name),
                    "topic": room.topic.map(HyphaCanvasJSONValue.string) ?? .null,
                    "repository_count": .number(Double(repositorySet.repositories.count)),
                    "asset_count": .number(Double(assets.count)),
                ]))
            case .repositoriesList:
                return .success(id: request.id, result: .array(repositorySet.repositories.map { repository in
                    .object([
                        "id": .string(repository.id),
                        "name": .string(repository.name),
                        "requested_ref": .string(repository.requestedRef),
                        "resolved_commit": repository.resolvedCommit.map(HyphaCanvasJSONValue.string) ?? .null,
                        "primary": .bool(repository.id == repositorySet.primaryID),
                    ])
                }))
            case .assetsList:
                let repositoryID = request.stringParam("repository_id")
                let prefix = request.stringParam("prefix") ?? ""
                guard prefix.utf8.count <= 1_024, !prefix.contains("..") else {
                    return .failure(id: request.id, code: .invalidRequest, message: "The Asset prefix is invalid.")
                }
                let matches = assets.filter {
                    (repositoryID == nil || $0.attachmentID == repositoryID) && $0.path.hasPrefix(prefix)
                }.prefix(256)
                return .success(id: request.id, result: .array(matches.map(assetMetadata)))
            case .assetsGetMetadata:
                guard let asset = requestedAsset(request) else {
                    return .failure(id: request.id, code: .notFound, message: "The Asset is unavailable.")
                }
                return .success(id: request.id, result: assetMetadata(asset))
            case .assetsGetURL:
                guard let asset = requestedAsset(request) else {
                    return .failure(id: request.id, code: .notFound, message: "The Asset is unavailable.")
                }
                return .success(id: request.id, result: .object([
                    "url": .string(assetHandler.issue(asset: asset, roomID: room.id)),
                    "expires_in_seconds": .number(300),
                ]))
            case .viewerOpen:
                return .failure(
                    id: request.id,
                    code: .userGestureRequired,
                    message: "Use a hypha-viewer link so WebKit can prove a user activation."
                )
            case .layoutStateGet:
                return .success(id: request.id, result: loadLayoutState())
            case .layoutStateSet:
                guard let value = request.params["value"],
                      let data = try? JSONEncoder().encode(value),
                      data.count <= Self.maximumLayoutStateBytes else {
                    return .failure(id: request.id, code: .stateTooLarge, message: "Layout state must be at most 32 KiB.")
                }
                UserDefaults.standard.set(data, forKey: layoutStateKey)
                return .success(id: request.id, result: .object(["saved": .bool(true)]))
            }
        }

        private func requestedAsset(_ request: HyphaCanvasBridgeRequest) -> HyphaRoomAsset? {
            guard let id = request.stringParam("asset_id"), id.utf8.count <= 2_048 else { return nil }
            return assets.first { $0.id == id }
        }

        private func assetMetadata(_ asset: HyphaRoomAsset) -> HyphaCanvasJSONValue {
            .object([
                "id": .string(asset.id),
                "repository_id": .string(asset.attachmentID),
                "repository_name": .string(asset.repositoryName),
                "path": .string(asset.path),
                "title": .string(asset.title),
                "format": .string(asset.format),
                "viewer": .string(asset.viewer.rawValue),
                "source": .string(asset.source.kind.rawValue),
                "stale": .bool(asset.source.isStale),
            ])
        }

        private var layoutStateKey: String {
            let value = room.id + "\n" + package.digest
            let digest = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
            return "ca.zenithresearch.hypha.canvas-layout.v1.\(digest)"
        }

        private func loadLayoutState() -> HyphaCanvasJSONValue {
            guard let data = UserDefaults.standard.data(forKey: layoutStateKey),
                  data.count <= Self.maximumLayoutStateBytes,
                  let value = try? JSONDecoder().decode(HyphaCanvasJSONValue.self, from: data) else {
                return .object([:])
            }
            return value
        }

        private func reply(_ response: HyphaCanvasBridgeResponse) {
            guard let data = try? JSONEncoder().encode(response) else { return }
            let encoded = data.base64EncodedString()
            webView?.evaluateJavaScript("window.__hyphaBridgeReceive(JSON.parse(atob(`\(encoded)`)))")
        }

        private static func validRequestID(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 128
                && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "hypha-template", navigationAction.targetFrame?.isMainFrame == true {
                let expectedPath = "/" + package.manifest.entry
                let requestedPath = url.path.removingPercentEncoding ?? url.path
                decisionHandler(url.host == "package" && requestedPath == expectedPath ? .allow : .cancel)
                return
            }
            if url.scheme == "hypha-viewer",
               navigationAction.navigationType == .linkActivated,
               url.host == "open",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "asset_id" })?.value,
               let asset = assets.first(where: { $0.id == id }) {
                openAsset(asset)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? { nil }
    }
}

private extension HyphaCanvasBridgeRequest {
    func stringParam(_ key: String) -> String? {
        guard case let .string(value) = params[key] else { return nil }
        return value
    }
}

final class HyphaCanvasTemplateSchemeHandler: NSObject, WKURLSchemeHandler {
    var package: HyphaRoomTemplatePackage

    init(package: HyphaRoomTemplatePackage) {
        self.package = package
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "hypha-template", url.host == "package",
              let decodedPath = url.path.removingPercentEncoding else {
            fail(urlSchemeTask)
            return
        }
        let relative = String(decodedPath.drop(while: { $0 == "/" }))
        let file = package.root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(package.root.path + "/"),
              let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
              data.count <= HyphaRoomTemplateValidator.maximumFileBytes else {
            fail(urlSchemeTask)
            return
        }
        let headers = [
            "Content-Type": Self.contentType(file),
            "Content-Security-Policy": "default-src 'none'; script-src hypha-template: 'wasm-unsafe-eval'; style-src hypha-template: 'unsafe-inline'; img-src hypha-template: hypha-asset: data:; font-src hypha-template:; media-src hypha-asset:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            fail(urlSchemeTask)
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(URLError(.fileDoesNotExist))
    }

    private static func contentType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "json": "application/json"
        case "wasm": "application/wasm"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }
}

final class HyphaCanvasAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct Grant { let url: URL; let contentType: String; let expiresAt: Date }
    private var grants: [String: Grant] = [:]

    func issue(asset: HyphaRoomAsset, roomID: String) -> String {
        grants = grants.filter { $0.value.expiresAt > Date() }
        let token = UUID().uuidString.lowercased()
        grants[token] = Grant(
            url: asset.selection.url,
            contentType: Self.contentType(for: asset.format),
            expiresAt: Date().addingTimeInterval(300)
        )
        return "hypha-asset://room/\(token)"
    }

    func revokeAll() { grants = [:] }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "hypha-asset", url.host == "room",
              let token = url.path.split(separator: "/").last.map(String.init),
              let grant = grants[token], grant.expiresAt > Date(),
              let data = try? Data(contentsOf: grant.url, options: [.mappedIfSafe]),
              Int64(data.count) <= HyphaRoomAssetIndexer.maximumDigestBytes,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": grant.contentType,
                    "Cache-Control": "no-store",
                    "X-Content-Type-Options": "nosniff",
                ]
              ) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func contentType(for format: String) -> String {
        switch HyphaArtifactViewerRegistry.normalize(format) {
        case "pdf": "application/pdf"
        case "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppsx": "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
        case "ppt": "application/vnd.ms-powerpoint"
        case "html", "htm": "text/html; charset=utf-8"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "heic": "image/heic"
        case "json": "application/json"
        case "md", "markdown": "text/markdown; charset=utf-8"
        case "txt", "log": "text/plain; charset=utf-8"
        default: "application/octet-stream"
        }
    }
}
#endif
