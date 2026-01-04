import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Path
import SwiftBuild

actor XcodeProject {
    var indexStorePath: AbsolutePath {
        try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
        //    Path($0).dirname.join("index-store").str
    }
    var indexDatabasePath: AbsolutePath {
        try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
    }

    private let logger: (LogEntry) -> Void

    private let arena: SWBArenaInfo
    private let buildServiceSession: SWBBuildServiceSession
    private var buildRequest: SWBBuildRequest {
        get async throws {
            var request = SWBBuildRequest()
            request.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
            request.parameters.arenaInfo = arena
            request.enableIndexBuildArena = true

            let workspaceInfo = try await buildServiceSession.workspaceInfo()

            for target in workspaceInfo.targetInfos {
                request.add(target: SWBConfiguredTarget(guid: target.guid))
            }

            return request
        }
    }

    private var _buildDescriptionID: SWBBuildDescriptionID?
    private var buildDescriptionID: SWBBuildDescriptionID {
        get async throws {
            if let _buildDescriptionID { return _buildDescriptionID }
            self._buildDescriptionID = try await loadBuildDescriptionID()
            return _buildDescriptionID!
        }
    }

    init(projectRoot: AbsolutePath, projectFileName: String, logger: @escaping (LogEntry) -> Void) async throws {
        let service = try await SWBBuildService(connectionMode: .default, variant: .default)
        let xcodeBspFolder = projectRoot.appending(components: ".xcodebsp")

        self.arena = SWBArenaInfo(root: xcodeBspFolder.appending(component: "arena"), indexEnableDataStore: true)
        self.logger = logger

        logger(.info("Creating session..."))

        let (session, diagnosticInfo) = await service.createSession(
            name: projectRoot.pathString,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: xcodeBspFolder.appending(component: "cache").pathString,
            inferiorProductsPath: xcodeBspFolder.appending(component: "inferiorProducts").pathString,
            environment: [:]
        )

        if !diagnosticInfo.isEmpty {
            logger(.warning(diagnosticInfo))
        }

        self.buildServiceSession = try session.get()

        logger(.info("Created session"))

        logger(.info("Loading workspace..."))

        try await buildServiceSession.loadWorkspace(
            containerPath: projectRoot.appending(component: projectFileName).pathString
        )

        logger(.info("Loaded workspace"))

        try await buildServiceSession.setSystemInfo(.default())
    }

    // MARK: - Loaders

    private func loadBuildDescriptionID() async throws -> SWBBuildDescriptionID {
        let buildDescriptionOperation = try await buildServiceSession.createBuildOperationForBuildDescriptionOnly(
            request: buildRequest,
            delegate: self
        )

        var buildDescriptionID: SWBBuildDescriptionID?

        for try await event in try await buildDescriptionOperation.start() {
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

    func loadBuildTargets() async throws -> [BuildTarget] {
        let targets = try await buildServiceSession.configuredTargets(
            buildDescription: try await buildDescriptionID,
            buildRequest: buildRequest
        )

        logger(.info(targets))

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
        try await buildServiceSession.indexCompilerArguments(
            of: SwiftBuild.AbsolutePath(validating: file.pathString),
            in: targetIdentifier.configuredTargetIdentifier,
            buildDescription: buildDescriptionID,
            buildRequest: buildRequest
        )
    }

    // MARK: - Mutators

    func prepareTargets(targets: [BuildTargetIdentifier]) async throws {
        var request = try await buildRequest

        let targetGUIDs = targets.map {
            $0.configuredTargetIdentifier.targetGUID.rawValue
        }

        request.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: targetGUIDs, enableIndexBuildArena: true)

        let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)

        let events = try await buildOperation.start()
        await self.logEvents(events)
        await buildOperation.waitForCompletion()
    }

    func buildIndex() async throws {
        // TODO
    }

    func buildTarget(target: String) async throws {
        var request = try await buildRequest
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
        var request = try await buildRequest
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
    private func logEvents(_ events: AsyncStream<SwiftBuildMessage>) async {
        for try await event in events {
            switch event {
            case .planningOperationStarted(_):
                logger(.log("Planning Build", .begin(.init(title: "Planning Build"))))
            case .planningOperationCompleted(_):
                logger(.info("Build Planning Complete", .end(.init())))
            case .buildStarted(_):
                logger(.log("Building", .begin(.init(title: "Building"))))
            case .buildDiagnostic(let info):
                logger(.log(info.message, .report(.init())))
            case .buildCompleted(let info):
                switch info.result {
                case .ok:
                    logger(.log("Build Complete", .end(.init())))
                case .failed:
                    logger(.log("Build Failed", .end(.init())))
                case .cancelled:
                    logger(.log("Build Cancelled", .end(.init())))
                case .aborted:
                    logger(.log("Build Aborted", .end(.init())))
                }
            case .preparationComplete(_):
                logger(.log("Build Preparation Complete", .end(.init())))
            case .didUpdateProgress(_):
                break
            case .taskStarted(let info):
                logger(
                    .log(info.executionDescription, .begin(.init(title: info.executionDescription))))
            case .taskDiagnostic(let info):
                logger(.log(info.message, .report(.init())))
            case .taskComplete(_):
                break
            case .targetDiagnostic(let info):
                logger(.log(info.message, .report(.init())))
            case .diagnostic(let info):
                logger(.log(info.message, .report(.init())))
            case .backtraceFrame, .reportPathMap, .reportBuildDescription, .preparedForIndex, .buildOutput,
                .targetStarted, .targetComplete, .targetOutput, .targetUpToDate, .taskUpToDate, .taskOutput, .output:
                break
            }
        }
    }
}
