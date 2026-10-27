import Foundation
import LanguageServerProtocol

struct LogReporter: Sendable {
    private let connection: any Connection

    init(connection: any Connection) {
        self.connection = connection
    }

    func log(message: String, type: WindowMessageType = .log) {
        let notification = LogMessageNotification(type: type, message: message, logName: "swift-bsp")
        connection.send(notification)
    }

    func show(message: String, type: WindowMessageType = .log) {
        let notification = ShowMessageNotification(type: type, message: message)
        connection.send(notification)
    }
}
