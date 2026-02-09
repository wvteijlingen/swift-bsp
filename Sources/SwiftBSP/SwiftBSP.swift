import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import System
import SwiftBuild
import ToolsProtocolsSwiftExtensions

actor SwiftBSP {
    private let swiftBSPFolder: FilePath
    private let projectFilePath: FilePath
    private let arena: SWBArenaInfo
    private let buildServiceSession: SWBBuildServiceSession

    private let taskReporter: TaskReporter
    private let eventLogger: EventLogger

    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()

    private var config: BuildServerConfig?
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

    init(projectFilePath: FilePath, config: BuildServerConfig, taskReporter: TaskReporter) async throws {
        self.swiftBSPFolder = projectFilePath.removingLastComponent().appending("build")
        self.config = config
        self.taskReporter = taskReporter
        self.eventLogger = EventLogger(taskReporter: taskReporter)

        self.projectFilePath = projectFilePath
        self.arena = SWBArenaInfo(root: swiftBSPFolder, indexEnableDataStore: true)

        let task = taskReporter.start(title: "Initializing build server")
        let service = try await SWBBuildService(connectionMode: .default, variant: .default)

        let (session, _) = await service.createSession(
            name: projectFilePath.string,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: nil,
            inferiorProductsPath: nil,
            environment: [:]
        )

        self.buildServiceSession = try session.get()

        taskReporter.finish(id: task, status: .ok)

        try await loadProject()
    }

    deinit {
        Task { [buildServiceSession] in
            try? await buildServiceSession.close()
        }
    }

    func closeSession() async throws {
        try await buildServiceSession.close()
    }

    // MARK: - Project loading

    func loadProject() async throws {
        try await workspaceLoadingQueue.asyncThrowing {
            self._configuredBuildRequest = nil
            try await self.loadWorkspace()
            self.buildDescriptionID = try await self.loadBuildDescriptionID()
        }.valuePropagatingCancellation
    }

    private func loadWorkspace() async throws {
        try await taskReporter.log(title: "Loading workspace") {
            try await buildServiceSession.loadWorkspace(containerPath: projectFilePath.string)
            try await buildServiceSession.setSystemInfo(.default())
            try await buildServiceSession.setUserInfo(.default)
        }
    }

    private func loadBuildDescriptionID() async throws -> SWBBuildDescriptionID {
        try await taskReporter.log(title: "Generating build description") {
            let configuredRequest = try await configuredBuildRequest

            let operation = try await buildServiceSession.createBuildOperationForBuildDescriptionOnly(
                request: configuredRequest,
                delegate: self
            )

            var buildDescriptionID: SWBBuildDescriptionID?

            for try await event in try await operation.start() {
                eventLogger.log(event: event)

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

    func waitForUpdates() async {
        await workspaceLoadingQueue.async {
            // No updates are pending once this closure is executed
        }.valuePropagatingCancellation
    }

    // InitializeBuildRequest
    func initialize() -> InitializeBuildResponse {
        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]

        return InitializeBuildResponse(
            displayName: "swift-bsp \(buildServiceSession.uid)",
            version: "0.0.1",
            bspVersion: "2.2.0",
            capabilities:
                BuildServerCapabilities(
                    compileProvider: CompileProvider(languageIds: languageIds),
                    testProvider: TestProvider(languageIds: languageIds),
                    runProvider: RunProvider(languageIds: languageIds),
                    debugProvider: nil,
                    inverseSourcesProvider: nil,
                    dependencySourcesProvider: nil,
                    resourcesProvider: nil,
                    outputPathsProvider: nil,
                    buildTargetChangedProvider: nil,
                    jvmRunEnvironmentProvider: nil,
                    jvmTestEnvironmentProvider: nil,
                    cargoFeaturesProvider: nil,
                    canReload: nil,
                    jvmCompileClasspathProvider: nil
                ),
            dataKind: .sourceKit,
            data: SourceKitInitializeBuildResponseData(
                indexDatabasePath: arena.indexDataStoreFolderPath,
                indexStorePath: arena.indexDataStoreFolderPath,
                outputPathsProvider: true,
                prepareProvider: true,
                sourceKitOptionsProvider: true,
                watchers: [
                    FileSystemWatcher(globPattern: projectFilePath.string, kind: .change),
                    FileSystemWatcher(
                        globPattern: projectFilePath.removingLastComponent().appending("buildServer.json").string,
                        kind: .change
                    ),
                    FileSystemWatcher(globPattern: "**/*.swift", kind: [.create, .delete])
                ]
            ).encodeToLSPAny()
        )
    }

    // WorkspaceBuildTargetsRequest
    func loadBuildTargets() async throws -> [BuildTarget] {
        try await taskReporter.log(title: "Loading targets") {
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = try await configuredBuildRequest

            let targets: [SWBConfiguredTargetInfo] = try await buildServiceSession.configuredTargets(
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
            )

            let buildTargets = try await targets.asyncMap { @Sendable targetInfo in
                try await taskReporter.log(title: "Loading target: \(targetInfo.name) (\(targetInfo.identifier.targetGUID.rawValue))") {
                    let tags = try await buildServiceSession.evaluateMacroAsStringList(
                        "BUILD_SERVER_PROTOCOL_TARGET_TAGS",
                        level: .target(targetInfo.identifier.targetGUID.rawValue),
                        buildParameters: buildRequest.parameters,
                        overrides: nil
                    ).filter {
                        !$0.isEmpty
                    }.map {
                        BuildTargetTag(rawValue: $0)
                    }

                    let toolchain = targetInfo.toolchain.map { toolchain in
                        DocumentURI(filePath: toolchain.pathString, isDirectory: true)
                    }

                    let target = BuildTarget(
                        id: try BuildTargetIdentifier(configuredTargetIdentifier: targetInfo.identifier),
                        displayName: "\(targetInfo.name) (\(targetInfo.identifier.sdkVariant, default: "unknown SDK"))",
                        baseDirectory: nil,
                        tags: tags,
                        capabilities: BuildTargetCapabilities(),
                        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
                        dependencies: [], //allDependencies,
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
    func loadBuildSources(targetIdentifiers: [BuildTargetIdentifier]) async throws -> [SourcesItem] {
        try await taskReporter.log(title: "Loading build sources for targets \(targetIdentifiers.map(\.uri))") {
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = try await configuredBuildRequest
            let configuredTargetIdentifiers = try targetIdentifiers.map { try $0.configuredTargetIdentifier }

            let response = try await buildServiceSession.sources(
                of: configuredTargetIdentifiers,
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
            )

            return try response.map { swbSourcesItem -> SourcesItem in
                let sources = swbSourcesItem.sourceFiles.map { sourceFile in
//                    taskReporter.log(title: "Loading build source: \(sourceFile.path.pathString)") {
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
//                    }
                }

                return SourcesItem(
                    target: try BuildTargetIdentifier(configuredTargetIdentifier: swbSourcesItem.configuredTarget),
                    sources: sources
                )
            }
        }
    }

    // TextDocumentSourceKitOptionsRequest
    func loadCompilerArguments(file: FilePath, targetIdentifier: BuildTargetIdentifier) async throws -> [String] {
        try await taskReporter.log(title: "Loading compiler arguments for target \(targetIdentifier): \(file.string)")
        {
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = try await configuredBuildRequest

            return try await buildServiceSession.indexCompilerArguments(
                of: SwiftBuild.AbsolutePath(validating: file.string),
                in: targetIdentifier.configuredTargetIdentifier,
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
            )
        }
    }

    // MARK: - Mutators

    // BuildTargetPrepareRequest
    func prepareTargets(targets: [BuildTargetIdentifier]) async throws {
        let ids = try targets.map { try $0.configuredTargetIdentifier.targetGUID.rawValue }

        try await taskReporter.log(title: "Preparing targets: \(ids.formatted())") {
            try await preparationQueue.asyncThrowing {
                let targetGUIDs = try targets.map {
                    try $0.configuredTargetIdentifier.targetGUID.rawValue
                }

                var buildRequest = try await self.configuredBuildRequest
                buildRequest.buildCommand = .prepareForIndexing(
                    buildOnlyTheseTargets: targetGUIDs,
                    enableIndexBuildArena: true
                )

                let buildOperation = try await self.buildServiceSession.createBuildOperation(
                    request: buildRequest,
                    delegate: self
                )

                let events = try await buildOperation.start()

                self.eventLogger.log(events: events)

                await buildOperation.waitForCompletion()
            }.valuePropagatingCancellation
        }
    }
}

// MARK: - SWBPlanningOperationDelegate, SWBIndexingDelegate

extension SwiftBSP: SWBIndexingDelegate {
    func provisioningTaskInputs(
        targetGUID: String,
        provisioningSourceData: SWBProvisioningTaskInputsSourceData
    ) async -> SWBProvisioningTaskInputs {
        SWBProvisioningTaskInputs()
    }

    func executeExternalTool(
        commandLine: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> SWBExternalToolResult {
        .deferred
    }
}

extension SwiftBSP {
    private func createBuildRequest() -> SWBBuildRequest {
        var buildRequest = SWBBuildRequest()
        buildRequest.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
        buildRequest.useParallelTargets = true
        buildRequest.enableIndexBuildArena = true
        buildRequest.continueBuildingAfterErrors = true
        buildRequest.containerPath = projectFilePath.string

        // Taken from Xcode message dump
        buildRequest.dependencyScope = .workspace
        buildRequest.hideShellScriptEnvironment = false
        buildRequest.useImplicitDependencies = true
        buildRequest.showNonLoggedProgress = true
        buildRequest.schemeCommand = .launch

        buildRequest.parameters.arenaInfo = arena
        buildRequest.parameters.action = "indexbuild"
        buildRequest.parameters.configurationName = config?.swiftBSP?.configuration ?? "Debug"

        if let runDestination = config?.swiftBSP?.runDestination {
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

            Log.default.info("Adding target to build request: \(target.targetName, privacy: .public) (\(target.guid, privacy: .public))")
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
                Log.default.warning("No custom run destination set and could not determine a default destination. This may result in indexing errors.")
            }
        }

        return buildRequest
    }
}
