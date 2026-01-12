import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport

struct TaskLogger: Sendable {
    private let connection: any Connection
    private let logger: Logger

    init(connection: any Connection, logger: Logger) {
        self.connection = connection
        self.logger = logger
    }

    func start(title: String) -> TaskId {
        let id = generateTaskId()
        startTask(id: id, title: title)
        return id
    }

    func finish(id: TaskId, status: StatusCode) {
        finishTask(id: id, status: status)
    }

    func start(id: LosslessStringConvertible, title: String) {
        let id = TaskId(id: String(id))
        startTask(id: id, title: title)
    }

    func finish(id: LosslessStringConvertible, status: StatusCode) {
        let id = TaskId(id: String(id))
        finishTask(id: id, status: status)
    }

    nonisolated(nonsending) func log<T>(title: String, perform: () async throws -> T) async rethrows -> T {
        let id = generateTaskId()
        startTask(id: id, title: title)

        do {
            let result = try await perform()
            finishTask(id: id, status: .ok)
            return result
        } catch let error as CancellationError {
            finishTask(id: id, status: .cancelled)
            throw error
        } catch {
            finishTask(id: id, status: .error)
            throw error
        }
    }

    func log<T>(title: String, perform: () throws -> T) rethrows -> T {
        let id = generateTaskId()
        startTask(id: id, title: title)

        do {
            let result = try perform()
            finishTask(id: id, status: .ok)
            return result
        } catch let error as CancellationError {
            finishTask(id: id, status: .cancelled)
            throw error
        } catch {
            finishTask(id: id, status: .error, error: error)
            throw error
        }
    }

    private func generateTaskId() -> TaskId {
        let uuid = UUID().uuidString
        return TaskId(id: uuid)
    }

    private func startTask(id: TaskId, title: String) {
        let notification = TaskStartNotification(taskId: id, data: WorkDoneProgressTask(title: title).encodeToLSPAny())
        connection.send(notification)
        logger.info("Start task \(id.id): \(title)")
    }

    private func finishTask(id: TaskId, status: StatusCode, error: Error? = nil) {
        let message = error.map { "Error: \($0)" }
        let notification = TaskFinishNotification(taskId: id, message: message, status: status)
        connection.send(notification)
        logger.info("Finish task \(id.id): \(status), \(message, default: "no message")")
    }
}
