import AppKit
import Combine
import Foundation

@MainActor
final class HyphaUpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case updating
        case failed
    }

    @Published private(set) var state: State = .idle

    var statusText: String? {
        switch state {
        case .idle: nil
        case .updating: "Opening the updater in Terminal…"
        case .failed: "The updater could not be opened. The current application was left unchanged."
        }
    }

    func updateFromGitHubMain() {
        guard state != .updating else { return }
        guard let scriptURL = Bundle.main.url(
            forResource: "launch-update-from-main",
            withExtension: "command"
        ) else {
            state = .failed
            return
        }

        state = .updating
        let scriptPath = scriptURL.path
        Task {
            let launched = await Task.detached(priority: .userInitiated) {
                Self.openUpdaterInTerminal(scriptPath: scriptPath)
            }.value
            if launched {
                NSApp.terminate(nil)
            } else {
                state = .failed
            }
        }
    }

    nonisolated private static func openUpdaterInTerminal(scriptPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [scriptPath]
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
