import Foundation
import ToolsProtocolsSwiftExtensions

extension Logger {
    enum Level: String {
        case info, warning, error
    }
}

struct Logger {
    private let fileURL: URL
    public let queque = AsyncQueue<Serial>()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func info(_ message: Sendable) {
        self.log(.info, message: message)
    }

    func warning(_ message: Sendable) {
        self.log(.info, message: message)
    }

    func error(_ message: Sendable) {
        self.log(.info, message: message)
    }

    func log(_ level: Level, message: Sendable) {
        queque.async {
            let date = Date().formatted(
                .dateTime
                    .year(.twoDigits)
                    .month(.twoDigits)
                    .day(.twoDigits)
                    .hour()
                    .minute(.twoDigits)
                    .second(.twoDigits)
                    .secondFraction(.milliseconds(0))
            )

            let logLine = "[\(date)] \(level.rawValue.padded(8, with: " ", side: .left)): \(message)\n"

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()

                if let data = logLine.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                // File doesn't exist, create it
                try? logLine.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
