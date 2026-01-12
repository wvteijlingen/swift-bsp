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
            logger.info(
                "Build started: baseDirectory='\(info.baseDirectory)', derivedDataPath='\(info.derivedDataPath, default: "nil")'"
            )
        case .buildDiagnostic(let info):
            logger.info("Build diagnostic: message='\(info.message)'")
        case .buildCompleted(let info):
            switch info.result {
            case .ok:
                logger.info("Build complete")
            case .failed:
                logger.error("Build failed")
            case .cancelled:
                logger.warning("Build cancelled")
            case .aborted:
                logger.warning("Build aborted")
            }
        case .preparationComplete(_):
            logger.info("Build Preparation Complete")
        case .didUpdateProgress(let info):
            logger.info("Progress: \(info.message) \(info.percentComplete)%")
        case .taskStarted(let info):
            _ = taskLogger.start(id: String(info.taskID), title: "[swift-build] " + info.executionDescription)
        case .taskDiagnostic(let info):
            logger.info("Task Diagnostic: targetID='\(info.taskID)' message='\(info.message)'")
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
            logger.info("Target Diagnostic: targetID='\(info.targetID)', message='\(info.message)'")
        case .diagnostic(let info):
            logger.info("Diagnostic: \(info.message)")
        case .backtraceFrame:
            logger.info(".backtraceFrame")
        case .reportPathMap:
            logger.info(".reportPathMap")
        case .reportBuildDescription(let info):
            logger.info(".reportBuildDescription: buildDescriptionID='\(info.buildDescriptionID)'")
        case .preparedForIndex(let info):
            logger.info(".preparedForIndex: targetGUID='\(info.targetGUID)'")
        case .buildOutput(let info):
            logger.info(".buildOutput: data='\(info.data)'")
        case .targetStarted(let info):
            logger.info(
                ".targetStarted: targetName='\(info.targetName)', targetID='\(info.targetID)', targetGUID='\(info.targetGUID)', name='\(info.targetName)'"
            )
        case .targetComplete(let info):
            logger.info(".targetComplete: targetID='\(info.targetID)'")
        case .targetOutput(let info):
            logger.info(".targetOutput: targetID='\(info.targetID)', data=\(info.data)")
        case .targetUpToDate(let info):
            logger.info(".targetUpToDate: guid='\(info.guid)'")
        case .taskUpToDate(let info):
            logger.info(".taskUpToDate: targetID='\(info.targetID, default: "nil")'")
        case .taskOutput(let info):
            logger.info(".taskOutput: id='\(info.taskID)', data='\(info.data)'")
        case .output:
            logger.info(".output")
        }
    }
}
