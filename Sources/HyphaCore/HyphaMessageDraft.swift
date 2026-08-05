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

public struct HyphaMessageDraftStore: Equatable, Sendable {
    public struct Context: Hashable, Sendable {
        public let accountID: String
        public let roomID: String

        public init(accountID: String, roomID: String) {
            self.accountID = accountID
            self.roomID = roomID
        }
    }

    public struct Submission: Equatable, Sendable {
        public let context: Context
        public let body: String

        public init(context: Context, body: String) {
            self.context = context
            self.body = body
        }
    }

    public private(set) var activeContext: Context?
    private var drafts: [Context: HyphaMessageDraft]

    public var activeDraft: HyphaMessageDraft {
        guard let activeContext else { return HyphaMessageDraft() }
        return drafts[activeContext] ?? HyphaMessageDraft()
    }

    public init() {
        activeContext = nil
        drafts = [:]
    }

    public mutating func activate(_ context: Context) {
        activeContext = context
        if drafts[context] == nil {
            drafts[context] = HyphaMessageDraft()
        }
    }

    public mutating func edit(_ text: String) {
        guard let activeContext else { return }
        drafts[activeContext, default: HyphaMessageDraft()].edit(text)
    }

    public mutating func beginSend() -> Submission? {
        guard let activeContext,
              let body = drafts[activeContext, default: HyphaMessageDraft()].beginSend() else {
            return nil
        }
        return Submission(context: activeContext, body: body)
    }

    public mutating func succeedSend(in context: Context) {
        guard var draft = drafts[context] else { return }
        draft.succeedSend()
        drafts[context] = draft
    }

    public mutating func failSend(in context: Context, reason: String) {
        guard var draft = drafts[context] else { return }
        draft.failSend(reason: reason)
        drafts[context] = draft
    }
}
