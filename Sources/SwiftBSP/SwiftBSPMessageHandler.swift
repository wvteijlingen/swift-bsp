import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import System
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
    private let projectFilePath: FilePath
    private let projectDirectoryPath: FilePath
    private let config: BuildServerConfig
    private let connection: JSONRPCConnection
    private let taskReporter: TaskReporter

    init(
        projectFilePath: FilePath,
        config: BuildServerConfig,
        messageMirrorFile: FileHandle?,
        onExit: @escaping (_ code: Int32) -> Void
    ) {
        self.projectFilePath = projectFilePath
        self.projectDirectoryPath = projectFilePath.removingLastComponent()
        self.config = config
        self.onExit = onExit
        self.connection = JSONRPCConnection(
            name: "swift-bsp",
            protocol: .bspProtocol,
            receiveFD: FileHandle.standardInput,
            sendFD: FileHandle.standardOutput,
            receiveMirrorFile: messageMirrorFile,
            sendMirrorFile: messageMirrorFile
        )

        self.taskReporter = TaskReporter(connection: self.connection)
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
        let notificationType = "\(notification.self)"

        Log.default.debug("[Receive] Notification - \(notificationType, privacy: .public)")

        Task {
            switch notification {
            case _ as CancelRequestNotification:
                break
            case _ as OnBuildExitNotification:
                onExit(state == .shutdown ? 0 : 1)
            case _ as OnBuildInitializedNotification:
                state = .running
            case let notification as OnWatchedFilesDidChangeNotification:
                try await handleOnWatchedFilesDidChange(notification: notification)
            // case _ as OnBuildLogMessageNotification:
            // case _ as OnBuildTargetDidChangeNotification:
            // case _ as FileOptionsChangedNotification:
            // case _ as TaskFinishNotification:
            // case _ as TaskProgressNotification:
            // case _ as TaskStartNotification:
            default:
                Log.default.error("Unhandled notification type '\(notificationType, privacy: .public)'")
            }
        }
    }

    func handle<Request>(
        request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) async where Request: RequestType {
        let requestType = "\(request.self)"
        Log.default.debug("[Receive] Request '\(id, privacy: .public)': \(requestType, privacy: .public)")

        let requestAndReply = RequestAndReply(request) { response in
            switch response {
            case .success(let message):
                let messageType = String(describing: type(of: message))
                Log.default.debug("[Send] Success response '\(id, privacy: .public)': \(messageType, privacy: .public)")
            case .failure:
                Log.default.error("[Send] Failure response '\(id, privacy: .public)'")
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

        guard fileURL.path(percentEncoded: false) == projectDirectoryPath.string else {
            throw ResponseError.invalidParams(
                "Expected rootUri to be '\(projectDirectoryPath)', actually is '\(fileURL.path(percentEncoded: false))'"
            )
        }

        let bsp = try await SwiftBSP(
            projectFilePath: projectFilePath,
            config: config,
            taskReporter: taskReporter
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

        let filePath = FilePath(fileURL.path(percentEncoded: false))

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

        let needsReload = notification.changes.contains { change in
            guard let filePath = change.uri.fileURL?.path(percentEncoded: false) else { return false }

            return change.type == .created ||
                change.type == .deleted ||
                filePath == projectFilePath.string ||
                filePath == projectDirectoryPath.appending("buildServer.json").string
        }

        if needsReload {
            try await bsp.loadProject()
            connection.send(OnBuildTargetDidChangeNotification(changes: nil))
        }
    }
}
