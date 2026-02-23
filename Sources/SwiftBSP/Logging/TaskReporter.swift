import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import OSLog

struct TaskReporter: Sendable {
    private let connection: (any Connection)?

    init(connection: (any Connection)?) {
        self.connection = connection
    }

    func start(id: String? = nil, title: String) -> TaskId {
        let id = id.map { TaskId(id: String($0)) } ?? TaskId(id: UUID().uuidString)
        let title = "[swift-bsp] \(title)"
        let notification = TaskStartNotification(taskId: id, data: WorkDoneProgressTask(title: title).encodeToLSPAny())

        connection?.send(notification)
        Log.default.info("Start task \(id.id, privacy: .public): \(title, privacy: .public)")

        return id
    }

    func finish(id: TaskId, status: StatusCode, error: Error? = nil) {
        let errorMessage = error.map { "Error: \($0.localizedDescription)" }
        let notification = TaskFinishNotification(taskId: id, message: errorMessage, status: status)

        connection?.send(notification)

        let logLevel = status == .ok ? OSLogType.info : OSLogType.error
        let logMessage = ["\(status)", errorMessage].compactMap { $0 }.joined(separator: ", ")
        Log.default.log(level: logLevel, "Finish task \(id.id, privacy: .public): \(logMessage, privacy: .public)")
    }

    func finish(id: String, status: StatusCode, error: Error? = nil) {
        finish(id: TaskId(id: id), status: status, error: error)
    }

    nonisolated(nonsending) func log<T>(
        id: String? = nil,
        title: String,
        perform: () async throws -> T
    ) async rethrows -> T {
        let id = start(id: id, title: title)

        do {
            let result = try await perform()
            finish(id: id, status: .ok)
            return result
        } catch let error as CancellationError {
            finish(id: id, status: .cancelled)
            throw error
        } catch {
            finish(id: id, status: .error, error: error)
            throw error
        }
    }

    func log<T>(id: String? = nil, title: String, perform: () throws -> T) rethrows -> T {
        let id = start(id: id, title: title)

        do {
            let result = try perform()
            finish(id: id, status: .ok)
            return result
        } catch let error as CancellationError {
            finish(id: id, status: .cancelled)
            throw error
        } catch {
            finish(id: id, status: .error, error: error)
            throw error
        }
    }
}
