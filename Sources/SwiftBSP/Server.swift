import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import System
import ToolsProtocolsSwiftExtensions
import Shared
import SwiftBuildAdapter
import XcodeAdapter

final actor Server: QueueBasedMessageHandler {
    public let messageHandlingHelper = QueueBasedMessageHandlerHelper(
        signpostLoggingCategory: "SwiftBSPMessageHandler",
        createLoggingScope: false
    )

    public let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()

    private var state = ServerState.waitingForInitializeRequest
    private let onExit: (_ code: Int32) -> Void

    private let config: Configuration
    private let connection: JSONRPCConnection
    private let taskReporter: TaskReporter
    private let diagnosticsReporter: DiagnosticsReporter
    private let logReporter: LogReporter
    private var adapter: (any BSPAdapter)?

    init(
        config: Configuration,
        messageMirrorFile: FileHandle?,
        onExit: @escaping (_ code: Int32) -> Void
    ) async throws {
        self.config = config
        self.onExit = onExit
        self.connection = JSONRPCConnection(
            name: "swift-bsp",
            protocol: .bspProtocolExtended,
            receiveFD: FileHandle.standardInput,
            sendFD: FileHandle.standardOutput,
            receiveMirrorFile: messageMirrorFile,
            sendMirrorFile: messageMirrorFile
        )
        self.taskReporter = TaskReporter(connection: connection)
        self.diagnosticsReporter = DiagnosticsReporter(connection: connection)
        self.logReporter = LogReporter(connection: connection)
    }

    package func start() async {
        connection.start(
            receiveHandler: self,
            closeHandler: {
                Log.default.info("Connection closed")
            }
        )
    }

    func handle(notification: some NotificationType) async {
        let notificationType = "\(notification.self)"
        Log.default.debug("[Receive] Notification - \(notificationType, privacy: .public)")

        guard let adapter else {
            Log.default.error("Notification received before adapter was set up")
            return
        }

        do {
            try await handle(notification: notification, adapter: adapter)
        } catch {
            Log.default.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    func handle<Request>(
        request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) async where Request: RequestType {
        let requestType = "\(request.self)"
        Log.default.debug("[Receive] Request '\(id, privacy: .public)': \(requestType, privacy: .public)")

        let requestAndReply = makeRequestAndReply(for: request, id: id, reply: reply)

        do {
            if let initializeBuildRequest = requestAndReply.params as? InitializeBuildRequest {
                self.adapter = try await makeAdapter(basedOn: initializeBuildRequest)
            } else if state != .running {
                throw ResponseError.requestFailed(
                    "Request received while the build server is '\(state)'"
                )
            }

            guard let adapter else {
                throw BuildServerError.buildServerNotStarted
            }

            await self.handle(requestAndReply: requestAndReply, adapter: adapter)
        } catch {
            await requestAndReply.reply { throw error }
        }
    }

    private func makeAdapter(basedOn initializeRequest: InitializeBuildRequest) async throws -> any BSPAdapter {
        var config = config
        config.scratchPath = config.scratchPath.appending(initializeRequest.displayName)

        if initializeRequest.displayName == "SourceKit-LSP" {
            return try await taskReporter.log(message: "Initializing build server for SourceKit-LSP") { _ in
                try await SwiftBuildAdapter(
                    config: config,
                    taskReporter: taskReporter,
                    logReporter: logReporter
                )
            }
        } else {
            return try taskReporter.log(message: "Initializing build server for Xcode") { _ in
                try XcodeAdapter(
                    config: config,
                    taskReporter: taskReporter,
                    logReporter: logReporter,
                    diagnosticsReporter: diagnosticsReporter
                )
            }
        }
    }

    private func makeRequestAndReply<Request>(
        for request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) -> RequestAndReply<Request> {
        RequestAndReply(request) { response in
            switch response {
            case .success(let message):
                let messageType = String(describing: type(of: message))
                Log.default.debug("[Send] Success response '\(id, privacy: .public)': \(messageType, privacy: .public)")
            case .failure:
                Log.default.error("[Send] Failure response '\(id, privacy: .public)'")
            }

            reply(response)
        }
    }
}

extension Server {
    func handle(notification: some NotificationType, adapter: some BSPAdapter) async throws {
        switch notification {
        case is CancelRequestNotification:
            break
        case is OnBuildExitNotification:
            onExit(state == .shutdown ? 0 : 1)
        case is OnBuildInitializedNotification:
            state = .running
        case let notification as OnWatchedFilesDidChangeNotification:
            if let response = try await adapter.handleOnWatchedFilesDidChange(notification: notification) {
                connection.send(response)
            }
        default:
            Log.default.error("Unimplemented notification")
        }
    }

    func handle<Request>(requestAndReply: RequestAndReply<Request>, adapter: any BSPAdapter) async {
        switch requestAndReply {
        case let req as RequestAndReply<BuildShutdownRequest>:
            await req.reply {
                try await adapter.handleBuildShutdown(request: req.params)
            }

            state = .shutdown

        case let req as RequestAndReply<BuildTargetSourcesRequest>:
            await req.reply {
                try await adapter.handleBuildTargetSources(request: req.params)
            }

        case let req as RequestAndReply<InitializeBuildRequest>:
            await req.reply {
                let (capabilities, sourceKitData) = try await adapter.handleInitializeBuild(request: req.params)

                return InitializeBuildResponse(
                    displayName: "swift-bsp",
                    version: "0.0.2",
                    bspVersion: "2.2.0",
                    capabilities: capabilities,
                    dataKind: sourceKitData == nil ? nil : .sourceKit,
                    data: sourceKitData
                )
            }

        case let req as RequestAndReply<WorkspaceBuildTargetsRequest>:
            await req.reply {
                try await adapter.handleWorkspaceBuildTargets(request: req.params)
            }

        case let req as RequestAndReply<WorkspaceWaitForBuildSystemUpdatesRequest>:
            await req.reply {
                try await adapter.handleWorkspaceWaitForBuildSystemUpdates(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetCompileRequest>:
            await req.reply {
                try await adapter.handleBuildTargetCompile(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetDestinationsRequest>:
            await req.reply {
                try await adapter.handleBuildTargetDestinations(request: req.params)
            }
        
        case let req as RequestAndReply<BuildTargetRunRequest>:
            await req.reply {
                try await adapter.handleBuildTargetRun(request: req.params)
            }

        case let req as RequestAndReply<BuildTargetPrepareRequest>:
            await req.reply {
                try await adapter.handleBuildTargetPrepare(request: req.params)
            }

        case let req as RequestAndReply<TextDocumentSourceKitOptionsRequest>:
            await req.reply {
                try await adapter.handleTextDocumentSourceKitOptions(request: req.params)
            }

        default:
            await requestAndReply.reply {
                throw ResponseError.requestNotImplemented(Request.self)
            }
        }
    }
}
