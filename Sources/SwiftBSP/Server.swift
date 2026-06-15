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

final actor Server: QueueBasedMessageHandler {
    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "SwiftBSPMessageHandler",
        createLoggingScope: false
    )

    public let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()

    private var state = State.waitingForInitializeRequest
    private let onExit: (_ code: Int32) -> Void
    private let containerPath: FilePath
    private let containerDirectoryPath: FilePath
    private let connection: JSONRPCConnection
    private var taskReporter = TaskReporter(connection: nil)

    private var swiftBuildAdapter: SwiftBuildAdapter
    private var xcodeAdapter: XcodeAdapter

    init(
        containerPath: FilePath,
        scratchPath: FilePath,
        config: BuildServerConfig,
        messageMirrorFile: FileHandle?,
        onExit: @escaping (_ code: Int32) -> Void
    ) async throws {
        self.containerPath = containerPath
        self.containerDirectoryPath = containerPath.removingLastComponent()
        self.onExit = onExit
        self.connection = JSONRPCConnection(
            name: "swift-bsp",
            protocol: .bspProtocolExtended,
            receiveFD: FileHandle.standardInput,
            sendFD: FileHandle.standardOutput,
            receiveMirrorFile: messageMirrorFile,
            sendMirrorFile: messageMirrorFile
        )

        self.swiftBuildAdapter = try await SwiftBuildAdapter(
            containerPath: containerPath,
            scratchPath: scratchPath,
            config: config,
            taskReporter: TaskReporter(connection: nil)
        )

        self.xcodeAdapter = try XcodeAdapter(containerPath: containerPath)
    }

    package func start() async {
        connection.start(
            receiveHandler: self,
            closeHandler: {
                Log.default.info("Connection closed")
            }
        )

        taskReporter = TaskReporter(connection: connection)

        await swiftBuildAdapter.setTaskReporter(TaskReporter(connection: connection))
        await xcodeAdapter.setTaskReporter(TaskReporter(connection: connection))
        await xcodeAdapter.setDiagnosticsReporter(DiagnosticsReporter(connection: connection))
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
                    throw ResponseError.requestFailed(
                        "Request '\(String(describing: type(of: requestAndReply.params)))' received while the build server is '\(state)'"
                    )
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

        // Extended requests

        case let req as RequestAndReply<BuildTargetDestinationsRequest>:
            await req.reply {
                try await handleBuildTargetDestinations(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetCompileRequest>:
            await req.reply {
                try await handleBuildTargetCompile(request: req.params)
            }

        default:
            reply(.failure(.requestNotImplemented(Request.self)))
        }
    }
}

// MARK: - Helpers

extension Server {
    private func assertRunning() throws {
        guard state == .running else { throw BuildServerError.projectNotInitialized }
    }
}

// MARK: - Default Requests

extension Server {
    private func handle(request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        guard state == .waitingForInitializeRequest else {
            throw BuildServerError.projectAlreadyInitialized
        }

        guard let rootPath = request.rootUri.fileURL?.path(percentEncoded: false) else {
            throw ResponseError.invalidParams("InitializeBuildRequest received with invalid rootUri")
        }

        guard rootPath == containerDirectoryPath.string else {
            throw ResponseError.invalidParams(
                "Expected rootUri to be '\(containerDirectoryPath)', actually is '\(rootPath)'"
            )
        }

        state = .waitingForInitializedNotification

        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]

        _ = await xcodeAdapter.initialize()
        let data = await swiftBuildAdapter.initialize()

        return InitializeBuildResponse(
            displayName: "swift-bsp",
            version: "0.0.2",
            bspVersion: "2.2.0",
            capabilities:
                BuildServerCapabilities(
                    compileProvider: CompileProvider(languageIds: languageIds),
                    testProvider: TestProvider(languageIds: languageIds),
                    runProvider: RunProvider(languageIds: languageIds),
                    debugProvider: nil,
                    inverseSourcesProvider: false,
                    dependencySourcesProvider: false,
                    resourcesProvider: false,
                    outputPathsProvider: false,
                    buildTargetChangedProvider: false,
                    jvmRunEnvironmentProvider: false,
                    jvmTestEnvironmentProvider: false,
                    cargoFeaturesProvider: false,
                    canReload: true,
                    jvmCompileClasspathProvider: false
                ),
            dataKind: .sourceKit,
            data: data
        )
    }

    private func handleBuildShutdown(request: BuildShutdownRequest) async throws -> VoidResponse {
        try assertRunning()

        try await swiftBuildAdapter.closeSession()

        state = .shutdown
        return VoidResponse()
    }

    private func handleBuildTargetSources(
        request: BuildTargetSourcesRequest
    ) async throws -> BuildTargetSourcesResponse {
        try assertRunning()

        let swiftBuildTargets = try request.targets.compactMap { targetIdentifier in
            try targetIdentifier.swiftBuildTarget
        }

        let sources = try await swiftBuildAdapter.loadBuildSources(targetIdentifiers: swiftBuildTargets)

        return BuildTargetSourcesResponse(items: sources)
    }

    private func handleWorkspaceBuildTargets(
        request: WorkspaceBuildTargetsRequest
    ) async throws -> WorkspaceBuildTargetsResponse {
        try assertRunning()

//        let swiftBuildTargets = try await swiftBuildAdapter.loadBuildTargets()
        let xcodeTargets = try await xcodeAdapter.loadBuildTargets()

        return WorkspaceBuildTargetsResponse(targets: xcodeTargets)
    }

    private func handleWorkspaceWaitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest
    ) async throws -> VoidResponse {
        try assertRunning()

        await swiftBuildAdapter.waitForUpdates()

        return VoidResponse()
    }
}

// MARK: - Default Notifications

extension Server {
    func handleOnWatchedFilesDidChange(notification: OnWatchedFilesDidChangeNotification) async throws {
        try assertRunning()

        let needsReload = notification.changes.contains { change in
            guard let filePath = change.uri.fileURL?.path(percentEncoded: false) else { return false }

            return change.type == .created ||
                change.type == .deleted ||
                filePath == containerPath.string ||
                filePath == containerDirectoryPath.appending("buildServer.json").string
        }

        if needsReload {
            try await swiftBuildAdapter.loadProject()
            connection.send(OnBuildTargetDidChangeNotification(changes: nil))
        }
    }
}

// MARK: - Sourcekit Extension

extension Server {
    private func handleBuildTargetPrepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
        try assertRunning()

        let swiftBuildTargets = try request.targets.compactMap { targetIdentifier in
            try targetIdentifier.swiftBuildTarget
        }

        try await swiftBuildAdapter.prepareTargets(targets: swiftBuildTargets)

        return VoidResponse()
    }

    private func handleTextDocumentSourceKitOptions(
        request: TextDocumentSourceKitOptionsRequest
    ) async throws -> TextDocumentSourceKitOptionsResponse {
        try assertRunning()

        guard let fileURL = request.textDocument.uri.fileURL else {
            throw BuildServerError.invalidFileURI(request.textDocument.uri)
        }

        let filePath = FilePath(fileURL.path(percentEncoded: false))

        guard let target = try request.target.swiftBuildTarget else {
            throw BuildServerError.generic("Sourcekit options not available for target: \(request.target.uri)")
        }

        let arguments = try await swiftBuildAdapter.loadCompilerArguments(file: filePath, targetIdentifier: target)

        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
    }
}

// MARK: - Extension Requests

extension Server {
    func handleBuildTargetDestinations(
        request: BuildTargetDestinationsRequest
    ) async throws -> BuildTargetDestinationsRequest.Response {
        try assertRunning()

        guard let target = try request.target.xcodeTarget else {
            throw BuildServerError.generic("Build target destinations not available for target: \(request.target.uri)")
        }

        let destinations = try await xcodeAdapter.loadBuildTargetDestinations(targetIdentifier: target)

        return BuildTargetDestinationsResponse(destinations: destinations)
    }

    func handleBuildTargetCompile(
        request: BuildTargetCompileRequest
    ) async throws -> BuildTargetCompileRequest.Response {
        try assertRunning()

        let xcodeTargets = try request.targets.compactMap { targetIdentifier in
            try targetIdentifier.xcodeTarget
        }

        if xcodeTargets.count > 1 {
            throw BuildServerError.generic("Cannot compile more than one target at a time")
        }

        guard let target = xcodeTargets.first else {
            throw BuildServerError.generic("No valid compile targets specified")
        }

        return try await xcodeAdapter.compile(targetIdentifier: target, destination: request.destination)
    }
}
