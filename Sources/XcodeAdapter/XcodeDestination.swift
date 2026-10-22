import Foundation

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
