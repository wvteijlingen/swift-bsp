import Foundation
import LanguageServerProtocol

public struct LogReporter: Sendable {
    private let connection: (any Connection)?

    public init(connection: (any Connection)?) {
        self.connection = connection
    }

    public func log(message: String, type: WindowMessageType = .log, logName: String? = nil) {
        let notification = LogMessageNotification(type: type, message: message, logName: "swift-bsp")
        connection?.send(notification)
    }

    public func show(message: String, type: WindowMessageType = .log) {
        let notification = ShowMessageNotification(type: type, message: message)
        connection?.send(notification)
    }
}
