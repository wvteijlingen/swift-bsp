import BuildServerProtocol
import SwiftBuild

struct EventLogger {
    let logger: Logger
    let taskLogger: TaskLogger

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
            _ = taskLogger.start(id: info.planningOperationID, title: "[swift-build] Planning build")
        case .planningOperationCompleted(let info):
            taskLogger.finish(id: info.planningOperationID, status: .ok)
        case .buildStarted(let info):
            logger.debug(
                "Build started: baseDirectory='\(info.baseDirectory.pathString)', derivedDataPath='\(info.derivedDataPath, default: "nil")'"
            )
        case .buildDiagnostic(let info):
            logger.info("Build diagnostic: \(info.message)")
        case .buildCompleted(let info):
            switch info.result {
            case .ok:
                logger.info("########## Build complete ##########")
            case .failed:
                logger.error("########## Build failed ##########")
            case .cancelled:
                logger.warning("########## Build cancelled ##########")
            case .aborted:
                logger.warning("########## Build aborted ##########")
            }
        case .preparationComplete(_):
            logger.debug("Build preparation complete")
        case .didUpdateProgress(let info):
            logger.debug("Progress: \(info.message) \(info.percentComplete)%")
        case .taskStarted(let info):
            _ = taskLogger.start(id: String(info.taskID), title: "[swift-build] " + info.executionDescription)
        case .taskDiagnostic(let info):
            logger.debug("Task \(info.taskID): \(info.message)")
        case .taskComplete(let info):
            switch info.result {
            case .success:
                taskLogger.finish(id: String(info.taskID), status: .ok)
            case .failed:
                taskLogger.finish(id: String(info.taskID), status: .error)
            case .cancelled:
                taskLogger.finish(id: String(info.taskID), status: .cancelled)
            }
        case .targetDiagnostic(let info):
            logger.debug("Target \(info.targetID): \(info.message)")
        case .diagnostic(let info):
            logger.debug("Diagnostic: \(info.message)")
        case .backtraceFrame:
            logger.debug(".backtraceFrame")
        case .reportPathMap:
            logger.debug(".reportPathMap")
        case .reportBuildDescription(let info):
            logger.debug("Build description reported: \(info.buildDescriptionID)")
        case .preparedForIndex(let info):
            logger.debug("Target \(info.targetGUID): Prepared for index")
        case .buildOutput(let info):
            logger.debug("Build output: \(info.data)")
        case .targetStarted(let info):
            logger.debug(
                "Target \(info.targetID): Started \(info.targetName) - \(info.targetGUID)"
            )
        case .targetComplete(let info):
            logger.debug("Target \(info.targetID): Complete")
        case .targetOutput(let info):
            logger.debug("Target \(info.targetID): \(info.data)")
        case .targetUpToDate(let info):
            logger.debug("Target \(info.guid): Up to date")
        case .taskUpToDate(let info):
            logger.debug("Task up to date: \(info.taskSignature)")
        case .taskOutput(let info):
            logger.debug("Task \(info.taskID): \(info.data)")
        case .output(let info):
            if let string = String(data: info.data, encoding: .utf8) {
                logger.info(string)
            }
        }
    }
}
