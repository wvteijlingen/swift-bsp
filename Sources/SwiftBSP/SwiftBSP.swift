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

    private let taskLogger: TaskLogger
    private let logger: FileLogger
    private let eventLogger: EventLogger

    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()

    private var config: BuildServerConfig?
    private var buildDescriptionID: SWBBuildDescriptionID?

    init(
        projectFilePath: FilePath,
        config: BuildServerConfig,
        taskLogger: TaskLogger,
        logger: FileLogger
    ) async throws {
        self.swiftBSPFolder = projectFilePath.removingLastComponent().appending("build")
        self.config = config
        self.taskLogger = taskLogger
        self.logger = logger
        self.eventLogger = EventLogger(logger: logger, taskLogger: taskLogger)

        self.projectFilePath = projectFilePath
        self.arena = SWBArenaInfo(root: swiftBSPFolder, indexEnableDataStore: true)
//        self.arena = try config.swiftBSP?.scratchPad.map { scratchPad in
//            let root = try AbsolutePath(validating: scratchPad)
//            return SWBArenaInfo(root: root, indexEnableDataStore: true)
//        }

        let task = taskLogger.start(title: "Initializing build server")

        let service = try await SWBBuildService(connectionMode: .default, variant: .default)

        let (session, diagnosticInfo) = await service.createSession(
            name: projectFilePath.string,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: nil, //swiftBSPFolder.appending(component: "cache").pathString,
            inferiorProductsPath: nil,  //xcodeBspFolder.appending(component: "inferiorProducts").pathString,
            environment: [:]
        )

        if !diagnosticInfo.isEmpty {
            logger.warning(diagnosticInfo)
        }

        self.buildServiceSession = try session.get()

        taskLogger.finish(id: task, status: .ok)

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
            try await self.loadWorkspace()
            let buildRequest = self.createBuildRequest()
            self.buildDescriptionID = try await self.loadBuildDescriptionID(buildRequest: buildRequest)
        }.valuePropagatingCancellation
    }

    private func loadWorkspace() async throws {
        try await taskLogger.log(title: "Loading workspace") {
            try await buildServiceSession.loadWorkspace(containerPath: projectFilePath.string)
            try await buildServiceSession.setSystemInfo(.default())
            try await buildServiceSession.setUserInfo(.default)
        }
    }

    private func createBuildRequest() -> SWBBuildRequest {
        var buildRequest = SWBBuildRequest()
        buildRequest.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
        buildRequest.useParallelTargets = true
        buildRequest.enableIndexBuildArena = true
        buildRequest.continueBuildingAfterErrors = true

        // Taken from Xcode message dump
        buildRequest.dependencyScope = .workspace
        buildRequest.hideShellScriptEnvironment = false
        buildRequest.useImplicitDependencies = true
        buildRequest.showNonLoggedProgress = true
        buildRequest.schemeCommand = .launch

        buildRequest.parameters.arenaInfo = arena
        buildRequest.parameters.action = "indexbuild"
        buildRequest.parameters.configurationName = config?.swiftBSP?.configuration ?? "Debug"
        buildRequest.parameters.activeRunDestination = config?.swiftBSP?.runDestination.map { config in
            SWBRunDestinationInfo(
                platform: config.platform ?? config.sdk,
                sdk: config.sdk,
                sdkVariant: nil,
                targetArchitecture: "undefined_arch",
                supportedArchitectures: [],
                disableOnlyActiveArch: false
            )
        }

        var synthesized = buildRequest.parameters.overrides.synthesized ?? SWBSettingsTable()
        synthesized.set(value: "NO", for: "ENABLE_XOJIT_PREVIEWS")
        synthesized.set(value: "NO", for: "ENABLE_PREVIEWS")
        synthesized.set(value: "YES", for: "ONLY_ACTIVE_ARCH")
        buildRequest.parameters.overrides.synthesized = synthesized

        return buildRequest
    }

    private func loadBuildDescriptionID(buildRequest: SWBBuildRequest) async throws -> SWBBuildDescriptionID {
        try await taskLogger.log(title: "Generating build description") {
            let configuredRequest = try await configureTargets(in: buildRequest)  //, onlyMain: false)

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

    private func configureTargets(
        in buildRequest: SWBBuildRequest,
        only: [SWBTargetGUID]? = nil // [SWBTargetGUID(rawValue: "320fb9466095fc0f9cd888bb584aebfbd01de5efbdb0778ec2cc312d20ac66e4")]
    ) async throws -> SWBBuildRequest {
        var buildRequest = buildRequest

        let workspaceInfo = try await buildServiceSession.workspaceInfo()

        for target in workspaceInfo.targetInfos {
            buildRequest.add(target: SWBConfiguredTarget(guid: target.guid))
        }

        return buildRequest
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
        try await taskLogger.log(title: "Loading targets") {
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = createBuildRequest()
            let configuredRequest = try await configureTargets(in: buildRequest)

            let targets: [SWBConfiguredTargetInfo] = try await buildServiceSession.configuredTargets(
                buildDescription: buildDescriptionID,
                buildRequest: configuredRequest
            )

            let buildTargets = try await targets.asyncMap { @Sendable targetInfo in
                try await taskLogger.log(title: "Loading target: \(targetInfo.name) (\(targetInfo.identifier.targetGUID.rawValue))") {
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
        try await taskLogger.log(title: "Loading build sources for targets \(targetIdentifiers.map(\.uri))") {
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = createBuildRequest()
            let configuredRequest = try await configureTargets(in: buildRequest)  // , onlyMain: false)
            let configuredTargetIdentifiers = try targetIdentifiers.map { try $0.configuredTargetIdentifier }

            let response = try await buildServiceSession.sources(
                of: configuredTargetIdentifiers,
                buildDescription: buildDescriptionID,
                buildRequest: configuredRequest
            )

            return try response.map { swbSourcesItem -> SourcesItem in
                let sources = swbSourcesItem.sourceFiles.map { sourceFile in
                    taskLogger.log(title: "Loading build source: \(sourceFile.path.pathString)") {
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
    func loadCompilerArguments(file: FilePath, targetIdentifier: BuildTargetIdentifier) async throws -> [String] {
        try await taskLogger.log(title: "Loading compiler arguments for target \(targetIdentifier): \(file.string)")
        {
            guard let buildDescriptionID = buildDescriptionID else {
                throw BuildServerError.noWorkspaceInfo
            }

            let buildRequest = createBuildRequest()
            let configuredRequest = try await configureTargets(in: buildRequest) //, only: [targetIdentifier.targetGUID])

            return try await buildServiceSession.indexCompilerArguments(
                of: SwiftBuild.AbsolutePath(validating: file.string),
                in: targetIdentifier.configuredTargetIdentifier,
                buildDescription: buildDescriptionID,
                buildRequest: configuredRequest
            )
        }
    }

    // MARK: - Mutators

    // BuildTargetPrepareRequest
    func prepareTargets(targets: [BuildTargetIdentifier]) async throws {
        let ids = try targets.map { try $0.configuredTargetIdentifier.targetGUID.rawValue }

        try await taskLogger.log(title: "Preparing targets: \(ids.formatted())") {
            try await preparationQueue.asyncThrowing {
                let buildRequest = self.createBuildRequest()

                var configuredRequest = try await self.configureTargets(in: buildRequest)

                let targetGUIDs = try targets.map {
                    try $0.configuredTargetIdentifier.targetGUID.rawValue
                }

                configuredRequest.buildCommand = .prepareForIndexing(
                    buildOnlyTheseTargets: targetGUIDs,
                    enableIndexBuildArena: true
                )

                let buildOperation = try await self.buildServiceSession.createBuildOperation(
                    request: configuredRequest,
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
