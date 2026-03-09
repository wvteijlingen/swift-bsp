import Foundation
import System

enum Homebrew {
    static func homebrewPrefixPath() async throws -> FilePath {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["brew", "--prefix", "swift-bsp"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try await process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let prefixPath = String(data: data, encoding: .utf8) else {
            throw BuildServerError.invalidHomebrewPrefix
        }

        return FilePath(prefixPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
