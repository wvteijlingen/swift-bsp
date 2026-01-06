import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport

struct TaskLogger {
    typealias ProgressReporter = @Sendable (_ message: String?, _ progress: Int?, _ total: Int?) -> Void

    private let connection: any Connection
    // private var taskNumber = 0

    init(connection: any Connection) {
        self.connection = connection
    }

    func start(title: String) -> TaskId {
        let id = generateTaskId()
        startTask(id: id, title: title)
        return id
    }

    func finish(id: TaskId) {
        finishTask(id: id, status: .ok)
    }

    nonisolated(nonsending) func log<T>(
        title: String,
        perform: (ProgressReporter) async throws -> T
    ) async rethrows -> T {
        let id = generateTaskId()
        startTask(id: id, title: title)

        let progressLogger: ProgressReporter = { message, progress, total in
            Task {
                self.reportProgress(id: id, message: message, progress: progress, total: total)
            }
        }

        do {
            let result = try await perform(progressLogger)
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

    func log<T>(
        title: String,
        perform: (ProgressReporter) throws -> T
    ) rethrows -> T {
        let id = generateTaskId()
        startTask(id: id, title: title)

        let progressLogger: ProgressReporter = { message, progress, total in
            Task {
                self.reportProgress(id: id, message: message, progress: progress, total: total)
            }
        }

        do {
            let result = try perform(progressLogger)
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

    private func generateTaskId() -> TaskId {
        let uuid = UUID().uuidString
        return TaskId(id: uuid)
    }

    private func startTask(id: TaskId, title: String) {
        let notification = TaskStartNotification(taskId: id, data: WorkDoneProgressTask(title: title).encodeToLSPAny())
        connection.send(notification)
    }

    private func finishTask(id: TaskId, status: StatusCode) {
        Task {
            let notification = TaskFinishNotification(taskId: id, status: status)
            // try? await Task.sleep(for: .seconds(1))
            connection.send(notification)
        }
    }

    private func reportProgress(id: TaskId, message: String?, progress: Int?, total: Int?) {
        // let notification = TaskProgressNotification(taskId: id, message: message, total: total, progress: progress)
        // connection.send(notification)
    }

    // func logTask<T>(_ name: String, _ perform: () async throws -> T) async throws -> T {
    //     let uuid = UUID().uuidString
    //     let taskId = TaskId(id: uuid)

    //     do {
    //         connection.send(
    //             TaskStartNotification(
    //                 taskId: taskId,
    //                 originId: uuid,
    //                 eventTime: Date(),
    //                 message: name,
    //                 dataKind: TaskStartDataKind(rawValue: name),
    //                 data: nil
    //             )
    //         )

    //         logEntry(.info("## Task start: \(name)", .begin(StructuredLogBegin(title: name))))

    //         let result = try await perform()

    //         logEntry(.info("## Task finish: \(name)", .end(StructuredLogEnd())))

    //         connection.send(
    //             TaskFinishNotification(
    //                 taskId: taskId,
    //                 originId: uuid,
    //                 eventTime: Date(),
    //                 message: name,
    //                 status: StatusCode.ok,
    //                 dataKind: TaskFinishDataKind(rawValue: name), data: nil
    //             )
    //         )

    //         return result
    //     } catch let error as CancellationError {
    //         logEntry(.info("## Task cancelled: \(name)", .end(StructuredLogEnd())))

    //         connection.send(
    //             TaskFinishNotification(
    //                 taskId: taskId,
    //                 originId: uuid,
    //                 eventTime: Date(),
    //                 message: "\(name) cancelled",
    //                 status: StatusCode.cancelled,
    //                 dataKind: TaskFinishDataKind(rawValue: name),
    //                 data: nil
    //             )
    //         )

    //         throw error
    //     } catch {
    //         logEntry(.info("## Task errored: \(name)", .end(StructuredLogEnd())))

    //         connection.send(
    //             TaskFinishNotification(
    //                 taskId: taskId,
    //                 originId: uuid,
    //                 eventTime: Date(),
    //                 message: "\(name) failed: \(error)",
    //                 status: StatusCode.error,
    //                 dataKind: TaskFinishDataKind(rawValue: name),
    //                 data: nil
    //             )
    //         )

    //         throw error
    //     }
    // }
}
