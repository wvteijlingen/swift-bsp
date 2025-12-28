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
