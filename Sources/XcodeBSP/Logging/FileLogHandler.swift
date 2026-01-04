import Foundation
import Logging

struct FileLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL

        // if FileManager.default.fileExists(atPath: fileURL.path) {
        //     try? FileManager.default.removeItem(at: fileURL)
        // }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let date = Date().formatted(
            .dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits).hour().minute().second()
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

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set {
            metadata[metadataKey] = newValue
        }
    }
}
