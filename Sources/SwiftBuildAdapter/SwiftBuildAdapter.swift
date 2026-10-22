import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import SwiftBuild
import System
import ToolsProtocolsSwiftExtensions
import Shared

public actor SwiftBuildAdapter {
    private let config: Configuration
    private let taskReporter: TaskReporter
    private let logReporter: LogReporter
    // private let eventReporter: EventReporter
    private let arena: SWBArenaInfo
    private let buildServiceSession: SWBBuildServiceSession
    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()
    private var buildDescriptionID: SWBBuildDescriptionID?

    private var _configuredBuildRequest: SWBBuildRequest?
    private var configuredBuildRequest: SWBBuildRequest {
        get async throws {
            if let _configuredBuildRequest { return _configuredBuildRequest }
            let request = try await configureTargets(on: createBuildRequest())
            _configuredBuildRequest = request
            return request
        }
    }

    public init(
        config: Configuration,
        taskReporter: TaskReporter,
        logReporter: LogReporter
    ) async throws {
        self.config = config
        self.taskReporter = taskReporter
        self.logReporter = logReporter
        // self.eventReporter = EventReporter(taskReporter: taskReporter)
        self.arena = SWBArenaInfo(root: config.scratchPath, indexEnableDataStore: true)

        let service = try await SWBBuildService(connectionMode: .default, variant: .default, serviceBundleURL: nil)

        let (session, _) = await service.createSession(
            name: config.xcodeProjectPath.string,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: nil,
            inferiorProductsPath: nil,
            environment: [:]
        )

        self.buildServiceSession = try session.get()

        try await loadProject()
    }

    deinit {
        Task { [buildServiceSession] in
            try? await buildServiceSession.close()
        }
    }

    public func closeSession() async throws {
        try await buildServiceSession.close()
    }

    // MARK: - Project loading

    public func loadProject() async throws {
        try await workspaceLoadingQueue.asyncThrowing {
            self._configuredBuildRequest = nil
            try await self.loadWorkspace()
            self.buildDescriptionID = try await self.loadBuildDescriptionID()
        }.valuePropagatingCancellation
    }

    private func loadWorkspace() async throws {
        try await taskReporter.log(message: "Loading workspace") { _ in
            try await buildServiceSession.loadWorkspace(containerPath: config.xcodeProjectPath.string)
            try await buildServiceSession.setSystemInfo(.default())
            try await buildServiceSession.setUserInfo(.default)
        }
    }

    private func loadBuildDescriptionID() async throws -> SWBBuildDescriptionID {
        try await taskReporter.log(message: "Generating build description") { _ in
            let configuredRequest = try await configuredBuildRequest

            let operation = try await buildServiceSession.createBuildOperationForBuildDescriptionOnly(
                request: configuredRequest,
                delegate: self
            )

            var buildDescriptionID: SWBBuildDescriptionID?

            for try await event in try await operation.start() {
                if case let .output(info) = event, let string = String(data: info.data, encoding: .utf8) {
                    logReporter.log(message: string, type: .info)
                }

                guard case .reportBuildDescription(let info) = event else {
                    continue
                }

                guard buildDescriptionID == nil else {
                    throw ResponseError.unknown("Unexpectedly reported multiple build descriptions")
                }

                buildDescriptionID = SWBBuildDescriptionID(info.buildDescriptionID)
            }

            guard let buildDescriptionID else {
                throw BuildServerError.cannotLoadBuildDescriptionID
            }

            return buildDescriptionID
        }
    }

    // MARK: - Loaders

    public  func waitForUpdates() async {
        await workspaceLoadingQueue.async {
            // No updates are pending once this closure is executed
        }.valuePropagatingCancellation
    }

    // InitializeBuildRequest
    public func initialize() -> LSPAny? {
        SourceKitInitializeBuildResponseData(
            indexDatabasePath: arena.indexDataStoreFolderPath,
            indexStorePath: arena.indexDataStoreFolderPath,
            outputPathsProvider: true,
            prepareProvider: true,
            sourceKitOptionsProvider: true,
            watchers: [
                FileSystemWatcher(globPattern: config.xcodeProjectPath.string, kind: .change),
                FileSystemWatcher(
                    globPattern: config.workspacePath.appending("buildServer.json").string,
                    kind: .change
                ),
                FileSystemWatcher(globPattern: "**/*.swift", kind: [.create, .delete]),
            ]
        ).encodeToLSPAny()
    }

    // WorkspaceBuildTargetsRequest
    public func loadBuildTargets() async throws -> [BuildTarget] {
        try await taskReporter.log(message: "Loading Swift Build targets") { taskId in
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = try await configuredBuildRequest

            let targets: [SWBConfiguredTargetInfo] = try await buildServiceSession.configuredTargets(
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
            )

            let buildTargets = try await targets.asyncMap { @Sendable targetInfo in
                try await taskReporter.log(
                    message: "Loading Swift Build target '\(targetInfo.name)'",
                    parent: taskId
                ) { _ in
                    let tags = try await buildServiceSession.evaluateMacroAsStringList(
                        "BUILD_SERVER_PROTOCOL_TARGET_TAGS",
                        level: .target(targetInfo.identifier.targetGUID.rawValue),
                        buildParameters: buildRequest.parameters,
                        overrides: nil
                    ).filter {
                        !$0.isEmpty
                    }.map {
                        BuildTargetTag(rawValue: $0)
                    }.appending(contentsOf: [.noIDE])

                    let toolchain = targetInfo.toolchain.map { toolchain in
                        DocumentURI(filePath: toolchain.pathString, isDirectory: true)
                    }

                    let displayName = "\(targetInfo.name) (\(targetInfo.identifier.sdkVariant, default: "unknown SDK"))"

                    let target = BuildTarget(
                        id: try BuildTargetIdentifier(configuredTargetIdentifier: targetInfo.identifier),
                        displayName: displayName,
                        baseDirectory: nil,
                        tags: tags,
                        capabilities: BuildTargetCapabilities(
                            canCompile: false,
                            canTest: false,
                            canRun: false,
                            canDebug: false
                        ),
                        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
                        dependencies: [],
                        dataKind: .sourceKit,
                        data: SourceKitBuildTarget(toolchain: toolchain).encodeToLSPAny()
                    )

                    return target
                }
            }

            return buildTargets.removingDuplicates()
        }
    }

    // BuildTargetSourcesRequest
    public func loadBuildSources(targets: [SWBConfiguredTargetIdentifier]) async throws -> [SourcesItem] {
        try await taskReporter.log(message: "Loading build sources") { taskId in
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = try await configuredBuildRequest
//            let configuredTargetIdentifiers = try targetIdentifiers.map { try $0.configuredTargetIdentifier }

            let response = try await buildServiceSession.sources(
                of: targets,
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
            )

            return try response.map { swbSourcesItem -> SourcesItem in
                let sources = swbSourcesItem.sourceFiles.map { sourceFile in
                    taskReporter.log(
                        message: "Loading build source: \(sourceFile.path.pathString)",
                        parent: taskId
                    ) { _ in
                        SourceItem(
                            uri: DocumentURI(URL(filePath: sourceFile.path.pathString)),
                            kind: .file,
                            generated: false,
                            dataKind: .sourceKit,
                            data: SourceKitSourceItemData(
                                language: sourceFile.language.flatMap { Language($0) },
                                outputPath: sourceFile.indexOutputPath
                            ).encodeToLSPAny()
                        )
                    }
                }

                return SourcesItem(
                    target: try BuildTargetIdentifier(configuredTargetIdentifier: swbSourcesItem.configuredTarget),
                    sources: sources
                )
            }
        }
    }

    // TextDocumentSourceKitOptionsRequest
    public func loadCompilerArguments(file: FilePath, target: BuildTargetIdentifier) async throws -> [String] {
        try await taskReporter.log(message: "Loading compiler arguments for '\(file.string)'") { _ in
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = try await configuredBuildRequest

            return try await buildServiceSession.indexCompilerArguments(
                of: SwiftBuild.AbsolutePath(validating: file.string),
                in: target.swiftBuildTarget,
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
            )
        }
    }

    // MARK: - Mutators

    // BuildTargetPrepareRequest
    public func prepareTargets(targets: [SWBConfiguredTargetIdentifier]) async throws {
        try await taskReporter.log(message: "Preparing targets") { _ in
            try await preparationQueue.asyncThrowing {
                let targetGUIDs = targets.map { $0.targetGUID.rawValue }

                var buildRequest = try await self.configuredBuildRequest
                buildRequest.buildCommand = .prepareForIndexing(
                    buildOnlyTheseTargets: targetGUIDs,
                    enableIndexBuildArena: true
                )

                let buildOperation = try await self.buildServiceSession.createBuildOperation(
                    request: buildRequest,
                    delegate: self
                )

                _ = try await buildOperation.start()

                // self.eventReporter.log(events: events)

                await buildOperation.waitForCompletion()
            }.valuePropagatingCancellation
        }
    }
}

// MARK: - SWBPlanningOperationDelegate, SWBIndexingDelegate

extension SwiftBuildAdapter: SWBIndexingDelegate {
    public func provisioningTaskInputs(
        targetGUID: String,
        provisioningSourceData: SWBProvisioningTaskInputsSourceData
    ) async -> SWBProvisioningTaskInputs {
        SWBProvisioningTaskInputs()
    }

    public func executeExternalTool(
        commandLine: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> SWBExternalToolResult {
        .deferred
    }
}

extension SwiftBuildAdapter {
    private func createBuildRequest() -> SWBBuildRequest {
        var buildRequest = SWBBuildRequest()
        buildRequest.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
        buildRequest.useParallelTargets = true
        buildRequest.enableIndexBuildArena = true
        buildRequest.continueBuildingAfterErrors = true
        buildRequest.containerPath = config.xcodeProjectPath.string

        // Taken from Xcode message dump
        buildRequest.dependencyScope = .workspace
        buildRequest.hideShellScriptEnvironment = false
        buildRequest.useImplicitDependencies = true
        buildRequest.showNonLoggedProgress = true
        buildRequest.schemeCommand = .launch

        buildRequest.parameters.arenaInfo = arena
        buildRequest.parameters.action = "indexbuild"
        buildRequest.parameters.configurationName = config.configuration ?? "Debug"

        if let runDestination = config.runDestination {
            buildRequest.parameters.activeRunDestination = SWBRunDestinationInfo(
                buildTarget: .toolchainSDK(
                    platform: runDestination.platform ?? runDestination.sdk,
                    sdk: runDestination.sdk,
                    sdkVariant: nil
                ),
                targetArchitecture: "undefined_arch",
                supportedArchitectures: [],
                disableOnlyActiveArch: false
            )
        }

        var overrides = buildRequest.parameters.overrides.commandLine ?? SWBSettingsTable()
        overrides.set(value: "NO", for: "ENABLE_XOJIT_PREVIEWS")
        overrides.set(value: "NO", for: "ENABLE_PREVIEWS")
        overrides.set(value: "NO", for: "COLOR_DIAGNOSTICS")
        overrides.set(value: "YES", for: "ONLY_ACTIVE_ARCH")
        buildRequest.parameters.overrides.commandLine = overrides

        return buildRequest
    }

    private func configureTargets(on buildRequest: SWBBuildRequest) async throws -> SWBBuildRequest {
        var buildRequest = buildRequest
        var supportedPlatforms: Set<String>?

        let workspaceInfo = try await buildServiceSession.workspaceInfo()

        for target in workspaceInfo.targetInfos {
            if target.guid.starts(with: "PACKAGE-") { continue }

            Log.default.info(
                "Adding target to build request: \(target.targetName, privacy: .public) (\(target.guid, privacy: .public))"
            )
            buildRequest.add(target: SWBConfiguredTarget(guid: target.guid))

            if !target.guid.starts(with: "PACKAGE-") {
                let platforms = try await buildServiceSession.evaluateMacroAsStringList(
                    "SUPPORTED_PLATFORMS",
                    level: .target(target.guid),
                    buildParameters: SWBBuildParameters(),
                    overrides: nil
                )

                supportedPlatforms = supportedPlatforms?.intersection(platforms) ?? Set(platforms)
            }
        }

        if buildRequest.parameters.activeRunDestination == nil {
            if let firstPlatform = supportedPlatforms?.sorted().first {
                Log.default.warning("No custom run destination set. Using '\(firstPlatform, privacy: .public)'")

                buildRequest.parameters.activeRunDestination = SWBRunDestinationInfo(
                    buildTarget: .toolchainSDK(
                        platform: firstPlatform,
                        sdk: firstPlatform,
                        sdkVariant: nil
                    ),
                    targetArchitecture: "undefined_arch",
                    supportedArchitectures: [],
                    disableOnlyActiveArch: false
                )
            } else {
                Log.default.warning(
                    "No custom run destination set and could not determine a default destination. This may result in indexing errors."
                )
            }
        }

        return buildRequest
    }
}

extension SwiftBuildAdapter: BSPAdapter {
    public func handleOnWatchedFilesDidChange(
        notification: OnWatchedFilesDidChangeNotification
    ) async throws -> OnBuildTargetDidChangeNotification? {
        // TODO: Make this more robust
        let needsReload = notification.changes.contains { change in
            guard let filePath = change.uri.fileURL?.path(percentEncoded: false) else { return false }

            // Ignore changes in the scratch pad
            guard !filePath.starts(with: config.scratchPath.string) else { return false }

            // Ignore changes in .build folders
            guard !filePath.contains(".build/") else { return false }

            // Ignore changes in .git folders
            guard !filePath.contains(".git/") else { return false }

            return change.type == .created || change.type == .deleted || filePath == config.xcodeProjectPath.string
        }

        if needsReload {
            try await loadProject()
            return OnBuildTargetDidChangeNotification(changes: nil)
        }
        
        return nil
    }
    
    public func handleInitializeBuild(
        request: InitializeBuildRequest
    ) async throws -> (
        capabilities: BuildServerCapabilities,
        sourceKitData: LSPAny?
    ) {
        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]
        let sourceKitData = initialize()
        let capabilities = BuildServerCapabilities(
            compileProvider: CompileProvider(languageIds: languageIds),
            testProvider: nil,
            runProvider: nil,
            debugProvider: nil,
            inverseSourcesProvider: false,
            dependencySourcesProvider: false,
            resourcesProvider: false,
            outputPathsProvider: false,
            buildTargetChangedProvider: true,
            jvmRunEnvironmentProvider: false,
            jvmTestEnvironmentProvider: false,
            cargoFeaturesProvider: false,
            canReload: true,
            jvmCompileClasspathProvider: false
        )

        return (capabilities, sourceKitData)
    }
    
    public func handleBuildShutdown(
        request: BuildShutdownRequest
    ) async throws -> VoidResponse {
        try await closeSession()
        return VoidResponse()
    }
    
    public func handleBuildTargetSources(
        request: BuildTargetSourcesRequest
    ) async throws -> BuildTargetSourcesResponse {
        let targets = try request.targets.map { try $0.swiftBuildTarget }
        let sources = try await loadBuildSources(targets: targets)
        return BuildTargetSourcesResponse(items: sources)
    }
    
    public func handleWorkspaceBuildTargets(
        request: WorkspaceBuildTargetsRequest
    ) async throws -> WorkspaceBuildTargetsResponse {
        let targets = try await loadBuildTargets()
        return WorkspaceBuildTargetsResponse(targets: targets)
    }
    
    public func handleWorkspaceWaitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest
    ) async throws -> VoidResponse {
        await waitForUpdates()
        return VoidResponse()
    }
    
    public func handleBuildTargetCompile(
        request: BuildTargetCompileRequest
    ) async throws -> BuildTargetCompileResponse {
        throw ResponseError.requestNotImplemented(BuildTargetCompileRequest.self)
    }
    
    public func handleBuildTargetDestinations(
        request: BuildTargetDestinationsRequest
    ) async throws -> Shared.BuildTargetDestinationsResponse {
        throw ResponseError.requestNotImplemented(BuildTargetDestinationsRequest.self)
    }

    public func handleBuildTargetRun(
        request: BuildTargetRunRequest
    ) async throws -> BuildTargetRunResponse {
        throw ResponseError.requestNotImplemented(BuildTargetRunRequest.self)
    }
    
    public func handleBuildTargetPrepare(
        request: BuildTargetPrepareRequest
    ) async throws -> VoidResponse {
        let targets = try request.targets.map { try $0.swiftBuildTarget }
        try await prepareTargets(targets: targets)
        return VoidResponse()
    }
    
    public func handleTextDocumentSourceKitOptions(
        request: TextDocumentSourceKitOptionsRequest
    ) async throws -> TextDocumentSourceKitOptionsResponse {
        guard let fileURL = request.textDocument.uri.fileURL else {
            throw BuildServerError.invalidFileURI(request.textDocument.uri)
        }

        let filePath = FilePath(fileURL.path(percentEncoded: false))
        let arguments = try await loadCompilerArguments(file: filePath, target: request.target)

        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
    }
}
