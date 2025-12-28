import BuildServerProtocol
import Logging

extension Logger {
    func log(
        level: BuildServerProtocol.MessageType,
        _ message: @autoclosure () -> String,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let logLevel: Logger.Level =
            switch level {
            case .error: .error
            case .info: .info
            case .log: .info
            case .warning: .warning
            }

        log(
            level: logLevel,
            "\(message())",
            metadata: metadata(),
            source: nil,
            file: file,
            function: function,
            line: line
        )
    }
}

// struct Logger {
//     let url = URL(filePath: "/Users/ward/Desktop/xcodebsp-output.log")
//     var bspLogger: ((String) -> Void)?

//     func warning(_ message: String) {
//         info(message)
//     }

//     func dump<T>(_ any: T) {
//         info(String(describing: any))
//     }

//     func info(_ message: String) {
//         let message = "\(message)\n\n"
//         bspLogger?(message)

//         if let handle = try? FileHandle(forWritingTo: url) {
//             handle.seekToEndOfFile()
//             if let data = message.data(using: .utf8) {
//                 handle.write(data)
//             }
//             try? handle.close()
//         } else {
//             // File doesn't exist, create it
//             try? message.write(to: url, atomically: true, encoding: .utf8)
//         }
//     }
// }
