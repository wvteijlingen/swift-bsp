import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import OSLog

struct TaskReporter: Sendable {
    private let connection: any Connection

    init(connection: any Connection) {
        self.connection = connection
    }

    nonisolated(nonsending) func log<T>(
        message: String,
        parent: TaskId? = nil,
        operation: (TaskId) async throws -> T
    ) async rethrows -> T {
        let uuid = UUID().uuidString
        let parents = parent.map { [$0.id] }
        let id = TaskId(id: uuid, parents: parents)

        sendStart(taskId: id, message: message)

        do {
            let operationResult = try await operation(id)
            sendFinish(taskId: id, status: .ok)
            return operationResult
        } catch let error as CancellationError {
            sendFinish(taskId: id, status: .cancelled)
            throw error
        } catch {
            sendFinish(taskId: id, status: .error)
            throw error
        }
    }

    func log<T>(
        message: String,
        parent: TaskId? = nil,
        operation: (TaskId) throws -> T
    ) rethrows -> T {
        let uuid = UUID().uuidString
        let parents = parent.map { [$0.id] }
        let id = TaskId(id: uuid, parents: parents)

        sendStart(taskId: id, message: message)

        do {
            let operationResult = try operation(id)
            sendFinish(taskId: id, status: .ok)
            return operationResult
        } catch let error as CancellationError {
            sendFinish(taskId: id, status: .cancelled, message: error.localizedDescription)
            throw error
        } catch {
            sendFinish(taskId: id, status: .error, message: error.localizedDescription)
            throw error
        }
    }

    private func sendStart(taskId: TaskId, message: String) {
        let notification = TaskStartNotification(
            taskId: taskId,
            message: "Swift BSP: \(message)",
            data: WorkDoneProgressTask(title: message).encodeToLSPAny()
        )

        connection.send(notification)
    }

    private func sendFinish(taskId: TaskId, status: StatusCode, message: String? = nil) {
        let notification = TaskFinishNotification(taskId: taskId, message: message, status: status)
        connection.send(notification)
    }
}
