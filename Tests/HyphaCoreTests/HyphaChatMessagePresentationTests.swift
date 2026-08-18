import Foundation
import XCTest
@testable import HyphaCore

final class HyphaChatMessagePresentationTests: XCTestCase {
    func testOwnMessageUsesOwnDirectionAndNeverShowsSender() {
        let event = makeEvent(sender: "Me", isOwn: true)

        let presentation = HyphaChatMessagePresentation(event: event)

        XCTAssertEqual(presentation.direction, .own)
        XCTAssertEqual(presentation.senderDisplayName, "Me")
        XCTAssertFalse(presentation.showsSender)
        XCTAssertFalse(presentation.isGroupedWithPrevious)
        XCTAssertFalse(presentation.isGroupedWithNext)
    }

    func testPeerMessageStartsGroupAndShowsSenderWhenPreviousSenderDiffers() {
        let previous = makeEvent(id: "$previous", sender: "Bob")
        let event = makeEvent(sender: "Alice")
        let next = makeEvent(id: "$next", sender: "Alice")

        let presentation = HyphaChatMessagePresentation(
            event: event,
            previousEvent: previous,
            nextEvent: next
        )

        XCTAssertEqual(presentation.direction, .peer)
        XCTAssertTrue(presentation.showsSender)
        XCTAssertFalse(presentation.isGroupedWithPrevious)
        XCTAssertTrue(presentation.isGroupedWithNext)
    }

    func testPeerMessageContinuesGroupAndHidesRepeatedSender() {
        let previous = makeEvent(id: "$previous", sender: "Alice")
        let event = makeEvent(sender: "Alice")

        let presentation = HyphaChatMessagePresentation(event: event, previousEvent: previous)

        XCTAssertFalse(presentation.showsSender)
        XCTAssertTrue(presentation.isGroupedWithPrevious)
    }

    func testPeerMessagesFromRoutineUnverifiedDevicesRemainGroupedWithoutWarnings() {
        let previous = makeEvent(id: "$previous", sender: "Alice")

        for authenticity in [
            MatrixEventAuthenticity.unknownDevice,
            MatrixEventAuthenticity.unsignedDevice,
        ] {
            let event = makeEvent(sender: "Alice", authenticity: authenticity)
            let presentation = HyphaChatMessagePresentation(
                event: event,
                previousEvent: previous
            )

            XCTAssertFalse(presentation.showsSender)
            XCTAssertNil(presentation.authenticity)
        }
    }

    func testMessagesWithSameDisplayNameButDifferentDirectionDoNotGroup() {
        let previous = makeEvent(id: "$previous", sender: "Alex", isOwn: true)
        let event = makeEvent(sender: "Alex", isOwn: false)

        let presentation = HyphaChatMessagePresentation(event: event, previousEvent: previous)

        XCTAssertTrue(presentation.showsSender)
        XCTAssertFalse(presentation.isGroupedWithPrevious)
    }

    func testPeersWithSameDisplayNameButDifferentStableIDsDoNotGroup() {
        let previous = makeEvent(id: "$previous", sender: "Alex", senderID: "@alex-one:example.org")
        let event = makeEvent(sender: "Alex", senderID: "@alex-two:example.org")

        let presentation = HyphaChatMessagePresentation(event: event, previousEvent: previous)

        XCTAssertTrue(presentation.showsSender)
        XCTAssertFalse(presentation.isGroupedWithPrevious)
    }

    func testTimestampLabelUsesInjectedLocaleAndTimeZone() {
        let event = makeEvent(timestamp: 0)
        let losAngeles = TimeZone(secondsFromGMT: -8 * 60 * 60)!

        let presentation = HyphaChatMessagePresentation(
            event: event,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: losAngeles
        )

        XCTAssertEqual(presentation.timestampLabel, "4:00 PM")
    }

    func testDisplayContentPreservesTextAndFailureGuidance() {
        XCTAssertEqual(
            HyphaChatMessagePresentation(event: makeEvent(content: .text("Hello"))).displayContent,
            .text("Hello")
        )
        XCTAssertEqual(
            HyphaChatMessagePresentation(
                event: makeEvent(content: .undecryptable(reason: "Waiting for room keys"))
            ).displayContent,
            .undecryptable(reason: "Waiting for room keys")
        )
        XCTAssertEqual(
            HyphaChatMessagePresentation(
                event: makeEvent(content: .unsupported(type: "m.reaction"))
            ).displayContent,
            .unsupported(type: "m.reaction")
        )
    }

    func testOnlyEncryptionAndIntegrityFailuresProduceAuthenticityWarnings() {
        let expectations: [(MatrixEventAuthenticity, HyphaChatMessagePresentation.Authenticity?)] = [
            (.noWarning, nil),
            (.authenticityNotGuaranteed, nil),
            (.unknownDevice, nil),
            (.unsignedDevice, nil),
            (.unverifiedIdentity, nil),
            (.verificationViolation, .init(
                severity: .critical,
                label: "The sender's verified Matrix identity changed"
            )),
            (.mismatchedSender, .init(
                severity: .critical,
                label: "The encrypted session does not match the event sender"
            )),
            (.sentInClear, .init(
                severity: .critical,
                label: "Sent without encryption in an encrypted room"
            )),
        ]

        for (authenticity, expected) in expectations {
            let event = makeEvent(authenticity: authenticity)
            XCTAssertEqual(HyphaChatMessagePresentation(event: event).authenticity, expected)
        }
    }

    func testRoutineVerificationStatesDoNotProduceMessageWarnings() {
        for authenticity in [
            MatrixEventAuthenticity.unknownDevice,
            MatrixEventAuthenticity.unsignedDevice,
        ] {
            let presentation = HyphaChatMessagePresentation(
                event: makeEvent(authenticity: authenticity)
            )
            XCTAssertNil(presentation.authenticity)
        }

        let identityWarning = HyphaChatMessagePresentation(
            event: makeEvent(authenticity: .unverifiedIdentity)
        )
        XCTAssertNil(identityWarning.authenticity)
    }

    private func makeEvent(
        id: String = "$event",
        sender: String = "Alice",
        senderID: String? = nil,
        content: MatrixTimelineEvent.Content = .text("Hello"),
        isOwn: Bool = false,
        authenticity: MatrixEventAuthenticity = .noWarning,
        timestamp: UInt64 = 1_800_000
    ) -> MatrixTimelineEvent {
        MatrixTimelineEvent(
            id: id,
            senderDisplayName: sender,
            senderID: senderID,
            content: content,
            isOwn: isOwn,
            authenticity: authenticity,
            timestamp: timestamp
        )
    }
}
