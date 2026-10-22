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
        data: LSPAnyCodable? = nil,
        operation: (TaskId) async throws -> T
    ) async rethrows -> T {
        let uuid = UUID().uuidString
        let parents = parent.map { [$0.id] }
        let id = TaskId(id: uuid, parents: parents)

        sendStart(taskId: id, message: message, data: data)

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
        data: LSPAnyCodable? = nil,
        operation: (TaskId) throws -> T
    ) rethrows -> T {
        let uuid = UUID().uuidString
        let parents = parent.map { [$0.id] }
        let id = TaskId(id: uuid, parents: parents)

        sendStart(taskId: id, message: message, data: data)

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

    private func sendStart(
        taskId: TaskId,
        message: String,
        data: LSPAnyCodable? = nil
    ) {
        let dataKind: TaskStartDataKind? = switch data {
        case is CompileTaskData: .compileTask
        case is TestStartData: .testTask
        case is TestTaskData: .testStart
        default: nil
        }

        let notificationData: LSPAny = {
            guard let lspData = data?.encodeToLSPAny() else {
                // There is no data, include default data with a `workDoneProgressTitle`` for SourceKit-LSP
                return .dictionary(["workDoneProgressTitle": .string(message)])
            }

            guard case let .dictionary(dictionary) = lspData, dictionary["workDoneProgressTitle"] == nil else {
                // Data is not a dictionary or already contains a `workDoneProgressTitle`. Return the data as is.
                return lspData
            }

            // Data is a dictionary without a `workDoneProgressTitle.
            // Add `workDoneProgressTitle` to the dictionary and return it.
            var mutableDictionary = dictionary
            mutableDictionary["workDoneProgressTitle"] = .string(message)
            return .dictionary(mutableDictionary)
        }()

        let title = "Swift BSP: \(message)"
        let notification = TaskStartNotification(
            taskId: taskId,
            eventTime: Date(),
            message: title,
            dataKind: dataKind,
            data: notificationData
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

extension CompileTaskData: @retroactive LSPAnyCodable {
    public init?(fromLSPDictionary dictionary: [String: LSPAny]) { nil }
    public func encodeToLSPAny() -> LSPAny {
        .dictionary([
            "target": .dictionary([
                "uri": .string(target.uri.stringValue)
            ])
        ])
    }
}

extension TestStartData: @retroactive LSPAnyCodable {
    public init?(fromLSPDictionary dictionary: [String: LSPAny]) { nil }
    public func encodeToLSPAny() -> LSPAny {
        .dictionary([
            "displayName": .string(displayName),
            "location": location?.encodeToLSPAny() ?? .null,
        ])
    }
}

extension TestTaskData: @retroactive LSPAnyCodable {
    public init?(fromLSPDictionary dictionary: [String: LSPAny]) { nil }
    public func encodeToLSPAny() -> LSPAny {
        .dictionary([
            "target": .dictionary([
                "uri": .string(target.uri.stringValue)
            ])
        ])
    }
}