import XCTest
@testable import ZenithMacOSClientCore

@MainActor
final class MatrixRoomInvitationTests: XCTestCase {
    func testEligibleRoomsIncludesOnlyJoinedRoomsWithAuthoritativeInvitePermission() {
        let eligible = MatrixRoomSummary(
            id: "!eligible:example.org",
            name: "Eligible",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: true
        )
        let denied = MatrixRoomSummary(
            id: "!denied:example.org",
            name: "Denied",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: false
        )
        let pending = MatrixRoomSummary(
            id: "!pending:example.org",
            name: "Pending",
            isEncrypted: true,
            hasInvite: true,
            canInviteMembers: true
        )
        let space = MatrixRoomSummary(
            id: "!space:example.org",
            name: "Space",
            isEncrypted: false,
            hasInvite: false,
            isSpace: true,
            canInviteMembers: true
        )

        XCTAssertEqual(
            MatrixRoomInvitationPolicy.eligibleRooms(from: [denied, pending, space, eligible]),
            [eligible]
        )
    }

    func testInviteRequestNormalizesAndDeduplicatesMatrixIDs() {
        let request = MatrixRoomInviteRequest(
            roomID: " !room:example.org ",
            userIDs: [" @bob:example.org ", "@bob:example.org", "", "@carol:example.org"]
        )

        XCTAssertEqual(request.roomID, "!room:example.org")
        XCTAssertEqual(request.userIDs, ["@bob:example.org", "@carol:example.org"])
    }

    func testCoordinatorRejectsRoomWithoutInvitePermissionBeforeCallingService() async {
        let service = InviteRecordingService()
        let coordinator = MatrixChatCoordinator(service: service)
        let room = MatrixRoomSummary(
            id: "!denied:example.org",
            name: "Denied",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: false
        )

        let invited = await coordinator.inviteUsers(["@bob:example.org"], to: room)

        XCTAssertFalse(invited)
        XCTAssertEqual(service.requests, [])
    }

    func testCoordinatorForwardsInviteForEligibleRoom() async {
        let service = InviteRecordingService()
        let coordinator = MatrixChatCoordinator(service: service)
        let room = MatrixRoomSummary(
            id: "!eligible:example.org",
            name: "Eligible",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: true
        )

        let invited = await coordinator.inviteUsers(
            [" @bob:example.org ", "@bob:example.org", "@carol:example.org"],
            to: room
        )

        XCTAssertTrue(invited)
        XCTAssertEqual(
            service.requests,
            [MatrixRoomInviteRequest(
                roomID: room.id,
                userIDs: ["@bob:example.org", "@carol:example.org"]
            )]
        )
    }
}

private final class InviteRecordingService: MatrixChatService, @unchecked Sendable {
    var requests: [MatrixRoomInviteRequest] = []

    func restore() async throws -> [MatrixRoomSummary] { [] }
    func signIn(username: String, password: String) async throws -> [MatrixRoomSummary] { [] }
    func timeline(for roomID: String) async throws -> [MatrixTimelineEvent] { [] }
    func sendText(_ body: String, to roomID: String) async throws {}
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws { requests.append(request) }
    func logout() async throws {}
}
