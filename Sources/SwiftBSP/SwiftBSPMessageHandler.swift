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

final actor SwiftBSPMessageHandler: QueueBasedMessageHandler {
    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "BSPMessageHandler",
        createLoggingScope: false
    )

    public let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()

    private var state = State.waitingForInitializeRequest
    private var bsp: SwiftBSP?
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
            name: "SwiftBSP",
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
                try await handleOnWatchedFilesDidChange(notification: notification)
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
                self.logger.error("[Send] \(id) - \(response)")
            }

            reply(response)
        }

        if !(requestAndReply.params is InitializeBuildRequest) {
            let state = self.state
            guard state == .running else {
                await requestAndReply.reply {
                    throw ResponseError.requestFailed("Request '\(String(describing: type(of: requestAndReply.params)))' received while the build server is '\(state)'")
                }
                return
            }
        }

        switch requestAndReply {
        case let req as RequestAndReply<BuildShutdownRequest>:
            await req.reply {
                try await handleBuildShutdown(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetPrepareRequest>:
            await req.reply {
                try await handleBuildTargetPrepare(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetSourcesRequest>:
            await req.reply {
                try await handleBuildTargetSources(request: req.params)
            }

        case let req as RequestAndReply<InitializeBuildRequest>:
            await req.reply {
                try await handle(request: req.params)
            }

        case let req as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
            await req.reply {
                try await handleTextDocumentSourceKitOptions(request: req.params)
            }

        case let req as RequestAndReply<WorkspaceBuildTargetsRequest>:
            await req.reply {
                try await handleWorkspaceBuildTargets(request: req.params)
            }

        case let req as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
            await req.reply {
                try await handleWorkspaceWaitForBuildSystemUpdates(request: req.params)
            }

        default:
            reply(.failure(.requestNotImplemented(Request.self)))
        }
    }
}

// MARK: - Request Handlers

extension SwiftBSPMessageHandler {
    private func handle(request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        guard state == .waitingForInitializeRequest else {
            throw BuildServerError.projectAlreadyInitialized
        }

        guard let fileURL = request.rootUri.fileURL else {
            throw ResponseError.invalidParams("InitializeBuildRequest received with invalid rootUri")
        }

        guard fileURL.path(percentEncoded: false) == projectFilePath.parentDirectory.pathString else {
            throw ResponseError.invalidParams(
                "Expected rootUri to be '\(projectFilePath.parentDirectory.pathString)', actually is '\(fileURL.path(percentEncoded: false))'"
            )
        }

        let bsp = try await SwiftBSP(
            projectFilePath: projectFilePath,
            taskLogger: taskLogger,
            logger: logger
        )

        self.bsp = bsp
        state = .waitingForInitializedNotification
        return await bsp.initialize()
    }

    private func handleBuildShutdown(request: BuildShutdownRequest) async throws -> VoidResponse {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        try await bsp.closeSession()
        state = .shutdown
        return VoidResponse()
    }

    private func handleBuildTargetSources(
        request: BuildTargetSourcesRequest
    ) async throws -> BuildTargetSourcesResponse {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        let sourceItems = try await bsp.loadBuildSources(targetIdentifiers: request.targets)
        return BuildTargetSourcesResponse(items: sourceItems)
    }

    private func handleWorkspaceBuildTargets(
        request: WorkspaceBuildTargetsRequest
    ) async throws -> WorkspaceBuildTargetsResponse {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        let buildTargets = try await bsp.loadBuildTargets()

        return WorkspaceBuildTargetsResponse(targets: buildTargets)
    }

    private func handleBuildTargetPrepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        try await bsp.prepareTargets(targets: request.targets)

        return VoidResponse()
    }

    private func handleTextDocumentSourceKitOptions(
        request: TextDocumentSourceKitOptionsRequest
    ) async throws -> TextDocumentSourceKitOptionsResponse {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        guard let fileURL = request.textDocument.uri.fileURL else {
            throw BuildServerError.invalidFileURI(request.textDocument.uri)
        }

        let filePath = try AbsolutePath(validating: fileURL.path(percentEncoded: false))

        let arguments = try await bsp.loadCompilerArguments(file: filePath, targetIdentifier: request.target)
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
    }

    private func handleWorkspaceWaitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest
    ) async throws -> VoidResponse {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        await bsp.waitForUpdates()

        return VoidResponse()
    }
}

// MARK: - Notification Handlers

extension SwiftBSPMessageHandler {
    func handleOnWatchedFilesDidChange(notification: OnWatchedFilesDidChangeNotification) async throws {
        guard let bsp, state == .running else { throw BuildServerError.projectNotInitialized }

        for change in notification.changes {
            if change.uri.fileURL?.path(percentEncoded: false) == projectFilePath.pathString {
                try await bsp.loadProject()
            }
        }
    }
}
