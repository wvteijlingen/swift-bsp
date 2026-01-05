import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Path
import SwiftBuild
import ToolsProtocolsSwiftExtensions

actor XcodeProject {
    var indexStorePath: AbsolutePath {
        try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
        //    Path($0).dirname.join("index-store").str
    }
    var indexDatabasePath: AbsolutePath {
        try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
    }

    private let logger: (LogEntry) -> Void
    private let projectFilePath: AbsolutePath
    private let arena: SWBArenaInfo
    private let buildServiceSession: SWBBuildServiceSession

    private let workspaceLoadingQueue = AsyncQueue<Serial>()
    private let preparationQueue = AsyncQueue<Serial>()

    private var workspaceInfo: (SWBBuildRequest, SWBBuildDescriptionID)?

    init(projectFilePath: AbsolutePath, logger: @escaping (LogEntry) -> Void) async throws {
        let xcodeBspFolder = projectFilePath.parentDirectory.appending(components: ".xcodebsp")

        self.projectFilePath = projectFilePath
        self.arena = SWBArenaInfo(root: xcodeBspFolder.appending(component: "arena"), indexEnableDataStore: true)
        self.logger = logger

        logger(.log("Creating session..."))

        let service = try await SWBBuildService(connectionMode: .default, variant: .default)

        let (session, diagnosticInfo) = await service.createSession(
            name: projectFilePath.pathString,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: xcodeBspFolder.appending(component: "cache").pathString,
            inferiorProductsPath: xcodeBspFolder.appending(component: "inferiorProducts").pathString,
            environment: [:]
        )

        if !diagnosticInfo.isEmpty {
            logger(.warning(diagnosticInfo))
        }

        self.buildServiceSession = try session.get()

        logger(.log("Created session"))

        try await loadProject()
    }

    // MARK: - Loaders

    func loadProject() async throws {
        try await workspaceLoadingQueue.asyncThrowing {
            try await self.loadWorkspace()
            let buildRequest = try await self.loadBasicBuildRequest()
            let buildDescriptionID = try await self.loadBuildDescriptionID(buildRequest: buildRequest)

            self.workspaceInfo = (buildRequest, buildDescriptionID)
        }.valuePropagatingCancellation
    }

    private func loadWorkspace() async throws {
        logger(.log("Loading workspace '\(projectFilePath.pathString)'..."))
        defer { logger(.log("Loaded workspace")) }

        try await buildServiceSession.loadWorkspace(containerPath: projectFilePath.pathString)
        try await buildServiceSession.setSystemInfo(.default())
    }

    private func loadBasicBuildRequest() async throws -> SWBBuildRequest {
        logger(.log("Loading build request..."))
        defer { logger(.log("Loaded build request")) }

        var buildRequest = SWBBuildRequest()
        buildRequest.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
        buildRequest.parameters.arenaInfo = arena
        buildRequest.enableIndexBuildArena = true

        let workspaceInfo = try await buildServiceSession.workspaceInfo()

        for target in workspaceInfo.targetInfos {
            buildRequest.add(target: SWBConfiguredTarget(guid: target.guid))
        }

        return buildRequest
    }

    private func loadBuildDescriptionID(buildRequest: SWBBuildRequest) async throws -> SWBBuildDescriptionID {
        logger(.log("Loading build description ID..."))
        defer { logger(.log("Loaded build description ID")) }

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

            buildDescriptionID = SWBBuildDescriptionID(info.buildDescriptionID)
        }

        guard let buildDescriptionID else {
            throw BuildServerError.cannotLoadBuildDescriptionID
        }

        return buildDescriptionID
    }

    // MARK: - Loaders

    // private func loadBuildDescriptionID() async throws -> SWBBuildDescriptionID {
    //     try await workspaceLoadingQueue.asyncThrowing {
    //         let operation = try await self.buildServiceSession.createBuildOperationForBuildDescriptionOnly(
    //             request: self.buildRequest,
    //             delegate: self
    //         )

    //         var buildDescriptionID: SWBBuildDescriptionID?

    //         for try await event in try await operation.start() {
    //             self.logEvent(event)

    //             guard case .reportBuildDescription(let info) = event else {
    //                 continue
    //             }

    //             buildDescriptionID = SWBBuildDescriptionID(info.buildDescriptionID)
    //         }

    //         guard let buildDescriptionID else {
    //             throw BuildServerError.cannotLoadBuildDescriptionID
    //         }

    //         return buildDescriptionID
    //     }.valuePropagatingCancellation
    // }

    func loadBuildTargets() async throws -> [BuildTarget] {
        guard let (buildRequest, buildDescriptionID) = workspaceInfo else {
            throw BuildServerError.noWorkspaceInfo
        }

        let targets = try await buildServiceSession.configuredTargets(
            buildDescription: buildDescriptionID,
            buildRequest: buildRequest
        )

        return try targets.map { targetInfo in
            //            let tags = try await buildServiceSession.evaluateMacroAsStringList(
            //                "BUILD_SERVER_PROTOCOL_TARGET_TAGS",
            //                level: .target(targetInfo.identifier.targetGUID.rawValue),
            //                buildParameters: buildRequest.parameters,
            //                overrides: nil
            //            ).filter {
            //                !$0.isEmpty
            //            }.map {
            //                BuildTargetTag(rawValue: $0)
            //            }

            let toolchain = targetInfo.toolchain.map { toolchain in
                DocumentURI(filePath: toolchain.pathString, isDirectory: true)
            }

            let uri = try URI(string: "swbuild-target://\(targetInfo.identifier.rawGUID)")

            let dependencies = try targetInfo.dependencies.map { dependency in
                let uri = try URI(string: "swbuild-target://\(dependency.targetGUID)")
                return BuildTargetIdentifier(uri: uri)
            }

            return BuildTarget(
                id: BuildTargetIdentifier(uri: uri),
                displayName: targetInfo.name,
                baseDirectory: nil,
                tags: [],
                capabilities: BuildTargetCapabilities(),
                languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
                dependencies: dependencies,
                dataKind: .sourceKit,
                data: SourceKitBuildTarget(toolchain: toolchain).encodeToLSPAny()
            )
        }
    }

    func loadBuildSources(targetIdentifiers: [BuildTargetIdentifier]) async throws -> [SourcesItem] {
        guard let (buildRequest, buildDescriptionID) = workspaceInfo else {
            throw BuildServerError.noWorkspaceInfo
        }

        let configuredTargetIdentifiers = targetIdentifiers.map(\.configuredTargetIdentifier)

        let response = try await buildServiceSession.sources(
            of: configuredTargetIdentifiers,
            buildDescription: buildDescriptionID,
            buildRequest: buildRequest
        )

        return try response.compactMap { swbSourcesItem -> SourcesItem? in
            let sources = swbSourcesItem.sourceFiles.map { sourceFile in
                return SourceItem(
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

            let uri = try URI(string: "swbuild-target://\(swbSourcesItem.configuredTarget.targetGUID.rawValue)")

            return SourcesItem(
                target: BuildTargetIdentifier(uri: uri),
                sources: sources
            )
        }
    }

    func loadCompilerArguments(file: AbsolutePath, targetIdentifier: BuildTargetIdentifier) async throws -> [String] {
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

    // MARK: - Mutators

    func prepareTargets(targets: [BuildTargetIdentifier]) async throws {
        try await preparationQueue.asyncThrowing {
            guard let buildRequest = self.workspaceInfo?.0 else {
                throw BuildServerError.noWorkspaceInfo
            }

            var request = buildRequest

            let targetGUIDs = targets.map {
                $0.configuredTargetIdentifier.targetGUID.rawValue
            }

            request.buildCommand = .prepareForIndexing(
                buildOnlyTheseTargets: targetGUIDs, enableIndexBuildArena: true)

            let buildOperation = try await self.buildServiceSession.createBuildOperation(
                request: request,
                delegate: self)

            let events = try await buildOperation.start()
            await self.logEvents(events)
            await buildOperation.waitForCompletion()
        }.valuePropagatingCancellation
    }

    func buildIndex() async throws {
        // TODO
    }

    func buildTarget(target: String) async throws {
        guard let buildRequest = self.workspaceInfo?.0 else {
            throw BuildServerError.noWorkspaceInfo
        }

        var request = buildRequest

        request.buildCommand = .build(style: .buildOnly)
        request.parameters.action = "build"
        request.parameters.configurationName = "Debug"

        request.add(target: SWBConfiguredTarget(guid: target))

        let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)
        let events = try await buildOperation.start()

        for await event in events {
            print(event)
        }

        await buildOperation.waitForCompletion()
    }

    func buildSources(paths: [AbsolutePath], target: String) async throws {
        guard let buildRequest = self.workspaceInfo?.0 else {
            throw BuildServerError.noWorkspaceInfo
        }

        var request = buildRequest

        request.buildCommand = .buildFiles(paths: paths.map(\.pathString), action: .compile)
        request.parameters.action = "build"
        request.parameters.configurationName = "Debug"
        //        request.parameters.activeRunDestination = SWBRunDestinationInfo(
        //            platform: "iphonesimulator",
        //            sdk: "iphonesimulator26.1",
        //            sdkVariant: nil,
        //            targetArchitecture: "arm64",
        //            supportedArchitectures: [],
        //            disableOnlyActiveArch: false,
        //            hostTargetedPlatform: nil
        //        )

        request.add(target: SWBConfiguredTarget(guid: target))

        let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)
        let events = try await buildOperation.start()
        for await event in events {
            print(event)
        }

        await buildOperation.waitForCompletion()

        print("done")

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

extension XcodeProject {
    private func logEvent(_ event: SwiftBuildMessage) {
        switch event {
        case .planningOperationStarted(_):
            logger(.log("Planning Build", .begin(StructuredLogBegin(title: "Planning Build"))))
        case .planningOperationCompleted(_):
            logger(.log("Build Planning Complete", .end(StructuredLogEnd())))
        case .buildStarted(_):
            logger(.log("Building", .begin(StructuredLogBegin(title: "Building"))))
        case .buildDiagnostic(let info):
            logger(.log(info.message, .report(StructuredLogReport())))
        case .buildCompleted(let info):
            switch info.result {
            case .ok:
                logger(.info("Build Complete", .end(StructuredLogEnd())))
            case .failed:
                logger(.error("Build Failed", .end(StructuredLogEnd())))
            case .cancelled:
                logger(.warning("Build Cancelled", .end(StructuredLogEnd())))
            case .aborted:
                logger(.warning("Build Aborted", .end(StructuredLogEnd())))
            }
        case .preparationComplete(_):
            logger(.log("Build Preparation Complete", .end(StructuredLogEnd())))
        case .didUpdateProgress(let info):
            logger(.log("Progress: \(info.message) \(info.percentComplete)%"))
        case .taskStarted(let info):
            logger(
                .log(
                    "Task Started \(info.taskID): \(info.executionDescription)",
                    .begin(
                        StructuredLogBegin(title: info.executionDescription)
                    )))
        case .taskDiagnostic(let info):
            logger(.log("Task Diagnostic \(info.taskID): \(info.message)", .report(StructuredLogReport())))
        case .taskComplete(let info):
            logger(.log("Task Complete: \(info.taskID)", .end(StructuredLogEnd())))
        case .targetDiagnostic(let info):
            logger(.log("Target Diagnostic \(info.targetID): \(info.message)", .report(StructuredLogReport())))
        case .diagnostic(let info):
            logger(.log("Diagnostic: \(info.message)", .report(StructuredLogReport())))
        case .backtraceFrame:
            logger(.log(".backtraceFrame"))
        case .reportPathMap:
            logger(.log(".reportPathMap"))
        case .reportBuildDescription:
            logger(.log(".reportBuildDescription"))
        case .preparedForIndex:
            logger(.log(".preparedForIndex"))
        case .buildOutput:
            logger(.log(".buildOutput"))
        case .targetStarted:
            logger(.log(".targetStarted"))
        case .targetComplete:
            logger(.log(".targetComplete"))
        case .targetOutput:
            logger(.log(".targetOutput"))
        case .targetUpToDate:
            logger(.log(".targetUpToDate"))
        case .taskUpToDate:
            logger(.log(".taskUpToDate"))
        case .taskOutput:
            logger(.log(".taskOutput"))
        case .output:
            logger(.log(".output"))
        }
    }

    private func logEvents(_ events: AsyncStream<SwiftBuildMessage>) async {
        for try await event in events {
            logEvent(event)
        }
    }
}
