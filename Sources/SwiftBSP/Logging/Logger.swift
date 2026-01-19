import ArgumentParser
import Foundation
import ToolsProtocolsSwiftExtensions

extension Logger {
    enum Level: String, Comparable, ExpressibleByArgument {
        case debug, info, warning, error

        private var severity: Int {
            switch self {
            case .debug: 0
            case .info: 1
            case .warning: 2
            case .error: 3
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.severity < rhs.severity
        }
    }
}

struct Logger {
    private let queque = AsyncQueue<Serial>()
    private let fileURL: URL
    private let minLevel: Level

    public init(fileURL: URL, minLevel: Level) {
        self.fileURL = fileURL
        self.minLevel = minLevel
    }

    func debug(_ message: Sendable) {
        self.log(.debug, message: message)
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
        guard level >= minLevel else { return }

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
