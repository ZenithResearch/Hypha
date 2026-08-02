import Foundation
import XCTest

final class MatrixShellSourceContractTests: XCTestCase {
    func testPasswordChangeFlowClearsSecretsAndLivesInSecurityCenter() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        for marker in [
            "MatrixChangePasswordSheet",
            ".sheet(isPresented: $showsPasswordChange)",
            "Change Password…",
            "matrix.password.current",
            "matrix.password.new",
            "matrix.password.confirmation",
            "matrix.password.submit",
            "clearSecrets()",
            "logoutOtherDevices",
            "No saved sign-in credential was changed.",
        ] {
            XCTAssertTrue(source.contains(marker), "Missing password-change contract: \(marker)")
        }
    }

    func testPasswordPersistenceIsExplicitAndUsesApplePasswordsAutofill() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let authSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/Auth/HyphaAuthenticationViews.swift"),
            encoding: .utf8
        )
        let entitlements = try String(
            contentsOf: root.appendingPathComponent("Resources/ZenithMacOSClient.apple-passwords.entitlements"),
            encoding: .utf8
        )
        let source = [appSource, authSource, entitlements].joined(separator: "\n")

        for marker in [
            "Save in Apple Passwords",
            "savePasswordToApplePasswords",
            ".textContentType(.username)",
            ".textContentType(.password)",
            ".textContentType(.newPassword)",
            "com.apple.developer.associated-domains",
            "webcredentials:synapse.zenith-research.ca",
        ] {
            XCTAssertTrue(source.contains(marker), "Missing opt-in Apple Passwords contract: \(marker)")
        }

        let signInStart = try XCTUnwrap(appSource.range(of: "    func signIn() async {"))
        let signInEnd = try XCTUnwrap(appSource.range(of: "    func signIn(with credential:", range: signInStart.upperBound..<appSource.endIndex))
        XCTAssertFalse(String(appSource[signInStart.lowerBound..<signInEnd.lowerBound]).contains("credentialStore.savePassword"))

        let registrationStart = try XCTUnwrap(appSource.range(of: "    func createAccount("))
        let registrationEnd = try XCTUnwrap(appSource.range(of: "    func dismissFirstRunGuidance", range: registrationStart.upperBound..<appSource.endIndex))
        XCTAssertFalse(String(appSource[registrationStart.lowerBound..<registrationEnd.lowerBound]).contains("credentialStore.savePassword"))
    }

    func testAdministratorControlsAreAuthorityGatedAndPresentedAsASheet() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let sheetSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/MatrixAdminSheet.swift"),
            encoding: .utf8
        )
        let clientSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixSynapseAdminClient.swift"),
            encoding: .utf8
        )
        let source = [appSource, sheetSource, clientSource].joined(separator: "\n")

        for marker in [
            ".sheet(isPresented: $showsAdministration)",
            "model.adminAccessState == .authorized",
            "MatrixAdminSheet",
            "matrix.admin.open",
            "matrix.admin.account.create",
            "matrix.admin.account.password",
            "privacySensitive()",
            "clearSecrets()",
            "Create user",
            "MatrixAdminAccountRole",
            "administrator: administrator",
            "user.userID == model.adminSnapshot?.currentUserID",
            "\"block\": true",
            "\"purge\": true",
            "Copies retained by federated servers",
        ] {
            XCTAssertTrue(source.contains(marker), "Missing administrator-control contract: \(marker)")
        }
        XCTAssertFalse(source.contains("registration_shared_secret"))
        XCTAssertFalse(source.contains("SYNAPSE_REGISTRATION_SHARED_SECRET"))
        XCTAssertFalse(source.contains("Create normal"))
    }

    func testSidebarUsesCompactCorporateRoomTypographyAndSmallTechnicalSecuritySymbols() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ZenithDesign.Typography.corporate(.callout, weight: .medium)"))
        XCTAssertTrue(source.contains("ZenithDesign.Typography.technical(.caption2, weight: .semibold)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Open \\(room.isSpace"))
        XCTAssertTrue(source.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(source.contains("Image(systemName: securityToolbarSymbol)"))
    }

    func testSecurityActionsLiveInToolbarAndOnlyCriticalTrustOccupiesChatSurface() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var securityToolbarMenu"))
        XCTAssertTrue(source.contains(".sheet(isPresented: $showsSecurityCenter)"))
        XCTAssertTrue(source.contains("Security Center…"))
        XCTAssertTrue(source.contains("if securityPresentation.requiresPersistentCriticalBanner"))
        XCTAssertTrue(source.contains("maxHeight: .infinity, alignment: .top"))
        XCTAssertFalse(source.contains("                    securityBanner\n"))
    }

    func testSidebarUsesExplicitVisibleRoomRowsInsteadOfImplicitListStyling() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ScrollView {"))
        XCTAssertTrue(source.contains("LazyVStack(alignment: .leading"))
        XCTAssertTrue(source.contains(".foregroundStyle(ZenithDesign.Palette.content)"))
        XCTAssertTrue(source.contains("matrix.rooms.sidebar"))
    }

    func testSecurityBannerConsumesTypedPolicyWithoutInventingPeerAvailability() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let bannerSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/HyphaSecurityBanner.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("@Published var peerVerificationEligibility"))
        XCTAssertTrue(appSource.contains("peerVerificationEligibility = coordinator.peerVerificationEligibility"))
        XCTAssertTrue(appSource.contains("HyphaSecurityPresentationPolicy.presentation("))
        XCTAssertTrue(appSource.contains("peerVerificationEligibility: model.peerVerificationEligibility"))
        XCTAssertTrue(appSource.contains("HyphaSecurityBanner("))
        XCTAssertTrue(bannerSource.contains("case .verifyWithAnotherHyphaDevice"))
        XCTAssertTrue(bannerSource.contains("matrix.security.banner"))
        XCTAssertTrue(bannerSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(bannerSource.contains("AccessibilityNotification.Announcement"))
        XCTAssertFalse(appSource.contains("private var trustPanel"))
        XCTAssertFalse(appSource.contains("private var verificationPanel"))
    }

    func testAuthenticationFlowsUseSeparateAtomicViewsWithInteractivePointerButtons() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift")
        let atomsURL = root.appendingPathComponent(
            "Sources/ZenithMacOSClient/DesignSystem/Atoms/HyphaButton.swift"
        )
        let headerURL = root.appendingPathComponent(
            "Sources/ZenithMacOSClient/DesignSystem/Molecules/HyphaAuthHeader.swift"
        )
        let accountCardURL = root.appendingPathComponent(
            "Sources/ZenithMacOSClient/DesignSystem/Molecules/HyphaAccountChoiceCard.swift"
        )
        let shellURL = root.appendingPathComponent(
            "Sources/ZenithMacOSClient/DesignSystem/Organisms/HyphaAuthShell.swift"
        )
        let viewsURL = root.appendingPathComponent(
            "Sources/ZenithMacOSClient/Auth/HyphaAuthenticationViews.swift"
        )

        for componentURL in [atomsURL, headerURL, accountCardURL, shellURL, viewsURL] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: componentURL.path),
                "Missing atomic authentication component: \(componentURL.path)"
            )
        }
        guard [atomsURL, headerURL, accountCardURL, shellURL, viewsURL].allSatisfy({
            FileManager.default.fileExists(atPath: $0.path)
        }) else { return }

        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let buttonSource = try String(contentsOf: atomsURL, encoding: .utf8)
        let authSource = try String(contentsOf: viewsURL, encoding: .utf8)
        let accountCardSource = try String(contentsOf: accountCardURL, encoding: .utf8)
        let shellSource = try String(contentsOf: shellURL, encoding: .utf8)

        for route in ["case landing", "case savedAccounts", "case passwordSignIn", "case registration"] {
            XCTAssertTrue(appSource.contains(route), "Missing authentication route: \(route)")
        }
        for view in [
            "struct HyphaAuthLandingView",
            "struct HyphaSavedAccountsView",
            "struct HyphaPasswordSignInView",
            "struct HyphaRegistrationView",
        ] {
            XCTAssertTrue(authSource.contains(view), "Missing separate authentication view: \(view)")
        }
        XCTAssertTrue(authSource.contains("HyphaAuthShell"))
        XCTAssertTrue(shellSource.contains("HyphaAuthHeader"))
        XCTAssertTrue(authSource.contains("HyphaAccountChoiceCard"))
        XCTAssertTrue(accountCardSource.contains("Continue existing session for \\(choice.displayAccount)"))
        XCTAssertTrue(accountCardSource.contains("Sign in with saved password for \\(choice.displayAccount)"))
        XCTAssertTrue(accountCardSource.contains("Delete local session for \\(choice.displayAccount)"))
        XCTAssertTrue(accountCardSource.contains("Delete saved password for \\(choice.displayAccount)"))
        XCTAssertTrue(accountCardSource.contains("fillsWidth: true"))
        XCTAssertTrue(accountCardSource.contains("choice.id"))
        XCTAssertTrue(accountCardSource.contains("ProgressView"))
        XCTAssertTrue(accountCardSource.contains("isInteractionDisabled"))
        XCTAssertTrue(authSource.contains("pendingAccountChoiceID"))
        XCTAssertTrue(authSource.contains("guard pendingAccountChoiceID == nil"))
        XCTAssertTrue(authSource.contains("isAuthenticationOperationInFlight"))
        XCTAssertTrue(authSource.contains("isBackDisabled: model.isAuthenticationOperationInFlight"))
        XCTAssertTrue(shellSource.contains("let isBackDisabled: Bool"))
        XCTAssertTrue(shellSource.contains(".disabled(isBackDisabled)"))
        XCTAssertTrue(appSource.contains("@Published private(set) var isAuthenticationOperationInFlight"))
        XCTAssertGreaterThanOrEqual(
            appSource.components(separatedBy: "guard beginAuthenticationOperation() else").count - 1,
            4
        )
        XCTAssertTrue(authSource.contains("Sign in with password"))
        XCTAssertTrue(authSource.contains("Create account with invite token"))
        XCTAssertTrue(authSource.contains("registrationAvailability == .inviteToken"))
        XCTAssertTrue(authSource.contains("clearSecrets()"))
        XCTAssertTrue(authSource.contains("model.password = \"\""))
        XCTAssertTrue(authSource.contains("model.savePasswordToApplePasswords = false"))
        XCTAssertTrue(authSource.contains(".onChange(of: model.registrationAvailability)"))
        XCTAssertFalse(appSource.contains("MatrixRegistrationSheet"))
        XCTAssertFalse(appSource.contains("showsRegistration"))

        XCTAssertTrue(buttonSource.contains("accessibilityReduceMotion"))
        XCTAssertTrue(buttonSource.contains("@FocusState"))
        XCTAssertTrue(buttonSource.contains(".focused("))
        XCTAssertTrue(buttonSource.contains("NSCursor.pointingHand.push()"))
        XCTAssertTrue(buttonSource.contains("NSCursor.pop()"))
        XCTAssertFalse(buttonSource.contains("NSCursor.arrow.set()"))
        XCTAssertTrue(buttonSource.contains("configuration.isPressed"))
        XCTAssertTrue(buttonSource.contains("isHovered"))
        XCTAssertTrue(buttonSource.contains("scaleEffect"))
        XCTAssertTrue(shellSource.contains("ZenithDesign.Palette"))
    }

    func testSavedPasswordRouteFinalizesOnlyAuthenticatedCredentialMigration() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "credentialStore.finalizeAuthenticatedMigration").count - 1,
            1
        )
        XCTAssertTrue(source.contains("if case .rooms = state"))
    }

    func testCreatorOwnedRoomsExposeExplicitLeaveAndForgetConfirmationWithoutGlobalDeletionClaim() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Delete \\(room.isSpace ? \"space\" : \"room\") from this account…"))
        XCTAssertTrue(source.contains("Leave and forget"))
        XCTAssertTrue(source.contains("Matrix does not erase copies held by other members or servers"))
        XCTAssertTrue(source.contains("room.isCreatedByCurrentUser"))
        XCTAssertTrue(source.contains("matrix.room.remove.confirm"))
    }

    func testMatrixSpacesUseSpaceMetadataAndAContainerSpecificSurface() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let service = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRustSDKChatService.swift"),
            encoding: .utf8
        )
        let spaceView = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/Spaces/HyphaSpaceView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(service.contains("isSpace: info?.isSpace == true"))
        XCTAssertTrue(shell.contains("let groups = MatrixSidebarRoomGroups(rooms: rooms)"))
        XCTAssertTrue(shell.contains("if groups.spaces.isEmpty"))
        XCTAssertTrue(shell.contains("HyphaSpaceView(space: room)"))
        XCTAssertTrue(shell.contains("matrix.space.create.inline"))
        XCTAssertTrue(shell.contains("matrix.room.create.inline"))
        XCTAssertFalse(shell.contains("Label(\"Add room or Space\""))
        XCTAssertTrue(shell.contains("MatrixRoomVisibility.public"))
        XCTAssertTrue(shell.contains(".accessibilityIdentifier(\"matrix.room.visibility\")"))
        XCTAssertTrue(spaceView.contains("Spaces organize rooms; they are not chat timelines."))
        XCTAssertFalse(spaceView.contains("ZenithMessageComposer"))
    }

    func testPasswordLoginRemainsAvailableWhenSavedCredentialsOrSessionRestoreFail() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try [
            root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/Auth/HyphaAuthenticationViews.swift"),
        ].map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let coreSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixChatService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("SecureField(\"Password\""))
        XCTAssertTrue(appSource.contains("title: \"Sign in with password\""))
        XCTAssertTrue(appSource.contains("retrySignIn(username: credential.username"))
        XCTAssertTrue(coreSource.contains("case savedCredentialUnavailable"))
        XCTAssertFalse(appSource.contains("state = .unavailable(reason: \"The saved Hypha password"))
    }

    func testUnavailablePeerGuidanceDoesNotInventWhyAuthorityIsUnavailable() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bannerSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/HyphaSecurityBanner.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(bannerSource.contains("could not determine whether another Hypha device can verify this one"))
        XCTAssertFalse(bannerSource.contains("No other Matrix device is available for verification"))
        XCTAssertFalse(bannerSource.contains("Hypha is your only Matrix client"))
    }

    func testProductIdentityKeepsMatrixAsOneHyphaCapability() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let appSource = try [
            root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/DesignSystem/Molecules/HyphaAuthHeader.swift"),
        ].map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let credentialSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/HyphaMatrixCredentialStore.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(readme.contains("Hypha is Zenith Research's native macOS client for Zenith"))
        XCTAssertTrue(readme.contains("Matrix chat is the first implemented capability, not the product boundary"))
        XCTAssertTrue(appSource.contains("Text(\"A sovereign client for Zenith\")"))
        XCTAssertTrue(credentialSource.contains("label: \"Hypha Zenith — \\(normalizedUsername)\""))

        for staleProductDefinition in [
            "Hypha Matrix —",
            "Hypha is Zenith Research's native macOS client for focused end-to-end encrypted Matrix chat.",
            "Hypha-to-Hypha encrypted chat as the primary product path",
            "focused desktop Matrix client",
            "Text(\"End-to-end encrypted Matrix chat\")",
        ] {
            XCTAssertFalse(
                readme.contains(staleProductDefinition)
                    || appSource.contains(staleProductDefinition)
                    || credentialSource.contains(staleProductDefinition),
                "Matrix must remain a Hypha capability, not its product identity: \(staleProductDefinition)"
            )
        }
    }

    func testSourceLineageRecordsPortAndExclusionBoundaries() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let lineage = root.appendingPathComponent("docs/source-lineage.md")
        let source = try String(contentsOf: lineage, encoding: .utf8)

        let requiredMarkers = [
            "MatrixForegroundLifecycleTests.swift",
            "MatrixSecureStorage.swift",
            "MatrixSyntheticDependencies.swift",
            "docs/spikes/e2ee-001/decision-packet.md",
            "MatrixURLSessionClient.swift",
            "Do not port"
        ]
        for marker in requiredMarkers {
            XCTAssertTrue(source.contains(marker), "Missing source-lineage boundary: \(marker)")
        }
    }

    func testBuildSigningModeIsExplicitAndCINeverSilentlyClaimsDevelopmentIdentity() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildScript = try String(contentsOf: root.appendingPathComponent("build-app.sh"), encoding: .utf8)
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)

        for marker in ["HYPHA_SIGNING_MODE", "development", "adhoc", "HYPHA_DEVELOPMENT_TEAM"] {
            XCTAssertTrue(buildScript.contains(marker), "Missing explicit signing contract: \(marker)")
        }
        XCTAssertTrue(workflow.contains("HYPHA_SIGNING_MODE=adhoc ./build-app.sh"))
        XCTAssertTrue(workflow.contains("codesign --verify --deep --strict --verbose=2 Hypha.app"))
        XCTAssertFalse(workflow.contains("codesign --verify --deep --strict --verbose=2 ZenithMacOSClient.app"))
    }

    func testContinuousIntegrationRunsPackageAndAppGates() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workflow = root.appendingPathComponent(".github/workflows/ci.yml")
        let source = try String(contentsOf: workflow, encoding: .utf8)

        for marker in [
            "swift test",
            "swift build",
            "./build-app.sh",
            "codesign --verify --deep --strict",
            "Verify patched SDK artifact",
            "lfs: true",
            "macos-26"
        ] {
            XCTAssertTrue(source.contains(marker), "Missing CI gate: \(marker)")
        }
    }

    func testHostCompatibleSDKUsesKeychainBackedStorePassphrase() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let provenance = try String(
            contentsOf: root.appendingPathComponent("Vendor/MatrixRustSDK/PROVENANCE.md"),
            encoding: .utf8
        )
        let service = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRustSDKChatService.swift"),
            encoding: .utf8
        )
        let coordinatorSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixChatService.swift"),
            encoding: .utf8
        )
        let generatedBinding = try String(
            contentsOf: root.appendingPathComponent("Vendor/MatrixRustSDK/Sources/MatrixRustSDK/matrix_sdk_ffi.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(package.contains("Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip"))
        XCTAssertTrue(package.contains("path: \"Vendor/MatrixRustSDK/Sources/MatrixRustSDK\""))
        XCTAssertTrue(provenance.contains("67d27c766ee61eca55707ddad232e57769344e5f"))
        XCTAssertTrue(provenance.contains("4bd5e819302ac5fd0cce86e2ec602a7540247dd5"))
        XCTAssertTrue(provenance.contains("3932fd4e8bcdb55738920de53e6dd6dad75c07a9"))
        XCTAssertTrue(provenance.contains("238e8745a9103cf0ee071771d7e93e007939cd20"))
        XCTAssertTrue(provenance.contains("f53e2ac81"))
        XCTAssertTrue(provenance.contains("c73782cbb"))
        XCTAssertTrue(provenance.contains("ca8796d0f065ade3787de2f18693afd940914ce2e35f807ccf479d2f14c5c565"))
        XCTAssertTrue(provenance.contains("f2f814679"))
        XCTAssertTrue(provenance.contains("97fa91b0c756604ef0b03ab9479fc704d1362c55"))
        XCTAssertTrue(provenance.contains("f4889ec898e77d8b8c9013adadd77f3d0901fc2d"))
        XCTAssertTrue(provenance.contains("533973cb7d918108fa111214575382bfbe30f765"))
        XCTAssertTrue(provenance.contains("2ee2199867bb28b723d80b1c6f80315301058c57"))
        XCTAssertTrue(provenance.contains("94f7106f93016e212fe69e9cc6f6d098f6dc71b6"))
        XCTAssertTrue(provenance.contains("minos 26.4"))
        XCTAssertTrue(generatedBinding.contains("public enum AuthoritativeDeviceVerificationState"))
        XCTAssertTrue(generatedBinding.contains("func authoritativeDeviceVerificationState() async throws"))
        XCTAssertTrue(generatedBinding.contains("func changePassword(newPassword:"))
        XCTAssertTrue(generatedBinding.contains("public protocol CrossSigningBootstrapHandleProtocol"))
        XCTAssertTrue(generatedBinding.contains("func bootstrapCrossSigningIfNeeded() async throws"))
        XCTAssertTrue(generatedBinding.contains("public struct CustomInitialStateEvent"))
        XCTAssertTrue(generatedBinding.contains("func getStateEventRaw(eventType:"))
        XCTAssertTrue(service.contains("\"passphrase-v1\""))
        XCTAssertTrue(service.contains(".passphrase(passphrase: storeKey.base64EncodedString())"))
        XCTAssertTrue(service.contains("saveStoreKey(generated, accountKey: accountKey)"))
        XCTAssertTrue(service.contains("encryption.authoritativeDeviceVerificationState()"))
        XCTAssertTrue(service.contains("encryption.diagnoseAndSignOwnDevice()"))
        let productionAuthoritySource = service + coordinatorSource
        for forbidden in [
            "refreshVerificationState()",
            "verificationState()",
            "signOwnDevice()",
            "MatrixDeviceVerificationState",
            "isCrossSignedByOwner",
            "is_cross_signed_by_owner",
        ] {
            XCTAssertFalse(productionAuthoritySource.contains(forbidden), "Stale trust authority remains: \(forbidden)")
        }
    }

    func testRepositoryContainsNoLegacyProductIdentifiers() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let legacyTokens = [
            ["Zenith", "Mobile", "MacOS"].joined(),
            ["zenith", "mobile", "macos"].joined(separator: "-"),
            ["ca", "zenithresearch", "mobile", "macos"].joined(separator: "."),
            ["ca", "zenith-research", "mobile-macos", "matrix"].joined(separator: "."),
        ]
        let allowedExtensions = Set(["swift", "md", "sh", "plist", "yml", "yaml", "json"])
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        )
        var violations: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if relativePath.hasPrefix(".build/")
                || relativePath.hasPrefix(".git/")
                || relativePath.hasPrefix(".swiftpm/")
                || relativePath.contains(".app/") { continue }
            guard allowedExtensions.contains(url.pathExtension),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for token in legacyTokens where source.contains(token) {
                violations.append("\(relativePath): \(token)")
            }
        }

        XCTAssertEqual(violations, [], "Legacy product identifiers remain:\n\(violations.joined(separator: "\n"))")
    }

    func testBundleAndPackageDeclareSDKCompatibleMinimum() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let info = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        let buildScript = try String(contentsOf: root.appendingPathComponent("build-app.sh"), encoding: .utf8)

        XCTAssertTrue(package.contains(".macOS(\"26.4\")"))
        XCTAssertTrue(package.contains("name: \"ZenithMacOSClient\""))
        XCTAssertTrue(package.contains("name: \"ZenithMacOSClientCore\""))
        XCTAssertTrue(info.contains("<key>CFBundleIdentifier</key><string>ca.zenithresearch.macos.client</string>"))
        XCTAssertTrue(info.contains("<key>CFBundleExecutable</key><string>ZenithMacOSClient</string>"))
        XCTAssertTrue(info.contains("<string>26.4</string>"))
        XCTAssertTrue(buildScript.contains("Hypha.app"))
        XCTAssertTrue(info.contains("<key>CFBundleName</key><string>Hypha</string>"))
        XCTAssertTrue(buildScript.contains("Resources/ZenithMacOSClient.entitlements"))
        XCTAssertTrue(buildScript.contains("MACOSX_DEPLOYMENT_TARGET=26.4"))
        XCTAssertFalse(info.contains("<string>13.0</string>"))
    }

    func testNativeShellContainsRequiredSafeStatesAndAccessibilityIdentifiers() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try [
            root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/HyphaSecurityBanner.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/Auth/HyphaAuthenticationViews.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/Chat/HyphaChatMessageRow.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/DesignSystem/Molecules/HyphaAccountChoiceCard.swift"),
        ].map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        let requiredMarkers = [
            "matrix.login.username",
            "matrix.login.password",
            "matrix.login.submit",
            "matrix.login.retry",
            "matrix.registration.open",
            "matrix.registration.username",
            "matrix.registration.password",
            "matrix.registration.confirmation",
            "matrix.registration.token",
            "matrix.registration.submit",
            "registrationAvailability == .inviteToken",
            "matrix.verification.request",
            "matrix.first-device.bootstrap",
            "matrix.first-device.password",
            "matrix.first-device.continue",
            "matrix.verification.challenge",
            "matrix.verification.approve",
            "matrix.verification.decline",
            "matrix.recovery.restore",
            "Upload transport:",
            "matrix.recovery.key",
            "matrix.recovery.setup",
            "matrix.recovery.generated-key",
            "generatedRecoveryKey = nil",
            "interactiveDismissDisabled(generatedRecoveryKey != nil)",
            "matrix.room.create",
            "matrix.room.name",
            "matrix.room.topic",
            "matrix.room.invitees",
            "matrix.room.visibility",
            "MatrixRoomVisibility.inviteOnly",
            "MatrixRoomVisibility.public",
            "recoveryKey = \"\"",
            "restoreSavedHomeserverIfAvailable",
            "await coordinator.restore()",
            "UserDefaults.standard",
            "matrix.rooms.sidebar",
            "matrix.rooms.sync",
            "matrix.session.switcher",
            "matrix.session.add",
            "matrix.session.continue",
            "model.switchSession",
            "HyphaMatrixKeychainCredentialStore()",
            "savePassword(",
            "signIn(with credential:",
            "storedSessions()",
            "sidebarSectionTitle(\"Invites\")",
            "MatrixSidebarRoomGroups(rooms: rooms)",
            "matrix.thread.timeline",
            "matrix.thread.composer",
            "matrix.session.expired",
            "matrix.timeline.undecryptable",
            "matrix.trust.blocked",
            "matrix.recovery.required",
            "matrix.homeserver.url",
            "matrix.homeserver.connect",
            "Check and connect",
            "MatrixHomeserverHealthChecker(",
            "MatrixRustSDKChatService(",
            "MatrixEncryptedSessionVault()",
            "MatrixRustLiveClientFactory(",
            ".navigationSplitViewColumnWidth(min: 230, ideal: 268, max: 340)",
            "private var detailTitle",
            ".keyboardShortcut(.defaultAction)"
        ]

        for marker in requiredMarkers {
            XCTAssertTrue(source.contains(marker), "Missing native shell contract marker: \(marker)")
        }
    }

    func testSecurityGuidanceIsAdditiveToRoomsAndChatAuthority() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        guard let guidance = source.range(of: "if isAuthenticated {"),
              let banner = source.range(of: "securityBanner", range: guidance.lowerBound..<source.endIndex),
              let chat = source.range(of: "chatDetail", range: banner.upperBound..<source.endIndex) else {
            return XCTFail("Authenticated security guidance and chat must share the detail surface")
        }
        XCTAssertLessThan(guidance.lowerBound, banner.lowerBound)
        XCTAssertLessThan(banner.lowerBound, chat.lowerBound)

        let shellEnd = source.range(of: "private struct ZenithMessageComposer")?.lowerBound ?? source.endIndex
        let shellSource = String(source[..<shellEnd])
        let forbiddenAuthorityGates = [
            ".disabled(model.trustState",
            ".disabled(model.recoveryState",
            "model.trustState == .verifiedByCurrentSelfSigningKey",
            "model.recoveryState == .ready"
        ]
        for marker in forbiddenAuthorityGates {
            XCTAssertFalse(shellSource.contains(marker), "Security guidance must not become chat authority: \(marker)")
        }
    }

    func testFirstRunRegistrationClearsSecretsAndKeepsSecuritySetupOptional() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let authSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/Auth/HyphaAuthenticationViews.swift"),
            encoding: .utf8
        )
        let messageRowSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/Chat/HyphaChatMessageRow.swift"),
            encoding: .utf8
        )
        let messagePresentationSource = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/HyphaChatMessagePresentation.swift"),
            encoding: .utf8
        )
        let source = [appSource, authSource, messageRowSource, messagePresentationSource]
            .joined(separator: "\n") + "\n" + (try String(
                contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/HyphaSecurityBanner.swift"),
                encoding: .utf8
            ))

        guard let submit = authSource.range(of: "private func submit()"),
              let clearSecrets = authSource.range(of: "clearSecrets()", range: submit.lowerBound..<authSource.endIndex),
              let task = authSource.range(of: "Task {", range: clearSecrets.upperBound..<authSource.endIndex),
              let register = appSource.range(of: "registrationClient.register"),
              let signIn = appSource.range(of: "await coordinator.signIn", range: register.upperBound..<appSource.endIndex) else {
            return XCTFail("Registration must clear UI secrets before the inhibited registration and deliberate SDK sign-in transition")
        }
        XCTAssertLessThan(clearSecrets.lowerBound, task.lowerBound)
        XCTAssertLessThan(register.lowerBound, signIn.lowerBound)
        XCTAssertTrue(source.contains("Account created. Encrypted rooms and chat are ready now."))
        XCTAssertTrue(source.contains("Device security and recovery are optional next steps."))
        XCTAssertTrue(source.contains("matrix.registration.first-run"))
        XCTAssertTrue(source.contains("firstDevicePassword = \"\""))
        XCTAssertTrue(source.contains("await model.continueFirstDeviceTrust(password: passwordForRequest)"))
        XCTAssertTrue(source.contains("guard firstDeviceTrustBootstrapState != .bootstrapping else { return }"))
        XCTAssertTrue(source.contains("Verify with another Hypha device"))
        XCTAssertTrue(source.contains("matrix.timeline.authenticity"))
        XCTAssertTrue(source.contains("authenticityPresentation"))
        XCTAssertTrue(source.contains("private func clearSecrets() {\n        username = \"\""))
        XCTAssertFalse(source.contains("registrationAvailability == .inviteToken && model.trustState"))
        XCTAssertFalse(source.contains("registrationAvailability == .inviteToken && model.recoveryState"))
    }

    func testProductDocsDefineZenithFirstSecurityBoundary() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let architecture = try String(contentsOf: root.appendingPathComponent("docs/architecture.md"), encoding: .utf8)
        let securityModel = try String(contentsOf: root.appendingPathComponent("docs/security-model.md"), encoding: .utf8)
        let faq = try String(contentsOf: root.appendingPathComponent("docs/faq.md"), encoding: .utf8)

        XCTAssertTrue(readme.contains("Hypha-to-Hypha encrypted chat as the primary Matrix interoperability path"))
        XCTAssertTrue(readme.contains("Element is an optional compatibility probe"))
        XCTAssertTrue(readme.contains("conformance evidence is tracked separately and is not claimed here"))
        XCTAssertFalse(readme.contains("two-client interoperability evidence with Element"))
        XCTAssertTrue(architecture.contains("security guidance separately from chat authority"))
        XCTAssertTrue(securityModel.contains("not prerequisites for encrypted room creation or current encrypted chat"))
        XCTAssertTrue(faq.contains("proven invalid-signature identity violation"))
    }

    func testAsyncChatOperationsRejectObsoleteAccountCoordinatorResults() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        let identityGuards = source.components(
            separatedBy: "guard coordinator === self.coordinator else { return }"
        ).count - 1
        XCTAssertGreaterThanOrEqual(identityGuards, 3)
        XCTAssertTrue(source.contains("let draftContext = draftContext(for: room)"))
    }

    func testChatTimelineHonorsReducedMotion() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(source.contains("if animated && !reduceMotion"))
    }

    func testChatAsyncStatusChangesPostVoiceOverAnnouncements() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AccessibilityNotification.Announcement"))
        XCTAssertTrue(source.contains("New messages are available. Jump to latest is now available."))
        XCTAssertTrue(source.contains("Draft preserved; press Send to retry."))
    }

    func testRecoverySheetShowsSafeRecoveryFailureFeedback() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        XCTAssertTrue(source.contains("recoveryErrorPresentation"))
        XCTAssertTrue(source.contains("Recovery diagnostic"))
    }

    func testNativeShellUsesZenithDesignSystemAndLandingInspiredComposer() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let design = try [
            root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithDesignSystem.swift"),
            root.appendingPathComponent("Sources/ZenithMacOSClient/DesignSystem/Atoms/HyphaButton.swift"),
        ].map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        for marker in [
            "static let base = Color(hex: 0x131A18)",
            "static let brand = Color(hex: 0x58EFC9)",
            "static let content = Color(hex: 0xD1FAF0)",
            "static let glassBorder",
            "static let full: CGFloat = 9_999",
            "static let technical",
            "static let corporate",
            "ZenithGlassSurface",
            "ZenithPrimaryButtonStyle",
        ] {
            XCTAssertTrue(design.contains(marker), "Missing native Zenith design marker: \(marker)")
        }

        for marker in [
            "ZenithMessageComposer(",
            "Capsule()",
            ".frame(minHeight: 64)",
            "lineWidth: isFocused ? 2 : 1",
            "matrix.thread.send",
            ".zenithAppSurface()",
        ] {
            XCTAssertTrue(app.contains(marker), "Missing landing-inspired native shell marker: \(marker)")
        }
        XCTAssertFalse(app.contains("TextField(\"Message \\(room.name)\", text: $model.composer)"))
    }

    func testBundlePackagesCanonicalZenithOSDockIcon() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let info = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        let build = try String(contentsOf: root.appendingPathComponent("build-app.sh"), encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Resources/ZenithOSIcon.icns").path))
        XCTAssertTrue(info.contains("CFBundleIconFile"))
        XCTAssertTrue(info.contains("ZenithOSIcon"))
        XCTAssertTrue(build.contains("ZenithOSIcon.icns"))
    }

    func testInlineRoomInvitesArePermissionFilteredAndRevalidatedAtSubmit() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )
        let sdk = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRustSDKChatService.swift"),
            encoding: .utf8
        )

        for marker in [
            "MatrixRoomInvitationPolicy.eligibleRooms",
            "MatrixRoomInviteSheet",
            "matrix.room.invite.inline",
            "matrix.room.invite.destination",
            "matrix.room.invite.userIDs",
            "matrix.room.invite.submit",
            "Confirm invitations",
            ".confirmationDialog(",
            "resolvedInviteUserIDs",
            "sidebarSectionTitle(\"DMs\")",
            "User found",
            "Copy invite link",
            "NSPasteboard.general",
        ] {
            XCTAssertTrue(app.contains(marker), "Missing inline room-invite contract: \(marker)")
        }
        for marker in [
            "let powerLevels = try await room.getPowerLevels()",
            "powerLevels.canUserInvite(userId: room.ownUserId())",
            "room.inviteUserById(userId: userID)",
            "client.getProfile(userId: userID)",
            "room.matrixToPermalink()",
        ] {
            XCTAssertTrue(sdk.contains(marker), "Missing authoritative invite revalidation: \(marker)")
        }
        let permissionCheck = try XCTUnwrap(sdk.range(of: "powerLevels.canUserInvite(userId: room.ownUserId())"))
        let inviteCall = try XCTUnwrap(sdk.range(of: "room.inviteUserById(userId: userID)"))
        XCTAssertLessThan(permissionCheck.lowerBound, inviteCall.lowerBound)
        XCTAssertFalse(sdk.contains("searchUsers("))
        let dmSection = try XCTUnwrap(app.range(of: "sidebarSectionTitle(\"DMs\")"))
        let inviteSection = try XCTUnwrap(app.range(of: "sidebarSectionTitle(\"Invites\")"))
        let spacesSection = try XCTUnwrap(app.range(of: "sidebarCreationHeader(\"Spaces\""))
        XCTAssertLessThan(dmSection.lowerBound, inviteSection.lowerBound)
        XCTAssertLessThan(inviteSection.lowerBound, spacesSection.lowerBound)
    }

    func testSidebarSuccessMessagesUseSuccessColor() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClient/ZenithMacOSClientApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(app.contains("roomSyncMessageTone = invited ? .success : .error"))
        XCTAssertTrue(app.contains("case .success: ZenithDesign.Palette.success"))
        XCTAssertFalse(app.contains("Text(roomSyncMessage)\n                        .font(.caption)\n                        .foregroundStyle(ZenithDesign.Palette.error)"))
    }
}
