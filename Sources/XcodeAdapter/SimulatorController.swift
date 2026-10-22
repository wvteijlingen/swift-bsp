import Foundation
import Subprocess
import System
import Shared

struct SimulatorController {
    let udid: String

    init(udid: String) {
        self.udid = udid
    }

    static private func allDevices() async throws -> [SimCtlDevicesListResponse.Device] {
        let json = try await succeedAndGetOutput(.name("xcrun"), ["simctl", "list", "devices", "--json"])
        let response = try JSONDecoder().decode(SimCtlDevicesListResponse.self, from: json.data(using: .utf8)!)

        return response.devices.flatMap(\.value)
    }

    func open() async throws {
        _ = try await succeedAndGetOutput(.name("open"), ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])

        while true {
            let devices = try await Self.allDevices()

            if devices.contains(where: { $0.state == "Booted" }) {
                if !devices.contains(where: { $0.udid == udid && $0.state == "Booted" }) {
                    // Something is booted but not the one we want
                    try await _ = run(.name("xcrun"), arguments: ["simctl", "boot", udid], output: .discarded)
                }
                break
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    func install(appBundleAtPath path: FilePath) async throws {
        _ = try await succeedAndGetOutput(.name("xcrun"), ["simctl", "install", udid, path.string])
    }

    func launchProcess(bundleID: String, extraFlags: [String] = []) async throws {
        // When simctl launch is run from terminal, it prints the pid in the first line. Don't be fooled
        // though - it doesn't do that here (different behaviour due to lack of terminal).
        let subprocess = Subprocess.Configuration(
            .name("xcrun"),
            arguments: Arguments(
                [
                    "simctl",
                    "launch",
                    udid,
                    bundleID,
                    "--console-pty",
                    "--terminate-running-process",
                ] + extraFlags
            )
        )

        _ = try await succeedAndGetOutput(subprocess)
    }

    /// Must call this as soon as you start the launcher process, as it waits for a change in pid - if you leave it
    /// too late it won't see the change. Uses this mechanism so as not to pick up an already running instance.
    func pidOfProcess(bundleID: String) async throws -> Int {
        func newestAppProcess() async throws -> Int? {
            let pid = try await succeedAndGetOutput(.name("ps"), ["aux"])
                .split(separator: "\n")
                .filter {
                    $0.contains("CoreSimulator/Devices/\(udid)/") && $0.contains("/\(bundleID)/")
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
        throw BuildServerError.generic("Timed out waiting for launch of \(bundleID)")
    }
}

// class Simulator {
// /// If there are multiple matches, returns the id that sorts first (so at least it's deterministic).
// static func udidForDevice(named name: String) async throws -> String {
//     let uuid = try await devices()
//         .filter { ($0.name == name || $0.udid == name) && $0.isAvailable }
//         .map { $0.udid }
//         .sorted()
//         .first

//     guard let uuid else {
//         fatalError()
//     }

//     return uuid
// }

// static func open(udid: String) async throws {
//     _ = try await succeedAndGetOutput(.name("open"), ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])

//     while true {
//         let devs = try await devices()
//         if devs.contains(where: { $0.state == "Booted" }) {
//             if !devs.contains(where: { $0.udid == udid && $0.state == "Booted" }) {
//                 // Something is booted but not the one we want
//                 try await _ = run(.name("xcrun"), arguments: ["simctl", "boot", udid], output: .discarded)
//             }
//             break
//         }
//         try? await Task.sleep(for: .seconds(0.5))
//     }
// }

// static func install(appPath: FilePath, deviceUdid: String) async throws {
//     try await open(udid: deviceUdid)
//     _ = try await succeedAndGetOutput(.name("xcrun"), ["simctl", "install", deviceUdid, appPath.string])
// }

// static func launchProcess(bundleId: String, deviceUdid: String, extraFlags: [String] = []) throws -> Configuration {
//     // When simctl launch is run from terminal, it prints the pid in the first line. Don't be fooled
//     // though - it doesn't do that here (different behaviour due to lack of terminal).
//     Configuration(
//         .name("xcrun"),
//         arguments: Arguments(
//             [
//                 "simctl",
//                 "launch",
//                 "--console-pty",
//                 "--terminate-running-process"
//             ] + extraFlags + [deviceUdid, bundleId]
//         )
//     )
// }

/// Must call this as soon as you start the launcher process, as it waits for a change in pid - if you leave it
/// too late it won't see the change. Uses this mechanism so as not to pick up an already running instance.
// static func pidOfLaunchedApp(deviceUdid: String, appBundleName: String) async throws -> Int {
//     func newestAppProcess() async throws -> Int? {
//         let pid = try await succeedAndGetOutput(.name("ps"), ["aux"])
//             .split(separator: "\n")
//             .filter {
//                 $0.contains("CoreSimulator/Devices/\(deviceUdid)/") && $0.contains("/\(appBundleName)/")
//             }
//             .compactMap {
//                 let bits = try $0.split(separator: Regex("\\s+"))
//                 return bits.count > 2 ? Int(bits[1]) : nil
//             }
//             .sorted().reversed()
//             .first
//         return pid
//     }

//     let original = try await newestAppProcess()
//     var latest = original
//     for _ in 1...5 {
//         try? await Task.sleep(for: .seconds(1))
//         latest = try await newestAppProcess()
//         if latest != nil && latest != original {
//             return latest!
//         }
//     }
//     throw BuildServerError.generic("Timed out waiting for launch of \(appBundleName)")
// }

// static func devices() async throws -> [Device] {
//     let s = try await succeedAndGetOutput(.name("xcrun"), ["simctl", "list", "devices", "--json"])
//     return try JSONDecoder().decode([String: [String: [Device]]].self, from: s.data(using: .utf8)!)["devices"]?
//         .flatMap { $0.1 } ?? []
// }
// }

// extension Simulator {
//     struct Device: Codable {
//         let udid: String
//         let name: String
//         let state: String
//         let isAvailable: Bool
//     }
// }

// MARK: - Models

private struct SimCtlDevicesListResponse: Decodable {
    let devices: [String: [Device]]  // Keyed by runtime (e.g. "com.apple.CoreSimulator.SimRuntime.iOS-26-4")

    struct Device: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
    }
}