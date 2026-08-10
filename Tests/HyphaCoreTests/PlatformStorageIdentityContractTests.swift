import Foundation
import XCTest
@testable import HyphaCore

final class PlatformStorageIdentityContractTests: XCTestCase {
    private struct IdentityFixture {
        let bundle: String
        let keychainService: String
        let vaultRoot: String
        let cryptoRoot: String
        let defaultsKey: String
        let loggerSubsystem: String
        let legacyMigrationEnabled: Bool

        var namespaces: [String] {
            [bundle, keychainService, vaultRoot, cryptoRoot, defaultsKey, loggerSubsystem]
        }
    }

    private static let macOS = IdentityFixture(
        bundle: "ca.zenithresearch.macos.client",
        keychainService: "ca.zenithresearch.macos.client.matrix",
        vaultRoot: "ca.zenithresearch.macos.client/MatrixSessionVault-v1",
        cryptoRoot: "ZenithMacOSClient/Matrix",
        defaultsKey: "ca.zenithresearch.macos.client.matrix.homeserver",
        loggerSubsystem: "ca.zenithresearch.macos.client",
        legacyMigrationEnabled: true
    )

    private static let iOS = IdentityFixture(
        bundle: "ca.zenithresearch.ios.client",
        keychainService: "ca.zenithresearch.ios.client.matrix",
        vaultRoot: "ca.zenithresearch.ios.client/MatrixSessionVault-v1",
        cryptoRoot: "ZenithIOSClient/Matrix",
        defaultsKey: "ca.zenithresearch.ios.client.matrix.homeserver",
        loggerSubsystem: "ca.zenithresearch.ios.client",
        legacyMigrationEnabled: false
    )

    func testRuntimePlatformStorageIdentitiesPreserveMacOSAndIsolateIOS() {
        XCTAssertEqual(MatrixPlatformStorageIdentity.macOS.bundleIdentifier, Self.macOS.bundle)
        XCTAssertEqual(MatrixPlatformStorageIdentity.macOS.keychainService, Self.macOS.keychainService)
        XCTAssertEqual(MatrixPlatformStorageIdentity.macOS.vaultRoot, Self.macOS.vaultRoot)
        XCTAssertEqual(MatrixPlatformStorageIdentity.macOS.cryptoRoot, Self.macOS.cryptoRoot)
        XCTAssertEqual(MatrixPlatformStorageIdentity.macOS.homeserverDefaultsKey, Self.macOS.defaultsKey)
        XCTAssertEqual(MatrixPlatformStorageIdentity.macOS.loggerSubsystem, Self.macOS.loggerSubsystem)
        XCTAssertTrue(MatrixPlatformStorageIdentity.macOS.legacyMigrationEnabled)

        XCTAssertEqual(MatrixPlatformStorageIdentity.iOS.bundleIdentifier, Self.iOS.bundle)
        XCTAssertEqual(MatrixPlatformStorageIdentity.iOS.keychainService, Self.iOS.keychainService)
        XCTAssertEqual(MatrixPlatformStorageIdentity.iOS.vaultRoot, Self.iOS.vaultRoot)
        XCTAssertEqual(MatrixPlatformStorageIdentity.iOS.cryptoRoot, Self.iOS.cryptoRoot)
        XCTAssertEqual(MatrixPlatformStorageIdentity.iOS.homeserverDefaultsKey, Self.iOS.defaultsKey)
        XCTAssertEqual(MatrixPlatformStorageIdentity.iOS.loggerSubsystem, Self.iOS.loggerSubsystem)
        XCTAssertFalse(MatrixPlatformStorageIdentity.iOS.legacyMigrationEnabled)

        #if os(iOS)
        XCTAssertEqual(MatrixPlatformStorageIdentity.current, .iOS)
        #else
        XCTAssertEqual(MatrixPlatformStorageIdentity.current, .macOS)
        #endif
    }

    func testKeychainWritesKeepCurrentAccessibilityAndNeverSynchronize() throws {
        let matrixStorage = try text("Sources/HyphaCore/MatrixRustSDKChatService.swift")
        let credentialStorage = try text("Sources/HyphaCore/HyphaMatrixCredentialStore.swift")

        XCTAssertTrue(credentialStorage.contains("private static let service = \"Hypha\""))
        XCTAssertTrue(credentialStorage.contains("private static let accountPrefix = \"matrix-password:\""))
        XCTAssertTrue(matrixStorage.contains("item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
        XCTAssertTrue(matrixStorage.contains("item[kSecAttrSynchronizable as String] = false"))
        XCTAssertTrue(credentialStorage.contains("item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
        XCTAssertTrue(credentialStorage.contains("kSecAttrSynchronizable as String: false"))
    }

    func testHyphaCoreDoesNotSelectAKeychainAccessGroup() throws {
        let files = try swiftFiles(below: repositoryRoot.appendingPathComponent("Sources/HyphaCore"))
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("kSecAttrAccessGroup"), file.path)
        }
    }

    func testRuntimeIOSNamespacesAreDisjointFromMacOSAndDisableLegacyMigration() {
        let mobileIdentity = MatrixPlatformStorageIdentity.iOS
        let desktopIdentity = MatrixPlatformStorageIdentity.macOS
        XCTAssertFalse(mobileIdentity.legacyMigrationEnabled)
        XCTAssertTrue(desktopIdentity.legacyMigrationEnabled)

        for mobile in mobileIdentity.namespaces {
            for desktop in desktopIdentity.namespaces {
                XCTAssertNotEqual(mobile, desktop)
                XCTAssertFalse(mobile.hasPrefix(desktop + "."), "iOS namespace nests under macOS: \(mobile)")
                XCTAssertFalse(mobile.hasPrefix(desktop + "/"), "iOS namespace nests under macOS: \(mobile)")
                XCTAssertFalse(desktop.hasPrefix(mobile + "."), "macOS namespace nests under iOS: \(desktop)")
                XCTAssertFalse(desktop.hasPrefix(mobile + "/"), "macOS namespace nests under iOS: \(desktop)")
            }
        }

        for namespace in mobileIdentity.namespaces {
            let desktopLegacyNamespaces = desktopIdentity.legacyNamespaces
            XCTAssertFalse(desktopLegacyNamespaces.contains(where: { namespace == $0 || namespace.hasPrefix($0 + ".") || namespace.hasPrefix($0 + "/") }))
        }
    }

    func testLoggingCallsAndScannerFixturesRejectSecretBearingLabelsWithoutValues() throws {
        let safeFixture = "logger.notice(\"stage=ready response=1\")"
        let forbiddenFixture = "logger.notice(\"access_token\")"
        XCTAssertTrue(secretBearingLoggingStatements(in: safeFixture).isEmpty)
        XCTAssertEqual(secretBearingLoggingStatements(in: forbiddenFixture), [forbiddenFixture])
        let newlyForbiddenFixtures = [
            "logger.notice(\"registration_token\")",
            "logger.notice(\"sas_value\")",
            "logger.notice(\"matrix_id\")",
            "logger.notice(\"device_id\")",
            "logger.notice(\"event_body\")",
            "logger.notice(\"event_content\")",
            "logger.notice(\"transaction_id\")",
        ]
        for fixture in newlyForbiddenFixtures {
            XCTAssertEqual(secretBearingLoggingStatements(in: fixture), [fixture])
        }

        let multilineAccessToken = """
        logger.notice(
            "access_token"
        )
        """
        let camelCaseLabels = [
            "logger.info(\"accessToken\")",
            "logger.warning(\"deviceID\")",
            "logger.error(\"eventBody\")",
        ]
        let levelNotice = """
        logger.log(
            level: .notice,
            "transaction_id"
        )
        """
        let multilineSafeStage = """
        logger.notice(
            "stage=ready response=1"
        )
        """
        XCTAssertEqual(secretBearingLoggingStatements(in: multilineAccessToken), [multilineAccessToken])
        for fixture in camelCaseLabels {
            XCTAssertEqual(secretBearingLoggingStatements(in: fixture), [fixture])
        }
        XCTAssertEqual(secretBearingLoggingStatements(in: levelNotice), [levelNotice])
        XCTAssertTrue(secretBearingLoggingStatements(in: multilineSafeStage).isEmpty)

        let roots = [repositoryRoot.appendingPathComponent("Sources"), repositoryRoot.appendingPathComponent("Tests")]
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        let files = try roots.flatMap(swiftFiles).filter { $0.standardizedFileURL != thisFile }
        let violations = try files.flatMap { file -> [String] in
            secretBearingLoggingStatements(in: try String(contentsOf: file, encoding: .utf8)).map {
                "\(file.path): \($0)"
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    private var repositoryRoot: URL { Self.repositoryRoot }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            XCTFail("Cannot enumerate \(root.path)")
            return []
        }
        return try enumerator.compactMap { entry -> URL? in
            guard let url = entry as? URL, url.pathExtension == "swift" else { return nil }
            return try url.resourceValues(forKeys: Set(keys)).isRegularFile == true ? url : nil
        }.sorted { $0.path < $1.path }
    }

    private func secretBearingLoggingStatements(in source: String) -> [String] {
        let forbiddenLabels = [
            "pass" + "word", "pass" + "phrase", "access_" + "token", "refresh_" + "token",
            "session_" + "token", "session_" + "key", "api_" + "key", "private_" + "key",
            "recovery_" + "key", "root_" + "key", "store_" + "key", "cred" + "ential",
            "author" + "ization", "sec" + "ret", "registration_" + "token", "sas_" + "value",
            "matrix_" + "id", "device_" + "id", "event_" + "body", "event_" + "content",
            "transaction_" + "id",
        ].map(comparableLabel)

        return loggingCallExpressions(in: source).filter { expression in
            let normalized = comparableLabel(expression)
            return forbiddenLabels.contains(where: normalized.contains)
        }
    }

    private func comparableLabel(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private func loggingCallExpressions(in source: String) -> [String] {
        let characters = Array(source)
        let directLevels = ["debug", "info", "notice", "warning", "error", "fault"]
        var expressions: [String] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "." else {
                index += 1
                continue
            }

            let methodStart = index + 1
            var methodEnd = methodStart
            while methodEnd < characters.count, characters[methodEnd].isLetter {
                methodEnd += 1
            }
            let method = String(characters[methodStart..<methodEnd])
            guard directLevels.contains(method) || method == "log" else {
                index += 1
                continue
            }

            var openingParenthesis = methodEnd
            while openingParenthesis < characters.count, characters[openingParenthesis].isWhitespace {
                openingParenthesis += 1
            }
            guard openingParenthesis < characters.count, characters[openingParenthesis] == "(",
                  let closingParenthesis = balancedCallEnd(in: characters, openingAt: openingParenthesis) else {
                index += 1
                continue
            }

            if method == "log" {
                let arguments = String(characters[(openingParenthesis + 1)..<closingParenthesis])
                let normalizedArguments = comparableLabel(arguments)
                guard directLevels.contains(where: { normalizedArguments.hasPrefix("level" + $0) }) else {
                    index = closingParenthesis + 1
                    continue
                }
            }

            var expressionStart = index
            while expressionStart > 0, characters[expressionStart - 1] != "\n" {
                expressionStart -= 1
            }
            let expression = String(characters[expressionStart...closingParenthesis])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            expressions.append(expression)
            index = closingParenthesis + 1
        }
        return expressions
    }

    private func balancedCallEnd(in characters: [Character], openingAt start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false

        for index in start..<characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }
}
