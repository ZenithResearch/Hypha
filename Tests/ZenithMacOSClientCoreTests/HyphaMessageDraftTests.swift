import XCTest
@testable import ZenithMacOSClientCore

final class HyphaMessageDraftTests: XCTestCase {
    func testBeginSendReturnsOriginalPayloadAndRetainsDraftWhileInFlight() {
        var draft = HyphaMessageDraft(text: "  hello Hypha  ")

        let payload = draft.beginSend()

        XCTAssertEqual(payload, "  hello Hypha  ")
        XCTAssertEqual(draft.text, "  hello Hypha  ")
        XCTAssertTrue(draft.isSending)
    }

    func testBeginSendRejectsEmptyAndWhitespaceOnlyDrafts() {
        var emptyDraft = HyphaMessageDraft()
        var whitespaceDraft = HyphaMessageDraft(text: " \n\t ")

        XCTAssertNil(emptyDraft.beginSend())
        XCTAssertNil(whitespaceDraft.beginSend())
        XCTAssertFalse(emptyDraft.isSending)
        XCTAssertFalse(whitespaceDraft.isSending)
    }

    func testBeginSendRejectsAnOverlappingSend() {
        var draft = HyphaMessageDraft(text: "first")
        XCTAssertEqual(draft.beginSend(), "first")

        draft.edit("second")

        XCTAssertNil(draft.beginSend())
        XCTAssertTrue(draft.isSending)
        XCTAssertEqual(draft.text, "second")
    }

    func testSuccessfulSendClearsSubmittedDraft() {
        var draft = HyphaMessageDraft(text: "send me")
        XCTAssertEqual(draft.beginSend(), "send me")

        draft.succeedSend()

        XCTAssertEqual(draft.text, "")
        XCTAssertFalse(draft.isSending)
        XCTAssertNil(draft.failureReason)
    }

    func testSuccessfulSendPreservesTextEditedWhileSendWasInFlight() {
        var draft = HyphaMessageDraft(text: "first")
        XCTAssertEqual(draft.beginSend(), "first")
        draft.edit("next message")

        draft.succeedSend()

        XCTAssertEqual(draft.text, "next message")
        XCTAssertFalse(draft.isSending)
    }

    func testFailedSendRetainsDraftAndExposesReason() {
        var draft = HyphaMessageDraft(text: "please retry")
        XCTAssertEqual(draft.beginSend(), "please retry")

        draft.failSend(reason: "Homeserver unavailable")

        XCTAssertEqual(draft.text, "please retry")
        XCTAssertFalse(draft.isSending)
        XCTAssertEqual(draft.failureReason, "Homeserver unavailable")
    }

    func testEditingAfterFailureClearsStaleReasonWithoutLosingNewText() {
        var draft = HyphaMessageDraft(text: "original")
        XCTAssertEqual(draft.beginSend(), "original")
        draft.failSend(reason: "Timed out")

        draft.edit("revised")

        XCTAssertEqual(draft.text, "revised")
        XCTAssertNil(draft.failureReason)
    }

    func testDraftIsEquatableAndSendable() {
        let draft = HyphaMessageDraft(text: "hello")

        XCTAssertEqual(draft, HyphaMessageDraft(text: "hello"))
        requireSendable(draft)
    }

    private func requireSendable<T: Sendable>(_: T) {}
}
