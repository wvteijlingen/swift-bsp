import BuildServerProtocol
import OSLog
import SwiftBuild

struct EventReporter {
    let taskReporter: TaskReporter
    let logReporter: LogReporter
    private let log = Log.buildSystem

    func log(events: AsyncStream<SwiftBuildMessage>) {
        Task {
            for await event in events {
                log(event: event)
            }
        }
    }

    func log(event: SwiftBuildMessage) {
        switch event {
        case .output(let info):
            if let string = String(data: info.data, encoding: .utf8) {
                logReporter.log(message: string, type: .info)
            }

        default:
            break

        // case .planningOperationStarted(let info):
        // case .planningOperationCompleted(let info):
        // case .taskStarted(let info):
        // case .taskComplete(let info):
        // case .taskDiagnostic(let info):
        // case .buildStarted(let info):
        // case .buildDiagnostic(let info):
        // case .buildCompleted(let info):
        // case .preparationComplete(_):
        // case .didUpdateProgress(let info):
        // case .targetDiagnostic(let info):
        // case .diagnostic(let info):
        // case .backtraceFrame:
        // case .reportPathMap:
        // case .reportBuildDescription(let info):
        // case .preparedForIndex(let info):
        // case .buildOutput(let info):
        // case .targetStarted(let info):
        // case .targetComplete(let info):
        // case .targetOutput(let info):
        // case .targetUpToDate(let info):
        // case .taskUpToDate(let info):
        // case .taskOutput(let info):
        }
    }
}
