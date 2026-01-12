import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Path
import SwiftBuild
import ToolsProtocolsSwiftExtensions

actor XcodeProject {
    // var indexStorePath: AbsolutePath {
    //     try! arena.indexDataStoreFolderPath.map {
    //         try AbsolutePath(validating: $0).appending(component: "index-store")
    //         // .dirname.join("index-store").str
    //     }!
    //     // try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
    //     // //    Path($0).dirname.join("index-store").str
    // }
    // var indexDatabasePath: AbsolutePath {
    //     try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
    // }

    private let taskLogger: TaskLogger
    private let logger: Logger
    private let projectFilePath: AbsolutePath
    // private let arena: SWBArenaInfo
    private let buildServiceSession: SWBBuildServiceSession

    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()

    private var workspaceInfo: (SWBBuildRequest, SWBBuildDescriptionID)?

    init(projectFilePath: AbsolutePath, taskLogger: TaskLogger, logger: Logger) async throws {
        let xcodeBspFolder = projectFilePath.parentDirectory.appending(components: ".xcode-bsp")

        self.taskLogger = taskLogger
        self.projectFilePath = projectFilePath
        // self.arena = SWBArenaInfo()

        // (root: xcodeBspFolder.appending(component: "arena"), indexEnableDataStore: true)
        self.logger = logger

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

    // MARK: - Loaders

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
                indexDatabasePath: nil,  //indexDatabasePath.pathString,
                indexStorePath: nil,  //indexStorePath.pathString,
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

            try await self.build()
        }.valuePropagatingCancellation
    }

    private func loadWorkspace() async throws {
        try await taskLogger.log(title: "Loading workspace") {
            try await buildServiceSession.loadWorkspace(containerPath: projectFilePath.pathString)
        }
    }

    private func loadBasicBuildRequest() async throws -> SWBBuildRequest {
        try await taskLogger.log(title: "Generating build request") {
            var buildRequest = SWBBuildRequest()
            buildRequest.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
            // buildRequest.parameters.arenaInfo = arena
            buildRequest.enableIndexBuildArena = true
            buildRequest.continueBuildingAfterErrors = true

            var overridesTable = buildRequest.parameters.overrides.commandLine ?? SWBSettingsTable()
            overridesTable.set(value: "YES", for: "ONLY_ACTIVE_ARCH")

            buildRequest.parameters.overrides.commandLine = overridesTable

            let workspaceInfo = try await buildServiceSession.workspaceInfo()

            for target in workspaceInfo.targetInfos {
                logger.info("Adding configured target: '\(target.targetName)' (\(target.guid))")
                if let dynamicTargetVariantGuid = target.dynamicTargetVariantGuid {
                    buildRequest.add(target: SWBConfiguredTarget(guid: dynamicTargetVariantGuid))
                }

                var overrides = SWBSettingsOverrides()
                overrides.commandLine?.set(value: "YES", for: "ONLY_ACTIVE_ARCH")

                var buildParameters = SWBBuildParameters()
                buildParameters.action = "indexbuild"
                buildParameters.configurationName = "Debug"
                buildParameters.overrides = overrides

                let configuredTarget = SWBConfiguredTarget(guid: target.guid, parameters: buildParameters)

                buildRequest.add(target: configuredTarget)
            }

            for targetIndex in buildRequest.configuredTargets.indices {
                buildRequest.configuredTargets[targetIndex].parameters?.action = "indexbuild"

                var overridesTable =
                    buildRequest.configuredTargets[targetIndex].parameters?.overrides.commandLine
                    ?? SWBSettingsTable()

                overridesTable.set(value: "YES", for: "ONLY_ACTIVE_ARCH")

                buildRequest.configuredTargets[targetIndex].parameters?.overrides.commandLine = overridesTable
            }

            return buildRequest
        }
    }

    private func loadBuildDescriptionID(buildRequest: SWBBuildRequest) async throws -> SWBBuildDescriptionID {
        try await taskLogger.log(title: "Generating build description") {
            try await buildServiceSession.setSystemInfo(.default())

            let operation = try await buildServiceSession.createBuildOperationForBuildDescriptionOnly(
                request: buildRequest,
                delegate: self
            )

            var buildDescriptionID: SWBBuildDescriptionID?

            for try await event in try await operation.start() {
                logEvent(event)

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

    func loadBuildTargets() async throws -> [BuildTarget] {
        try await taskLogger.log(title: "Loading targets") {
            guard let (buildRequest, buildDescriptionID) = workspaceInfo else {
                throw BuildServerError.noWorkspaceInfo
            }

            let targets = try await buildServiceSession.configuredTargets(
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
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

            let configuredTargetIdentifiers = try targetIdentifiers.map { try $0.configuredTargetIdentifier }

            let response = try await buildServiceSession.sources(
                of: configuredTargetIdentifiers,
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
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

            return try await buildServiceSession.indexCompilerArguments(
                of: SwiftBuild.AbsolutePath(validating: file.pathString),
                in: targetIdentifier.configuredTargetIdentifier,
                buildDescription: buildDescriptionID,
                buildRequest: buildRequest
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

                var request = buildRequest

                let targetGUIDs = try targets.map {
                    try $0.configuredTargetIdentifier.targetGUID.rawValue
                }

                request.buildCommand = .prepareForIndexing(
                    buildOnlyTheseTargets: targetGUIDs,
                    enableIndexBuildArena: true
                )

                let buildOperation = try await self.buildServiceSession.createBuildOperation(
                    request: request,
                    delegate: self
                )

                let events = try await buildOperation.start()

                self.logEvents(events)

                await buildOperation.waitForCompletion()
            }.valuePropagatingCancellation
        }
    }

    func build() async throws {
        try await taskLogger.log(title: "Building your anus") {
            guard let buildRequest = self.workspaceInfo?.0 else {
                throw BuildServerError.noWorkspaceInfo
            }

            var request = buildRequest

            request.buildCommand = .build(style: .buildOnly)
            request.parameters.action = "build"
            request.parameters.configurationName = "Debug"

            let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)
            let events = try await buildOperation.start()

            logEvents(events)

            await buildOperation.waitForCompletion()
        }
    }

    // func buildSources(paths: [AbsolutePath], target: String) async throws {
    //     try await taskLogger.log(title: "Building sources") {
    //         guard let buildRequest = self.workspaceInfo?.0 else {
    //             throw BuildServerError.noWorkspaceInfo
    //         }

    //         var request = buildRequest

    //         request.buildCommand = .buildFiles(paths: paths.map(\.pathString), action: .compile)
    //         request.parameters.action = "build"
    //         request.parameters.configurationName = "Debug"
    //         //        request.parameters.activeRunDestination = SWBRunDestinationInfo(
    //         //            platform: "iphonesimulator",
    //         //            sdk: "iphonesimulator26.1",
    //         //            sdkVariant: nil,
    //         //            targetArchitecture: "arm64",
    //         //            supportedArchitectures: [],
    //         //            disableOnlyActiveArch: false,
    //         //            hostTargetedPlatform: nil
    //         //        )

    //         request.add(target: SWBConfiguredTarget(guid: target))

    //         let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)
    //         let events = try await buildOperation.start()
    //         for await event in events {
    //             print(event)
    //         }

    //         await buildOperation.waitForCompletion()

    //         print("done")
    //     }
    // }
}

extension XcodeProject {
    private func logEvent(_ event: SwiftBuildMessage) {
        switch event {
        case .planningOperationStarted(let info):
            taskLogger.start(id: info.planningOperationID, title: "SwiftBuild: Planning build")
        case .planningOperationCompleted(let info):
            taskLogger.finish(id: info.planningOperationID, status: .ok)
        case .buildStarted(let info):
            logger.info(
                "Build started: baseDirectory='\(info.baseDirectory)', derivedDataPath='\(info.derivedDataPath, default: "nil")'"
            )
        case .buildDiagnostic(let info):
            logger.info("Build diagnostic: message='\(info.message)'")
        case .buildCompleted(let info):
            switch info.result {
            case .ok:
                logger.info("Build complete")
            case .failed:
                logger.error("Build failed")
            case .cancelled:
                logger.warning("Build cancelled")
            case .aborted:
                logger.warning("Build aborted")
            }
        case .preparationComplete(_):
            logger.info("Build Preparation Complete")
        case .didUpdateProgress(let info):
            logger.info("Progress: \(info.message) \(info.percentComplete)%")
        case .taskStarted(let info):
            taskLogger.start(id: info.taskID, title: "SwiftBuild: " + info.executionDescription)
        case .taskDiagnostic(let info):
            logger.info("Task Diagnostic: targetID='\(info.taskID)' message='\(info.message)'")
        case .taskComplete(let info):
            switch info.result {
            case .success:
                taskLogger.finish(id: info.taskID, status: .ok)
            case .failed:
                taskLogger.finish(id: info.taskID, status: .error)
            case .cancelled:
                taskLogger.finish(id: info.taskID, status: .cancelled)
            }
        case .targetDiagnostic(let info):
            logger.info("Target Diagnostic: targetID='\(info.targetID)', message='\(info.message)'")
        case .diagnostic(let info):
            logger.info("Diagnostic: \(info.message)")
        case .backtraceFrame:
            logger.info(".backtraceFrame")
        case .reportPathMap:
            logger.info(".reportPathMap")
        case .reportBuildDescription(let info):
            logger.info(".reportBuildDescription: buildDescriptionID='\(info.buildDescriptionID)'")
        case .preparedForIndex(let info):
            logger.info(".preparedForIndex: targetGUID='\(info.targetGUID)'")
        case .buildOutput(let info):
            logger.info(".buildOutput: data='\(info.data)'")
        case .targetStarted(let info):
            logger.info(
                ".targetStarted: targetName='\(info.targetName)', targetID='\(info.targetID)', targetGUID='\(info.targetGUID)', name='\(info.targetName)'"
            )
        case .targetComplete(let info):
            logger.info(".targetComplete: targetID='\(info.targetID)'")
        case .targetOutput(let info):
            logger.info(".targetOutput: targetID='\(info.targetID)', data=\(info.data)")
        case .targetUpToDate(let info):
            logger.info(".targetUpToDate: guid='\(info.guid)'")
        case .taskUpToDate:
            break
        // logger.info(".taskUpToDate")
        case .taskOutput(let info):
            logger.info(".taskOutput: id='\(info.taskID)', data='\(info.data)'")
        case .output:
            logger.info(".output")
        }
    }

    private func logEvents(_ events: AsyncStream<SwiftBuildMessage>) {
        Task {
            for try await event in events {
                logEvent(event)
            }
        }
    }
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
