import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Path
import SwiftBuild
import ToolsProtocolsSwiftExtensions

actor XcodeProject {
    private let taskLogger: TaskLogger
    private let logger: Logger
    private let eventLogger: EventLogger
    private let projectFilePath: AbsolutePath
    private let arena: SWBArenaInfo
    private let buildServiceSession: SWBBuildServiceSession

    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()

    private var workspaceInfo: (SWBBuildRequest, SWBBuildDescriptionID)?

    init(projectFilePath: AbsolutePath, taskLogger: TaskLogger, logger: Logger) async throws {
        let xcodeBspFolder = projectFilePath.parentDirectory.appending(components: ".xcode-bsp")

        self.taskLogger = taskLogger
        self.logger = logger
        self.eventLogger = EventLogger(logger: logger, taskLogger: taskLogger)

        self.projectFilePath = projectFilePath
        self.arena = SWBArenaInfo(root: xcodeBspFolder.appending(component: "arena"), indexEnableDataStore: true)

        let task = taskLogger.start(title: "Initializing build server")

        let service = try await SWBBuildService(connectionMode: .default, variant: .default)

        logger.info("Clearing caches...")
        try await service.clearAllCaches()
        logger.info("Cleared caches")

        let (session, diagnosticInfo) = await service.createSession(
            name: projectFilePath.pathString,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: xcodeBspFolder.appending(component: "cache").pathString,
            inferiorProductsPath: xcodeBspFolder.appending(component: "inferiorProducts").pathString,
            environment: [:]
        )

        if !diagnosticInfo.isEmpty {
            logger.warning(diagnosticInfo)
        }

        self.buildServiceSession = try session.get()

        taskLogger.finish(id: task, status: .ok)

        try await loadProject()
    }

    func waitForUpdates() async {
        await workspaceLoadingQueue.async {
            // No updates are pending once this closure is executed
        }.valuePropagatingCancellation
    }

    // MARK: - Configuration

    func initialize() -> InitializeBuildResponse {
        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]

        return InitializeBuildResponse(
            displayName: "xcode-bsp \(buildServiceSession.uid)",
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
                watchers: nil
            ).encodeToLSPAny()
        )
    }

    func loadProject() async throws {
        try await workspaceLoadingQueue.asyncThrowing {
            try await self.loadWorkspace()
            let buildRequest = try await self.loadBasicBuildRequest()
            let buildDescriptionID = try await self.loadBuildDescriptionID(buildRequest: buildRequest)

            self.workspaceInfo = (buildRequest, buildDescriptionID)

            // try await self.build()
        }.valuePropagatingCancellation
    }

    private func loadWorkspace() async throws {
        try await taskLogger.log(title: "Loading workspace") {
            try await buildServiceSession.loadWorkspace(containerPath: projectFilePath.pathString)
            try await buildServiceSession.setUserInfo(.default)
            try await buildServiceSession.setSystemInfo(.default())
        }
    }

    private func loadBasicBuildRequest() async throws -> SWBBuildRequest {
        taskLogger.log(title: "Generating build request") {
            var buildRequest = SWBBuildRequest()
            buildRequest.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
            buildRequest.continueBuildingAfterErrors = true
            buildRequest.useParallelTargets = true
            buildRequest.parameters.arenaInfo = arena
            buildRequest.enableIndexBuildArena = true
            buildRequest.continueBuildingAfterErrors = true

            return buildRequest
        }
    }

    private func loadBuildDescriptionID(buildRequest: SWBBuildRequest) async throws -> SWBBuildDescriptionID {
        try await taskLogger.log(title: "Generating build description") {
            let configuredRequest = try await configureTargets(in: buildRequest, onlyMain: false)

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

    private func configureTargets(in buildRequest: SWBBuildRequest, onlyMain: Bool) async throws -> SWBBuildRequest {
        var buildRequest = buildRequest

        let workspaceInfo = try await buildServiceSession.workspaceInfo()

        for target in workspaceInfo.targetInfos {
            let isExternalTarget =
                target.guid.starts(with: "PACKAGE-TARGET") || target.guid.starts(with: "PACKAGE-PRODUCT")

            if onlyMain && isExternalTarget { continue }

            buildRequest.add(target: SWBConfiguredTarget(guid: target.guid))
        }

        return buildRequest
    }

    // MARK: - Loaders

    func loadBuildTargets() async throws -> [BuildTarget] {
        try await taskLogger.log(title: "Loading targets") {
            guard let (buildRequest, buildDescriptionID) = workspaceInfo else {
                throw BuildServerError.noWorkspaceInfo
            }

            let configuredRequest = try await configureTargets(in: buildRequest, onlyMain: false)

            let targets = try await buildServiceSession.configuredTargets(
                buildDescription: buildDescriptionID,
                buildRequest: configuredRequest
            )

            return try await targets.asyncMap { @Sendable targetInfo in
                try await taskLogger.log(title: "Loading target: \(targetInfo.name)") {
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

                    let dependencies = try targetInfo.dependencies.map { dependency in
                        try BuildTargetIdentifier(configuredTargetIdentifier: dependency)
                    }

                    let target = BuildTarget(
                        id: try BuildTargetIdentifier(configuredTargetIdentifier: targetInfo.identifier),
                        displayName: targetInfo.name,
                        baseDirectory: nil,
                        tags: tags,
                        capabilities: BuildTargetCapabilities(),
                        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
                        dependencies: dependencies,
                        dataKind: .sourceKit,
                        data: SourceKitBuildTarget(toolchain: toolchain).encodeToLSPAny()
                    )

                    logger.info("Found target '\(targetInfo.name)': \(dependencies))")

                    return target
                }
            }
        }
    }

    func loadBuildSources(targetIdentifiers: [BuildTargetIdentifier]) async throws -> [SourcesItem] {
        try await taskLogger.log(title: "Loading build sources") {
            guard let (buildRequest, buildDescriptionID) = workspaceInfo else {
                throw BuildServerError.noWorkspaceInfo
            }

            let configuredRequest = try await configureTargets(in: buildRequest, onlyMain: false)
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

    func loadCompilerArguments(file: AbsolutePath, targetIdentifier: BuildTargetIdentifier) async throws -> [String] {
        try await taskLogger.log(title: "Loading compiler arguments: \(file.pathString)") {
            guard let (buildRequest, buildDescriptionID) = workspaceInfo else {
                throw BuildServerError.noWorkspaceInfo
            }

            let configuredRequest = try await configureTargets(in: buildRequest, onlyMain: true)

            return try await buildServiceSession.indexCompilerArguments(
                of: SwiftBuild.AbsolutePath(validating: file.pathString),
                in: targetIdentifier.configuredTargetIdentifier,
                buildDescription: buildDescriptionID,
                buildRequest: configuredRequest
            )
        }
    }

    // MARK: - Mutators

    func prepareTargets(targets: [BuildTargetIdentifier]) async throws {
        let ids = try targets.map { try $0.configuredTargetIdentifier.targetGUID.rawValue }

        try await taskLogger.log(title: "Preparing targets: \(ids.formatted())") {
            try await preparationQueue.asyncThrowing {
                guard let buildRequest = self.workspaceInfo?.0 else {
                    throw BuildServerError.noWorkspaceInfo
                }

                var configuredRequest = try await self.configureTargets(in: buildRequest, onlyMain: true)

                // let targetGUIDs = try targets.map {
                //     try $0.configuredTargetIdentifier.targetGUID.rawValue
                // }

                configuredRequest.buildCommand = .prepareForIndexing(
                    buildOnlyTheseTargets: nil,
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

    // func build() async throws {
    //     try await taskLogger.log(title: "Building your anus") {
    //         guard let buildRequest = self.workspaceInfo?.0 else {
    //             throw BuildServerError.noWorkspaceInfo
    //         }

    //         var configuredRequest = try await self.configureTargets(in: buildRequest, onlyMain: true)

    //         configuredRequest.buildCommand = .build(style: .buildOnly, skipDependencies: false)
    //         configuredRequest.parameters.action = "build"
    //         configuredRequest.parameters.configurationName = "Debug"

    //         let buildOperation = try await buildServiceSession.createBuildOperation(
    //             request: configuredRequest,
    //             delegate: self
    //         )

    //         let events = try await buildOperation.start()

    //         logEvents(events)

    //         await buildOperation.waitForCompletion()
    //     }
    // }
}

// MARK: - SWBPlanningOperationDelegate, SWBIndexingDelegate

extension XcodeProject: SWBIndexingDelegate {
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
