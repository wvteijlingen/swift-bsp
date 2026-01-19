import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import Path
import ToolsProtocolsSwiftExtensions

private enum State {
    case waitingForInitializeRequest
    case waitingForInitializedNotification
    case running
    case shutdown
}

final actor BuildServer: QueueBasedMessageHandler {
    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "BSPMessageHandler",
        createLoggingScope: false
    )

    public let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()

    private var state = State.waitingForInitializeRequest
    private var xcodeProject: XcodeProject?
    private let onExit: (_ code: Int32) -> Void
    private let projectFilePath: AbsolutePath
    private let connection: JSONRPCConnection
    private let logger: Logger
    private let taskLogger: TaskLogger

    init(projectFilePath: AbsolutePath, logger: Logger, onExit: @escaping (_ code: Int32) -> Void) {
        self.projectFilePath = projectFilePath
        self.logger = logger
        self.onExit = onExit
        self.connection = JSONRPCConnection(
            name: "XcodeBSP",
            protocol: .bspProtocol,
            inFD: FileHandle.standardInput,
            outFD: FileHandle.standardOutput,
            inputMirrorFile: nil,
            outputMirrorFile: nil
        )

        self.taskLogger = TaskLogger(connection: self.connection, logger: logger)
    }

    package func start() {
        connection.start(
            receiveHandler: self,
            closeHandler: {
                //
            }
        )
    }

    func handle(notification: some NotificationType) {
        logger.debug("[Receive] Notification - \(notification)")

        Task {
            switch notification {
            case _ as CancelRequestNotification:
                break
            case _ as OnBuildExitNotification:
                onExit(state == .shutdown ? 0 : 1)
            case _ as OnBuildInitializedNotification:
                state = .running
            // case _ as OnBuildLogMessageNotification:
            //     break
            // case _ as OnBuildTargetDidChangeNotification:
            //     break
            case let notification as OnWatchedFilesDidChangeNotification:
                try await handle(notification: notification)
            // case _ as FileOptionsChangedNotification:
            //     break
            // case _ as TaskFinishNotification:
            //     break
            // case _ as TaskProgressNotification:
            //     break
            // case _ as TaskStartNotification:
            //     break
            default:
                logger.error("Unhandled notification type '\(notification.self)'")
            }
        }
    }

    func handle<Request>(
        request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) async where Request: RequestType {
        logger.debug("[Receive] Request \(id) - \(request)")

        let requestAndReply = RequestAndReply(request) { response in
            switch response {
            case .success(let message):
                let messageType = String(describing: type(of: message))
                let jsonData = try! JSONEncoder(outputFormatting: [.prettyPrinted, .sortedKeys]).encode(message)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "?"
                self.logger.debug("[Send] \(id) \(messageType)- \(jsonString)")
            case .failure:
                self.logger.debug("[Send] \(id) - \(response)")
            }

            reply(response)
        }

        if !(requestAndReply.params is InitializeBuildRequest) {
            let state = self.state
            guard state == .running else {
                await requestAndReply.reply {
                    throw ResponseError.unknown("Request received while the build server is \(state)")
                }
                return
            }
        }

        switch requestAndReply {
        case let req as RequestAndReply<BuildShutdownRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetPrepareRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetSourcesRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<InitializeBuildRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<WorkspaceBuildTargetsRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        default:
            reply(.failure(.requestNotImplemented(Request.self)))
        }
    }
}

// MARK: - Request Handlers

extension BuildServer {
    private func handle(request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        guard state == .waitingForInitializeRequest else {
            throw ResponseError.unknown("InitializeBuildRequest received while the build server is \(state)")
        }

        guard let fileURL = request.rootUri.fileURL else {
            throw ResponseError.unknown("InitializeBuildRequest received with invalid rootUri")
        }

        guard fileURL.path(percentEncoded: false) == projectFilePath.parentDirectory.pathString else {
            throw ResponseError.unknown(
                "Expected rootUri to be '\(projectFilePath.parentDirectory.pathString)', actually is '\(fileURL.path(percentEncoded: false))'"
            )
        }

        let xcodeProject = try await XcodeProject(
            projectFilePath: projectFilePath,
            taskLogger: taskLogger,
            logger: logger
        )

        self.xcodeProject = xcodeProject
        state = .waitingForInitializedNotification
        return await xcodeProject.initialize()
    }

    private func handle(request: BuildShutdownRequest) async throws -> VoidResponse {
        try await xcodeProject?.closeSession()
        state = .shutdown
        return VoidResponse()
    }

    private func handle(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        guard state == .running else {
            throw ResponseError.unknown(
                "BuildTargetSourcesRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw BuildServerError.projectNotInitialized
        }

        let sourceItems = try await xcodeProject.loadBuildSources(targetIdentifiers: request.targets)
        return BuildTargetSourcesResponse(items: sourceItems)
    }

    private func handle(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse {
        guard state == .running else {
            throw ResponseError.unknown(
                "WorkspaceBuildTargetsRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw BuildServerError.projectNotInitialized
        }

        let buildTargets = try await xcodeProject.loadBuildTargets()

        return WorkspaceBuildTargetsResponse(targets: buildTargets)
    }

    private func handle(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
        guard state == .running else {
            throw ResponseError.unknown(
                "WorkspaceBuildTargetsRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw BuildServerError.projectNotInitialized
        }

        try await xcodeProject.prepareTargets(targets: request.targets)

        return VoidResponse()
    }

    private func handle(
        request: TextDocumentSourceKitOptionsRequest
    ) async throws -> TextDocumentSourceKitOptionsResponse {
        guard state == .running else {
            throw ResponseError.unknown("WorkspaceBuildTargetsRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw BuildServerError.projectNotInitialized
        }

        guard let fileURL = request.textDocument.uri.fileURL else {
            throw BuildServerError.invalidFileURI(request.textDocument.uri)
        }

        let filePath = try AbsolutePath(validating: fileURL.path(percentEncoded: false))

        let arguments = try await xcodeProject.loadCompilerArguments(file: filePath, targetIdentifier: request.target)
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
    }

    private func handle(
        request: WorkspaceWaitForBuildSystemUpdatesRequest
    ) async throws -> VoidResponse {
        guard let xcodeProject else {
            throw BuildServerError.projectNotInitialized
        }

        await xcodeProject.waitForUpdates()

        return VoidResponse()
    }
}

// MARK: - Notification Handlers

extension BuildServer {
    func handle(notification: OnWatchedFilesDidChangeNotification) async throws {
        guard state == .running else {
            throw ResponseError.unknown(
                "OnWatchedFilesDidChangeNotification received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw BuildServerError.projectNotInitialized
        }

        for change in notification.changes {
            if change.uri.fileURL?.path(percentEncoded: false) == projectFilePath.pathString {
                try await xcodeProject.loadProject()
            }
        }
    }
}
