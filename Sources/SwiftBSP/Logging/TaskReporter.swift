import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import OSLog

public struct TaskReporter: Sendable {
    private let connection: (any Connection)?

    public init(connection: (any Connection)?) {
        self.connection = connection
    }

    nonisolated(nonsending) public func log<T>(
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

    public func log<T>(
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
            sendFinish(taskId: id, status: .cancelled)
            throw error
        } catch {
            sendFinish(taskId: id, status: .error)
            throw error
        }
    }

    private func sendStart(taskId: TaskId, message: String) {
        let notification = TaskStartNotification(
            taskId: taskId,
            eventTime: Date(),
            message: "Swift BSP: \(message)",
            dataKind: nil,
            data: .dictionary(["workDoneProgressTitle": .string(message)])
        )

        connection?.send(notification)
    }

    private func sendFinish(taskId: TaskId, status: StatusCode, message: String? = nil) {
        let notification = TaskFinishNotification(
            taskId: taskId,
            eventTime: Date(),
            message: message,
            status: status
        )

        connection?.send(notification)
    }
}
