import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import ToolsProtocolsSwiftExtensions

package class BuildServer {
    private let connection: JSONRPCConnection

    package init() {
        self.connection = JSONRPCConnection(
            name: "XcodeBSP",
            protocol: .bspProtocol,
            inFD: FileHandle.standardInput,
            outFD: FileHandle.standardOutput,
            inputMirrorFile: nil,
            outputMirrorFile: nil
        )
    }

    package func start() {
        connection.start(
            receiveHandler: BSPMessageHandler(connection: connection),
            closeHandler: {
                //
            }
        )
    }
}

enum State {
    case waitingForInitializeRequest
    case waitingForInitializedNotification
    case running
    case shutdown
}

final actor BSPMessageHandler: QueueBasedMessageHandler {
    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "BSPMessageHandler",
        createLoggingScope: false
    )

    public let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()
    private var state = State.waitingForInitializeRequest
    private var xcodeProject: XcodeProject?
    private let connection: any Connection
    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()

    init(connection: JSONRPCConnection) {
        self.connection = connection
    }

    func handle(notification: some NotificationType) {
        logToClient(.info, "[Receive] Notification - \(notification)")

        switch notification {
        case _ as CancelRequestNotification:
            break
        case _ as OnBuildExitNotification:
            _Exit(0)
        case _ as OnBuildInitializedNotification:
            state = .running
        case _ as OnBuildLogMessageNotification:
            break
        case _ as OnBuildTargetDidChangeNotification:
            break
        case _ as OnWatchedFilesDidChangeNotification:
            break
        case _ as FileOptionsChangedNotification:
            break
        case _ as TaskFinishNotification:
            break
        case _ as TaskProgressNotification:
            break
        case _ as TaskStartNotification:
            break
        default:
            break
        }
    }

    func handle<Request>(
        request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) where Request: RequestType {
        logToClient(.info, "[Receive] Request - \(id) - \(request)")

        let requestAndReply = RequestAndReply(request) { response in
            Task {
                await self.logToClient(.info, "[Send] \(response)")
            }
            reply(response)
        }

        Task {
            switch requestAndReply {
            case let req as RequestAndReply<InitializeBuildRequest>:
                await req.reply {
                    try await handle(request: req.params)
                }

            case let req as RequestAndReply<WorkspaceBuildTargetsRequest>:
                await req.reply {
                    try await handle(request: req.params)
                }

            case let req as RequestAndReply<BuildShutdownRequest>:
                await req.reply {
                    try await handle(request: req.params)
                }

            case let req as RequestAndReply<BuildTargetSourcesRequest>:
                await req.reply {
                    try await handle(request: req.params)
                }

            case let req as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
                await req.reply {
                    VoidResponse()
                }

            case let req as RequestAndReply<BuildTargetPrepareRequest>:
                await req.reply {
                    try await handle(request: req.params)
                }

            case let req as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
                await req.reply {
                    try await handle(request: req.params)
                }

            default:
                reply(.failure(.requestNotImplemented(Request.self)))
            }
        }
    }

    private func logToClient(
        _ type: BuildServerProtocol.MessageType,
        _ message: String,
        _ structure: BuildServerProtocol.StructuredLogKind? = nil
    ) {
        logger.log(level: type, message)

        connection.send(
            OnBuildLogMessageNotification(
                type: type,
                task: nil,
                originId: nil,
                message: "[xcodebsp] \(message)",
                structure: structure
            )
        )
    }
}

// MARK: - Request Handlers

extension BSPMessageHandler {
    private func handle(request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        guard state == .waitingForInitializeRequest else {
            throw ResponseError.unknown("InitializeBuildRequest received while the build server is \(state)")
        }

        guard let fileURL = request.rootUri.fileURL else {
            throw ResponseError.unknown("InitializeBuildRequest received with invalid rootUri")
        }

        let rootPath = try AbsolutePath(validating: fileURL.path(percentEncoded: false))

        let xcodeProject = try await XcodeProject(
            projectRoot: rootPath,
            projectFileName: CLI.projectFileName,
            logger: self.logToClient(_:_:_:)
        )

        self.xcodeProject = xcodeProject

        // Task {
        //     do {
        //         try await xcodeProject.buildIndex()
        //     } catch {
        //         // TODO
        //     }
        // }

        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]

        state = .waitingForInitializedNotification

        return await InitializeBuildResponse(
            displayName: "xcode-bsp",
            version: "0.0.1",
            bspVersion: "2.2.0",
            capabilities:
                BuildServerCapabilities(
                    compileProvider: CompileProvider(languageIds: languageIds),
                    testProvider: TestProvider(languageIds: languageIds),
                    runProvider: RunProvider(languageIds: languageIds),
                    debugProvider: nil,
                    inverseSourcesProvider: true,
                    dependencySourcesProvider: true,
                    resourcesProvider: true,
                    outputPathsProvider: true,
                    buildTargetChangedProvider: true,
                    jvmRunEnvironmentProvider: true,
                    jvmTestEnvironmentProvider: true,
                    cargoFeaturesProvider: true,
                    canReload: true,
                    jvmCompileClasspathProvider: true
                ),
            dataKind: .sourceKit,
            data: SourceKitInitializeBuildResponseData(
                indexDatabasePath: xcodeProject.indexDatabasePath.pathString,
                indexStorePath: xcodeProject.indexStorePath.pathString,
                outputPathsProvider: false,
                prepareProvider: false,
                sourceKitOptionsProvider: true,
                watchers: nil
            ).encodeToLSPAny()
        )
    }

    private func handle(request: BuildShutdownRequest) async throws -> VoidResponse {
        VoidResponse()
    }

    private func handle(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        guard state == .running else {
            throw ResponseError.unknown(
                "BuildTargetSourcesRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw ResponseError.unknown("No project")
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
            throw ResponseError.unknown("No project")
        }

        logToClient(.info, "Finding build targets...")

        let buildTargets = try await xcodeProject.loadBuildTargets()

        logToClient(.info, "Found \(buildTargets.count) targets")

        return WorkspaceBuildTargetsResponse(targets: buildTargets)
    }

    private func handle(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
        guard state == .running else {
            throw ResponseError.unknown(
                "WorkspaceBuildTargetsRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw ResponseError.unknown("No project")
        }

        try await xcodeProject.prepareTargets(targets: request.targets)

        return VoidResponse()
    }

    private func handle(
        request: TextDocumentSourceKitOptionsRequest
    ) async throws -> TextDocumentSourceKitOptionsResponse {
        guard state == .running else {
            throw ResponseError.unknown(
                "WorkspaceBuildTargetsRequest received while the build server is \(state)")
        }

        guard let xcodeProject else {
            throw ResponseError.unknown("No project")
        }

        guard let fileURL = request.textDocument.uri.fileURL else {
            fatalError()
        }

        let filePath = try AbsolutePath(validating: fileURL.path(percentEncoded: false))

        let arguments = try await xcodeProject.loadCompilerArguments(file: filePath, targetIdentifier: request.target)
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
    }
}
