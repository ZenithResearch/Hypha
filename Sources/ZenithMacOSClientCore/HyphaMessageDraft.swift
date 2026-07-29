import Foundation

public struct HyphaMessageDraft: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var failureReason: String?

    private var submittedText: String?

    public var isSending: Bool {
        submittedText != nil
    }

    public init(text: String = "") {
        self.text = text
        failureReason = nil
        submittedText = nil
    }

    public mutating func edit(_ text: String) {
        self.text = text
        failureReason = nil
    }

    public mutating func beginSend() -> String? {
        guard submittedText == nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        submittedText = text
        failureReason = nil
        return text
    }

    public mutating func succeedSend() {
        guard let submittedText else { return }

        if text == submittedText {
            text = ""
        }
        self.submittedText = nil
        failureReason = nil
    }

    public mutating func failSend(reason: String) {
        guard submittedText != nil else { return }

        submittedText = nil
        failureReason = reason
    }
}
