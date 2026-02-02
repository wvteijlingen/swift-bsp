import ArgumentParser
import Foundation
import ToolsProtocolsSwiftExtensions

struct FileLogger {
    private let queque = AsyncQueue<Serial>()
    private let fileURL: URL

    public init(fileURL: URL, deleteExistingFile: Bool) {
        self.fileURL = fileURL
        
        if deleteExistingFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func log(_ message: Sendable) {
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

            let logLine = "[\(date)] \(message)\n"

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
