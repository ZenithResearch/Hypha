#if os(macOS)
import AppKit
import HyphaCore
import QuickLookUI
import SwiftUI
import WebKit

struct HyphaArtifactViewerView: View {
    let selection: HyphaArtifactSelection

    var body: some View {
        Group {
            switch selection.viewer {
            case .quickLook:
                HyphaQuickLookView(url: selection.url)
            case .web:
                HyphaWebArtifactView(url: selection.url)
            case .image:
                HyphaImageArtifactView(url: selection.url)
            case .markdown:
                HyphaMarkdownArtifactView(url: selection.url)
            case .text:
                HyphaTextArtifactView(url: selection.url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZenithDesign.Palette.base)
        .accessibilityIdentifier("hypha.artifact.viewer")
    }
}

private struct HyphaQuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }
}

private struct HyphaWebArtifactView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> NavigationPolicy {
        NavigationPolicy(allowedDirectory: url.deletingLastPathComponent())
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        context.coordinator.allowedDirectory = url.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    final class NavigationPolicy: NSObject, WKNavigationDelegate {
        var allowedDirectory: URL

        init(allowedDirectory: URL) {
            self.allowedDirectory = allowedDirectory.standardizedFileURL.resolvingSymlinksInPath()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let candidate = navigationAction.request.url,
                  candidate.isFileURL else {
                decisionHandler(.cancel)
                return
            }
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            let root = allowedDirectory.path
            decisionHandler(
                resolved.path == root || resolved.path.hasPrefix(root + "/") ? .allow : .cancel
            )
        }
    }
}

private struct HyphaImageArtifactView: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 320, minHeight: 240)
                    .padding()
            }
        } else {
            ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
        }
    }
}

private struct HyphaMarkdownArtifactView: View {
    let url: URL
    @State private var blocks: [HyphaMarkdownBlock] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Markdown unavailable",
                    systemImage: "doc.richtext",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            markdownBlock(block)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(32)
                }
            }
        }
        .task(id: url) { load() }
        .accessibilityIdentifier("hypha.artifact.markdown")
    }

    private func load() {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= 2 * 1_024 * 1_024 else {
                errorMessage = "The Markdown output exceeds the 2 MB in-app preview limit."
                return
            }
            let source = String(decoding: data, as: UTF8.self)
            blocks = HyphaMarkdownParser.blocks(in: source)
            errorMessage = nil
        } catch {
            errorMessage = "Hypha could not read this Markdown output."
        }
    }

    @ViewBuilder
    private func markdownBlock(_ block: HyphaMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level == 1 ? 8 : 2)
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(4)
        case let .unorderedListItem(text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .fontWeight(.bold)
                Text(inlineMarkdown(text))
            }
            .padding(.leading, 8)
        case let .orderedListItem(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number).")
                    .fontWeight(.semibold)
                Text(inlineMarkdown(text))
            }
            .padding(.leading, 8)
        case let .quote(text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(ZenithDesign.Palette.border)
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .italic()
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }
        case let .codeBlock(language, code):
            VStack(alignment: .leading, spacing: 6) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .background(ZenithDesign.Palette.baseSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        case .horizontalRule:
            Divider()
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 30
        case 2: 25
        case 3: 21
        case 4: 18
        default: 16
        }
    }
}

private struct HyphaTextArtifactView: View {
    let url: URL
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Text unavailable",
                    systemImage: "doc.badge.ellipsis",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding()
                }
            }
        }
        .task(id: url) { load() }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= 2 * 1_024 * 1_024 else {
                errorMessage = "The text output exceeds the 2 MB in-app preview limit."
                return
            }
            text = String(decoding: data, as: UTF8.self)
            errorMessage = nil
        } catch {
            errorMessage = "Hypha could not read this output."
        }
    }
}
#endif
