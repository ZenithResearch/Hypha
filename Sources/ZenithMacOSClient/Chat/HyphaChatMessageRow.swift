import SwiftUI
import ZenithMacOSClientCore

/// App-local, semantic presentation of one Matrix timeline event.
struct HyphaChatMessageRow: View {
    let presentation: HyphaChatMessagePresentation

    init(presentation: HyphaChatMessagePresentation) {
        self.presentation = presentation
    }

    init(
        event: MatrixTimelineEvent,
        previousEvent: MatrixTimelineEvent? = nil,
        nextEvent: MatrixTimelineEvent? = nil
    ) {
        presentation = HyphaChatMessagePresentation(
            event: event,
            previousEvent: previousEvent,
            nextEvent: nextEvent
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: ZenithDesign.Space.x3) {
            if presentation.direction == .own {
                Spacer(minLength: ZenithDesign.Space.x10)
            }

            VStack(
                alignment: presentation.direction == .own ? .trailing : .leading,
                spacing: ZenithDesign.Space.x1
            ) {
                if presentation.showsSender {
                    Text(presentation.senderDisplayName)
                        .font(ZenithDesign.Typography.technical(size: 11, weight: .semibold))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .padding(.horizontal, ZenithDesign.Space.x2)
                }

                VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                    messageContent

                    if let authenticity = presentation.authenticity {
                        Label(authenticity.label, systemImage: authenticitySymbol(for: authenticity))
                            .font(ZenithDesign.Typography.technical(size: 11))
                            .foregroundStyle(authenticityColor(for: authenticity))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, ZenithDesign.Space.x3)
                .padding(.vertical, ZenithDesign.Space.x2)
                .background(bubbleColor)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ZenithDesign.Radius.card,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenithDesign.Radius.card,
                        style: .continuous
                    )
                    .stroke(bubbleBorderColor, lineWidth: 1)
                }

                Text(presentation.timestampLabel)
                    .font(ZenithDesign.Typography.technical(size: 10, weight: .regular))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .padding(.horizontal, ZenithDesign.Space.x2)
            }
            .frame(maxWidth: 520, alignment: presentation.direction == .own ? .trailing : .leading)

            if presentation.direction == .peer {
                Spacer(minLength: ZenithDesign.Space.x10)
            }
        }
        .padding(.top, presentation.isGroupedWithPrevious ? ZenithDesign.Space.x1 : ZenithDesign.Space.x3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("matrix.message.row")
    }

    @ViewBuilder
    private var messageContent: some View {
        switch presentation.displayContent {
        case let .text(body):
            Text(body)
                .font(ZenithDesign.Typography.corporate)
                .foregroundStyle(ZenithDesign.Palette.content)
                .textSelection(.enabled)

        case let .undecryptable(reason):
            guidanceContent(
                title: "Unable to decrypt this message",
                detail: reason,
                symbol: "lock.trianglebadge.exclamationmark",
                color: ZenithDesign.Palette.warning
            )

        case let .unsupported(type):
            guidanceContent(
                title: "Unsupported message type",
                detail: type,
                symbol: "doc.questionmark",
                color: ZenithDesign.Palette.muted
            )
        }
    }

    private func guidanceContent(
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: ZenithDesign.Space.x2) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                Text(title)
                    .font(ZenithDesign.Typography.corporate(size: 14, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.content)
                Text(detail)
                    .font(ZenithDesign.Typography.technical(size: 11, weight: .regular))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bubbleColor: Color {
        switch presentation.direction {
        case .own:
            ZenithDesign.Palette.brand.opacity(0.16)
        case .peer:
            ZenithDesign.Palette.baseSubtle
        }
    }

    private var bubbleBorderColor: Color {
        switch presentation.direction {
        case .own:
            ZenithDesign.Palette.brand.opacity(0.36)
        case .peer:
            ZenithDesign.Palette.borderStrong
        }
    }

    private func authenticityColor(
        for authenticity: HyphaChatMessagePresentation.Authenticity
    ) -> Color {
        switch authenticity.severity {
        case .warning:
            ZenithDesign.Palette.warning
        case .critical:
            ZenithDesign.Palette.error
        }
    }

    private func authenticitySymbol(
        for authenticity: HyphaChatMessagePresentation.Authenticity
    ) -> String {
        switch authenticity.severity {
        case .warning:
            "exclamationmark.shield"
        case .critical:
            "exclamationmark.shield.fill"
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            presentation.direction == .own
                ? "Your message"
                : "Message from \(presentation.senderDisplayName)",
            accessibleContent,
            presentation.timestampLabel,
        ]
        if let authenticity = presentation.authenticity {
            parts.append(authenticity.label)
        }
        return parts.joined(separator: ", ")
    }

    private var accessibleContent: String {
        switch presentation.displayContent {
        case let .text(body):
            body
        case let .undecryptable(reason):
            "Unable to decrypt this message. \(reason)"
        case let .unsupported(type):
            "Unsupported message type. \(type)"
        }
    }
}
