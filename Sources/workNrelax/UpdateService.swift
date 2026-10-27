import AppKit
import Foundation
import Observation

enum UpdateVersion {
    /// Strips a release tag ("v1.2.3") down to its numeric version ("1.2.3").
    static func fromTag(_ tag: String) -> String? {
        let digits = tag.dropFirst(tag.hasPrefix("v") ? 1 : 0)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return String(digits)
    }

    /// True when `version` is strictly newer than `other` (numeric semver compare).
    static func isNewer(_ version: String, than other: String) -> Bool {
        let lhs = components(version)
        let rhs = components(other)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

enum UpdateError: LocalizedError {
    case unexpectedResponse
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "GitHub returned an unexpected response."
        case .invalidArchive:
            "The downloaded update archive was invalid."
        }
    }
}

@MainActor @Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading
        case failure(String)
    }

    static let repo = "Royr9/WorknRelax"
    private static let appName = "workNrelax"
    private static let installDirectory = "/Applications"

    private(set) var state: State = .idle

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var currentVersionText: String {
        Self.currentVersion().map { "Version \($0)" } ?? "Development build"
    }

    nonisolated static func currentVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func checkForUpdates() async {
        state = .checking
        do {
            var request = URLRequest(url: latestReleaseInfoURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await session.data(for: request)
            guard
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = payload["tag_name"] as? String,
                let latest = UpdateVersion.fromTag(tag)
            else {
                throw UpdateError.unexpectedResponse
            }
            if let current = Self.currentVersion(), !UpdateVersion.isNewer(latest, than: current) {
                state = .upToDate
            } else {
                state = .available(version: latest)
            }
        } catch {
            state = .failure("Couldn't check for updates: \(error.localizedDescription)")
        }
    }

    func installUpdate() async {
        guard case .available = state else { return }
        state = .downloading
        do {
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("workNrelax-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }

            let (downloadURL, _) = try await session.download(from: latestDownloadURL)
            let zipURL = workDir.appendingPathComponent("\(Self.appName).zip")
            try FileManager.default.moveItem(at: downloadURL, to: zipURL)

            let unpackedDir = workDir.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpackedDir, withIntermediateDirectories: true)
            try await runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpackedDir.path])

            let newApp = unpackedDir.appendingPathComponent("\(Self.appName).app", isDirectory: true)
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdateError.invalidArchive
            }

            let destination = URL(fileURLWithPath: Self.installDirectory)
                .appendingPathComponent("\(Self.appName).app", isDirectory: true)
            try spawnReplaceHelper(newApp: newApp, destination: destination)
            NSApplication.shared.terminate(nil)
        } catch {
            state = .failure("Couldn't install the update: \(error.localizedDescription)")
        }
    }

    private var latestReleaseInfoURL: URL {
        URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
    }

    private var latestDownloadURL: URL {
        URL(string: "https://github.com/\(Self.repo)/releases/latest/download/\(Self.appName).zip")!
    }

    /// Launches a detached helper that waits for this process to exit, then swaps in the new
    /// bundle and relaunches. The helper outlives the app, so the replace happens after quit.
    private func spawnReplaceHelper(newApp: URL, destination: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        for _ in $(seq 1 20); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.5
        done
        rm -rf "\(destination.path)"
        ditto "\(newApp.path)" "\(destination.path)"
        open "\(destination.path)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try process.run()
    }

    private func runProcess(_ executablePath: String, _ arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw UpdateError.invalidArchive
            }
        }.value
    }
}
