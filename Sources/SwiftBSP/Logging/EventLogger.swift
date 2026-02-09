import BuildServerProtocol
import SwiftBuild

struct EventLogger {
    let taskReporter: TaskReporter
    private let log = Log.buildSystem

    func log(events: AsyncStream<SwiftBuildMessage>) {
        Task {
            for try await event in events {
                log(event: event)
            }
        }
    }

    func log(event: SwiftBuildMessage) {
        switch event {
        case .planningOperationStarted(let info):
            _ = taskReporter.start(id: info.planningOperationID, title: "[swift-build] Planning build")

        case .planningOperationCompleted(let info):
            taskReporter.finish(id: info.planningOperationID, status: .ok)

        case .taskStarted(let info):
            _ = taskReporter.start(id: String(info.taskID), title: "[swift-build] " + info.executionDescription)

        case .taskComplete(let info):
            switch info.result {

            case .success:
                taskReporter.finish(id: String(info.taskID), status: .ok)

            case .failed:
                taskReporter.finish(id: String(info.taskID), status: .error)

            case .cancelled:
                taskReporter.finish(id: String(info.taskID), status: .cancelled)
            }

        case .taskDiagnostic(let info):
            log.debug("Task \(info.taskID, privacy: .public): \(info.message, privacy: .public)")

        case .buildStarted(let info):
            let baseDirectory = info.baseDirectory.pathString
            let derivedData = info.derivedDataPath?.pathString ?? "-"
            log.debug("Build started: baseDirectory='\(baseDirectory, privacy: .public)', derivedData='\(derivedData, privacy: .public)'")

        case .buildDiagnostic(let info):
            log.info("Build diagnostic: \(info.message, privacy: .public)")

        case .buildCompleted(let info):
            switch info.result {
            case .ok: log.info("########## Build complete ##########")
            case .failed: log.error("########## Build failed ##########")
            case .cancelled: log.warning("########## Build cancelled ##########")
            case .aborted: log.warning("########## Build aborted ##########")
            }

        case .preparationComplete(_):
            log.debug("Build preparation complete")

        case .didUpdateProgress(let info):
            if info.showInLog {
                log.debug("Progress \(info.targetName ?? "-"): \(info.message) \(info.percentComplete)%")
            }

        case .targetDiagnostic(let info):
            log.debug("Target \(info.targetID, privacy: .public): \(info.message, privacy: .public)")

        case .diagnostic(let info):
            log.debug("Diagnostic: \(info.message, privacy: .public)")

        case .backtraceFrame:
            log.debug(".backtraceFrame")

        case .reportPathMap:
            log.debug(".reportPathMap")

        case .reportBuildDescription(let info):
            log.debug("Build description reported: \(info.buildDescriptionID, privacy: .public)")

        case .preparedForIndex(let info):
            log.debug("Target \(info.targetGUID, privacy: .public): Prepared for index")

        case .buildOutput(let info):
            log.debug("Build output: \(info.data, privacy: .public)")

        case .targetStarted(let info):
            log.debug("Target \(info.targetID, privacy: .public): Started \(info.targetName, privacy: .public) - \(info.targetGUID, privacy: .public)")

        case .targetComplete(let info):
            log.debug("Target \(info.targetID, privacy: .public): Complete")

        case .targetOutput(let info):
            log.debug("Target \(info.targetID, privacy: .public): \(info.data, privacy: .public)")

        case .targetUpToDate(let info):
            log.debug("Target \(info.guid, privacy: .public): Up to date")

        case .taskUpToDate(let info):
            log.debug("Task up to date: \(info.taskSignature, privacy: .public)")

        case .taskOutput(let info):
            log.debug("Task \(info.taskID, privacy: .public): \(info.data, privacy: .public)")

        case .output(let info):
            if let string = String(data: info.data, encoding: .utf8) {
                log.info("\(string, privacy: .public)")
            }
        }
    }
}
