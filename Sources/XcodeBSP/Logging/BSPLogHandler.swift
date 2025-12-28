// import BuildServerProtocol
// import Foundation
// import LanguageServerProtocolTransport
// import Logging

// struct BSPLogHandler: LogHandler {
//     var metadata: Logger.Metadata = [:]
//     var logLevel: Logging.Logger.Level = .info

//     func log(
//         level: Logger.Level,
//         message: Logger.Message,
//         metadata: Logger.Metadata?,
//         source: String,
//         file: String,
//         function: String,
//         line: UInt
//     ) {
//         guard let connection = metadata?["bspConnection"] as? JSONRPCConnection else {
//             fatalError()
//         }

//         let logLine = "\(level) \(message)\n"

//         let type: MessageType =
//             switch level {
//             case .critical: .error
//             case .debug: .info
//             case .error: .error
//             case .info: .info
//             case .notice: .info
//             case .trace: .info
//             case .warning: .warning
//             }

//         connection.send(
//             OnBuildLogMessageNotification(
//                 type: type,
//                 task: nil,
//                 originId: nil,
//                 message: logLine,
//                 structure: nil
//             ))
//     }

//     subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
//         get {
//             metadata[metadataKey]
//         }
//         set {
//             metadata[metadataKey] = newValue
//         }
//     }
// }
