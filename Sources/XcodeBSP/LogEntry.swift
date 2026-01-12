// import BuildServerProtocol

// /// An entry that can be logged to a file or to the BSP client.
// struct LogEntry {
//     let type: BuildServerProtocol.MessageType
//     let message: String
//     let structure: BuildServerProtocol.StructuredLogKind?

//     static func log(
//         _ message: Any,
//         _ structure: BuildServerProtocol.StructuredLogKind? = nil
//     ) -> LogEntry {
//         LogEntry(type: .log, message: String(describing: message), structure: structure)
//     }

//     static func info(
//         _ message: Any,
//         _ structure: BuildServerProtocol.StructuredLogKind? = nil
//     ) -> LogEntry {
//         LogEntry(type: .info, message: String(describing: message), structure: structure)
//     }

//     static func warning(
//         _ message: Any,
//         _ structure: BuildServerProtocol.StructuredLogKind? = nil
//     ) -> LogEntry {
//         LogEntry(type: .warning, message: String(describing: message), structure: structure)
//     }

//     static func error(
//         _ message: Any,
//         _ structure: BuildServerProtocol.StructuredLogKind? = nil
//     ) -> LogEntry {
//         LogEntry(type: .error, message: String(describing: message), structure: structure)
//     }
// }
