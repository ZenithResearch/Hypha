import AppKit
import Combine
import Foundation

@MainActor
final class HyphaUpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case updating
        case installed
        case failed
    }

    @Published private(set) var state: State = .idle

    var statusText: String? {
        switch state {
        case .idle: nil
        case .updating: "Pulling and rebuilding GitHub main…"
        case .installed: "Update installed. Restart Hypha to use it."
        case .failed: "Update failed. The current application was left unchanged."
        }
    }

    func updateFromGitHubMain() {
        guard state != .updating else { return }
        guard let scriptURL = Bundle.main.url(
            forResource: "update-from-main",
            withExtension: "sh"
        ) else {
            state = .failed
            return
        }

        state = .updating
        let scriptPath = scriptURL.path
        let bundlePath = Bundle.main.bundlePath
        Task {
            let succeeded = await Task.detached(priority: .userInitiated) {
                Self.runUpdater(scriptPath: scriptPath, bundlePath: bundlePath)
            }.value
            state = succeeded ? .installed : .failed
        }
    }

    func restart() {
        guard state == .installed else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
        helper.arguments = [
            "-c",
            "sleep 1; /usr/bin/open -n \"$1\"",
            "hypha-restart",
            Bundle.main.bundlePath,
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed
        }
    }

    nonisolated private static func runUpdater(scriptPath: String, bundlePath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptPath, bundlePath]
        var environment: [String: String] = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
        ]
        if FileManager.default.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer") {
            environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationReason == .exit && process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
