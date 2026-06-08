import Foundation
import Subprocess
import System

class Simulator {
    /// If there are multiple matches, returns the id that sorts first (so at least it's deterministic).
    static func udidForDevice(named name: String) async throws -> String {
        let uuid = try await devices()
            .filter { ($0.name == name || $0.udid == name) && $0.isAvailable }
            .map { $0.udid }
            .sorted()
            .first

        guard let uuid else {
            fatalError()
        }

        return uuid
    }

    static func open(udid: String) async throws {
        _ = try await succeedAndGetOutput(.name("open"), ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])

        while true {
            let devs = try await devices()
            if devs.contains(where: { $0.state == "Booted" }) {
                if !devs.contains(where: { $0.udid == udid && $0.state == "Booted" }) {
                    // Something is booted but not the one we want
                    try await _ = run(.name("xcrun"), arguments: ["simctl", "boot", udid], output: .discarded)
                }
                break
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    static func install(appPath: FilePath, deviceUdid: String) async throws {
        try await open(udid: deviceUdid)
        _ = try await succeedAndGetOutput(.name("xcrun"), ["simctl", "install", deviceUdid, appPath.string])
    }

    static func launchProcess(bundleId: String, deviceUdid: String, extraFlags: [String] = []) throws -> Configuration {
        // When simctl launch is run from terminal, it prints the pid in the first line. Don't be fooled
        // though - it doesn't do that here (different behaviour due to lack of terminal).
        Configuration(
            .name("xcrun"),
            arguments: Arguments(
                [
                    "simctl",
                    "launch",
                    "--console-pty",
                    "--terminate-running-process"
                ] + extraFlags + [deviceUdid, bundleId]
            )
        )
    }

    /// Must call this as soon as you start the launcher process, as it waits for a change in pid - if you leave it
    /// too late it won't see the change. Uses this mechanism so as not to pick up an already running instance.
    static func pidOfLaunchedApp(deviceUdid: String, appBundleName: String) async throws -> Int {
        func newestAppProcess() async throws -> Int? {
            let pid = try await succeedAndGetOutput(.name("ps"), ["aux"])
                .split(separator: "\n")
                .filter {
                    $0.contains("CoreSimulator/Devices/\(deviceUdid)/") && $0.contains("/\(appBundleName)/")
                }
                .compactMap {
                    let bits = try $0.split(separator: Regex("\\s+"))
                    return bits.count > 2 ? Int(bits[1]) : nil
                }
                .sorted().reversed()
                .first
            return pid
        }

        let original = try await newestAppProcess()
        var latest = original
        for _ in 1...5 {
            try? await Task.sleep(for: .seconds(1))
            latest = try await newestAppProcess()
            if latest != nil && latest != original {
                return latest!
            }
        }
        throw BuildServerError.generic("Timed out waiting for launch of \(appBundleName)")
    }

    static func devices() async throws -> [Device] {
        let s = try await succeedAndGetOutput(.name("xcrun"), ["simctl", "list", "devices", "--json"])
        return try JSONDecoder().decode([String: [String: [Device]]].self, from: s.data(using: .utf8)!)["devices"]?
            .flatMap { $0.1 } ?? []
    }
}

extension Simulator {
    struct Device: Codable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
    }
}


struct XcodeDestination {
    let platform: String
    let arch: String
    let id: String
    let os: String
    let name: String

    var displayName: String {
        "\(platform) - \(name) (\(os))"
    }

    init?(xcodebuildLine line: String) {
        // Remove surrounding braces
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "{} \t").union(.whitespaces))

        var result: [String: String] = [:]

        // Split into key/value pairs
        let pairs = trimmed.split(separator: ",")

        for pair in pairs {
            let parts = pair.split(separator: ":", maxSplits: 1)

            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            result[key] = value
        }

        if result["error"] != nil {
            // Most likely an ineligible destination
            return nil
        }

        guard let platform = result["platform"],
              let arch = result["arch"],
              let id = result["id"],
              let os = result["OS"],
              let name = result["name"]
        else {
            return nil
        }

        self.platform = platform
        self.arch = arch
        self.id = id
        self.os = os
        self.name = name
    }
}
