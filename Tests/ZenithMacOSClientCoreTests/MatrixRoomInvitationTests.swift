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

    func testLocalUsernamesResolveAgainstTheActiveMatrixServerBeforeConfirmation() {
        XCTAssertEqual(
            MatrixRoomInvitationPolicy.resolveUserIDs(
                ["mgpi", "@remote:elsewhere.example", "mgpi"],
                defaultServerName: "zenith-research.ca"
            ),
            ["@mgpi:zenith-research.ca", "@remote:elsewhere.example"]
        )
    }

    func testInvalidUsernameFailsBeforeConfirmationOrNetworkMutation() {
        XCTAssertNil(
            MatrixRoomInvitationPolicy.resolveUserIDs(
                ["not a user"],
                defaultServerName: "zenith-research.ca"
            )
        )
        XCTAssertNil(
            MatrixRoomInvitationPolicy.resolveUserIDs(
                ["mgpi"],
                defaultServerName: nil
            )
        )
    }

    func testSidebarSeparatesDMsInvitesSpacesAndRooms() {
        let dm = MatrixRoomSummary(
            id: "!dm:example.org", name: "DM", isEncrypted: true, hasInvite: false, isDirect: true
        )
        let invitation = MatrixRoomSummary(
            id: "!invite:example.org", name: "Invite", isEncrypted: true, hasInvite: true, isDirect: true
        )
        let space = MatrixRoomSummary(
            id: "!space:example.org", name: "Space", isEncrypted: false, hasInvite: false, isSpace: true
        )
        let room = MatrixRoomSummary(
            id: "!room:example.org", name: "Room", isEncrypted: true, hasInvite: false
        )

        let groups = MatrixSidebarRoomGroups(rooms: [room, invitation, space, dm])

        XCTAssertEqual(groups.directMessages, [dm])
        XCTAssertEqual(groups.invitations, [invitation])
        XCTAssertEqual(groups.spaces, [space])
        XCTAssertEqual(groups.rooms, [room])
    }

    func testCoordinatorPerformsExactLookupOnlyForEligibleRoom() async {
        let expected = MatrixUserLookupResult.exists(
            userID: "@mgpi:example.org",
            displayName: "MGPI"
        )
        let service = InviteRecordingService(lookupResult: expected)
        let coordinator = MatrixChatCoordinator(service: service)
        let room = MatrixRoomSummary(
            id: "!eligible:example.org",
            name: "Eligible",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: true
        )

        let result = await coordinator.lookupInviteUser("@mgpi:example.org", for: room)

        XCTAssertEqual(result, expected)
        XCTAssertEqual(service.lookupRequests, ["@mgpi:example.org"])
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
    var lookupRequests: [String] = []
    let lookupResult: MatrixUserLookupResult

    init(lookupResult: MatrixUserLookupResult = .unavailable) {
        self.lookupResult = lookupResult
    }

    func restore() async throws -> [MatrixRoomSummary] { [] }
    func signIn(username: String, password: String) async throws -> [MatrixRoomSummary] { [] }
    func timeline(for roomID: String) async throws -> [MatrixTimelineEvent] { [] }
    func sendText(_ body: String, to roomID: String) async throws {}
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult {
        lookupRequests.append(userID)
        return lookupResult
    }
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws { requests.append(request) }
    func logout() async throws {}
}
